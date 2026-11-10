import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/access_control/access_monitor.dart';
import '../../../core/biometrics/access_agent_client.dart';
import '../../../core/biometrics/biometric_models.dart';
import '../../../core/sync/sync_models.dart';
import '../../../l10n/app_strings.dart';
import '../../subscriptions/data/subscriptions_repository.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../domain/member.dart';

class FingerprintEnrollmentDialog extends ConsumerStatefulWidget {
  const FingerprintEnrollmentDialog({
    super.key,
    required Member this.member,
    required this.onSaved,
  })  : displayName = null,
        subtitle = null,
        onCaptured = null;

  /// Menm popup anrejistreman an, pou lòt moun pase manm (ex. anplwaye yo):
  /// [onCaptured] resevwa kapti yo epi anrejistre yo.
  const FingerprintEnrollmentDialog.generic({
    super.key,
    required String this.displayName,
    this.subtitle,
    required Future<void> Function(List<String> captures) this.onCaptured,
    required this.onSaved,
  }) : member = null;

  final Member? member;
  final String? displayName;
  final String? subtitle;
  final Future<void> Function(List<String> captures)? onCaptured;
  final VoidCallback onSaved;

  static Future<void> show(
    BuildContext context, {
    required Member member,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FingerprintEnrollmentDialog(
        member: member,
        onSaved: onSaved,
      ),
    );
  }

  static Future<void> showGeneric(
    BuildContext context, {
    required String displayName,
    String? subtitle,
    required Future<void> Function(List<String> captures) onCaptured,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FingerprintEnrollmentDialog.generic(
        displayName: displayName,
        subtitle: subtitle,
        onCaptured: onCaptured,
        onSaved: onSaved,
      ),
    );
  }

  @override
  ConsumerState<FingerprintEnrollmentDialog> createState() =>
      _FingerprintEnrollmentDialogState();
}

class _FingerprintEnrollmentDialogState
    extends ConsumerState<FingerprintEnrollmentDialog> {
  /// Yon sèl kapti (bon kalite) ase: anrejistreman an rapid (< 5 s).
  static const int _required = 1;
  int _currentStep = 1;
  final List<String> _captures = [];
  bool _busy = false;
  String _hint = '';
  StreamSubscription<BiometricEvent>? _eventSub;
  bool _useTerminal = false;
  bool _scanningTerminal = false;
  String? _lastScanError;

  @override
  void initState() {
    super.initState();
    final defaultReader = AccessMonitor.instance.config.defaultEnrollmentReader;
    final bio = ref.read(biometricServiceProvider);

    final isTerminalOnline = AccessMonitor.instance.terminalOnline.value || bio.terminalAvailable;
    AccessMonitor.instance.terminalOnline.addListener(_onTerminalOnlineChanged);

    if (defaultReader == 'terminal_bew2') {
      _useTerminal = true;
    } else if (defaultReader == 'usb_biomini') {
      _useTerminal = false;
    } else {
      // auto: prefere USB sou biwo a si li branche, sinon lekte pot la
      _useTerminal = !bio.readerAvailable;
    }

    _eventSub = bio.events.listen(_onBiometricEvent);

    if (_useTerminal) {
      if (isTerminalOnline) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_busy && !_scanningTerminal) {
            _startTerminalScan();
          }
        });
      } else {
        _hint = '⚠️ Lektè sou pòt la (BioEntry W2) pa konekte nan rezo a (192.168.1.41). Tcheke fil rezo a oswa konekte BioMini USB.';
      }
    } else {
      bio.startCapture();
    }
    _updateHint();
  }

  void _onTerminalOnlineChanged() {
    if (!mounted) return;
    unawaited(ref.read(biometricServiceProvider).agent.checkHealth());
    _updateHint();
  }

  @override
  void dispose() {
    AccessMonitor.instance.terminalOnline.removeListener(_onTerminalOnlineChanged);
    _eventSub?.cancel();
    ref.read(biometricServiceProvider).stopCapture();
    super.dispose();
  }

  void _updateHint() {
    setState(() {
      if (_useTerminal) {
        final bio = ref.read(biometricServiceProvider);
        final isOnline = AccessMonitor.instance.active
            ? AccessMonitor.instance.terminalOnline.value
            : (AccessMonitor.instance.terminalOnline.value || bio.terminalAvailable);
        if (!isOnline) {
          _hint = '⚠️ Lektè sou pòt la (BioEntry W2) pa konekte nan rezo a (192.168.1.41). Tcheke fil rezo a oswa konekte BioMini USB.';
        } else {
          _hint = _scanningTerminal
              ? '🟢 Lektè pòt la pare! Mete dwèt la sou li kounye a...'
              : 'Mete moun nan devan pòt la, epi klike sou "Kòmanse Eskane sou Pòt la".';
        }
      } else {
        _hint = _required == 1
            ? 'Poze dwèt la byen plat sou lektè a'
            : 'Poze dwèt la sou lektè a (Kapti $_currentStep/$_required)';
      }
    });
  }

  void _onBiometricEvent(BiometricEvent event) {
    if (_busy) return;
    if (event.type == 'terminal_ready_to_scan') {
      setState(() => _hint = '🟢 Lektè pòt la limen! Mete dwèt la sou li kounye a...');
    } else if (event.type == 'fingerprint_captured' && event.template != null) {
      _processCapture(event.template!);
    } else if (event.type == 'low_quality') {
      setState(() => _hint = event.message ?? 'Kalite pa ase. Repoze dwèt la byen plat.');
    } else if (event.type == 'waiting_finger') {
      _updateHint();
    }
  }

  Future<void> _startTerminalScan() async {
    if (_busy || _scanningTerminal) return;
    setState(() {
      _scanningTerminal = true;
      _hint = 'Ap konekte ak pòt la... tann lektè a pare.';
    });
    try {
      final bio = ref.read(biometricServiceProvider);
      final cap = await bio.captureFromTerminal(
        terminalIp: AccessMonitor.instance.config.terminalIp,
      );
      if (!mounted) return;
      setState(() {
        _scanningTerminal = false;
        _hint = 'Anprent detekte sou pòt la! Ap anrejistre...';
      });
      await _processCapture(cap.template);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanningTerminal = false;
        _hint = 'Echèk eskan sou pòt la: $e. Klike pou re-eseye.';
      });
    }
  }

  Future<void> _processCapture(String template) async {
    if (_captures.length >= _currentStep) return;

    // Lè gen plizyè kapti, yo dwe matche ak premye a (menm dwèt).
    if (_captures.isNotEmpty) {
      final bio = ref.read(biometricServiceProvider);
      final res = await bio.match1to1(
        candidateTemplate: template,
        enrolledTemplate: _captures.first,
      );
      if (!mounted) return;
      if (!res.isMatch) {
        setState(() => _hint =
            'Anprent sa a pa koresponn ak premye a. Itilize menm dwèt la (Kapti $_currentStep/$_required).');
        return;
      }
    }

    setState(() {
      _captures.add(template);
      if (_captures.length < _required) {
        _currentStep++;
        _updateHint();
      } else {
        _hint = 'Anprent kaptire! Ap anrejistre...';
        _saveEnrollment();
      }
    });
  }

  Future<void> _saveEnrollment() async {
    if (_captures.length < _required) return;
    setState(() => _busy = true);

    final template = _captures.last; // Final validated template
    final runtime = ref.read(appRuntimeProvider);

    try {
      final generic = widget.onCaptured;
      if (generic != null) {
        await generic(List.unmodifiable(_captures));
      } else {
        final member = widget.member!;
        // 1. Ekri dirèkteman sou Supabase si gen rezo
        try {
          await runtime.client.rpc('register_member_fingerprint', params: {
            'p_member': member.id,
            'p_template': template,
          });
        } catch (e) {
          debugPrint('Supabase direct biometric registration error: $e');
          try {
            await runtime.client.from('members').update({
              'fingerprint_template': template,
              'fingerprint_registered': true,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('id', member.id);
          } catch (_) {}
        }

        // 2. Mete ajou baz done Drift lokal la
        final now = runtime.sync?.clock.correctedNow ?? DateTime.now().toUtc();
        final updatedRow = {
          ...member.row,
          'fingerprint_template': template,
          'fingerprint_registered': true,
          'updated_at': now.toIso8601String(),
        };

        await runtime.database?.save(
          SyncEntity.members,
          updatedRow,
          changedAt: now,
        );

        // Pouse anprent lan imedyatman (< 300ms) sou tèminal IP BioEntry W2 a
        if (runtime.database != null && runtime.session != null) {
          try {
            final subs = await SubscriptionsRepository(runtime.database!, runtime.session!).forMember(member.id);
            final activeSubs = subs.where((s) => s.deletedAt == null && s.status != 'cancelled').toList()
              ..sort((a, b) => b.endDate.compareTo(a.endDate));
            final startDate = activeSubs.isNotEmpty ? activeSubs.first.startDate : dateOnly(DateTime.now());
            final endDate = activeSubs.isNotEmpty
                ? activeSubs.first.endDate
                : subscriptionEnd(dateOnly(DateTime.now()), 30);
            final tmpls = <String>[template];
            if (member.row['fingerprint_backup_template'] is String &&
                (member.row['fingerprint_backup_template'] as String).isNotEmpty) {
              tmpls.add(member.row['fingerprint_backup_template'] as String);
            }
            await AccessAgentClient().syncTerminalMember(
              userId: member.id,
              name: member.fullName,
              startDate: startDate,
              endDate: endDate,
              templates: tmpls,
              terminalIp: AccessMonitor.instance.config.terminalIp,
            );
            // Ouvri relè pòt la pou valide pou manm lan touswit
            unawaited(AccessAgentClient().pulseTerminalRelay(
              terminalIp: AccessMonitor.instance.config.terminalIp,
              seconds: 2,
            ));
          } catch (_) {}
        }
      }

      // 3. Senkronize imedyatman sou W2 ak Cloud
      AccessMonitor.instance.invalidate();
      unawaited(AccessMonitor.instance.syncNow());
      unawaited(runtime.sync?.synchronize());

      widget.onSaved();

      if (mounted) {
        final name = widget.member?.fullName ?? widget.displayName ?? '';
        Navigator.pop(context);
        final successMsg = _useTerminal
            ? 'Anprent anrejistre epi valide sou pòt la avèk siksè pou $name!'
            : 'Anprent anrejistre avèk siksè pou $name!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xff1f6f4a),
            content: Text(successMsg),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('${AppStrings.of(context).text('fingerprint_enroll_error')}: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final bio = ref.watch(biometricServiceProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.fingerprint, size: 28, color: Color(0xff1f6f4a)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Anrejistre Anprent',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              widget.member?.fullName ?? widget.displayName ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              widget.member?.memberNumber ?? widget.subtitle ?? '',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            // Chwa Lektè: USB (BioMini) oswa Pòt la (BioEntry W2)
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  icon: Icon(LucideIcons.usb, size: 16),
                  label: Text('Lektè USB (BioMini)'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  icon: Icon(LucideIcons.doorClosed, size: 16),
                  label: Text('Lektè Pòt la (W2)'),
                ),
              ],
              selected: {_useTerminal},
              onSelectionChanged: _busy ? null : (set) {
                final val = set.first;
                if (val == _useTerminal) return;
                setState(() {
                  _useTerminal = val;
                  _scanningTerminal = false;
                  _updateHint();
                });
                final bio = ref.read(biometricServiceProvider);
                if (_useTerminal) {
                  bio.stopCapture();
                  _startTerminalScan();
                } else {
                  bio.startCapture();
                }
              },
            ),
            const SizedBox(height: 14),

            if (!bio.readerAvailable && _useTerminal) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.info, size: 18, color: Color(0xFF1D4ED8)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'BioMini USB pa monte. Anrejistreman an ap fèt dirèkteman sou lektè pòt la (BioEntry W2).',
                        style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (_required > 1) Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var step = 1; step <= _required; step++) ...[
                  _buildStepIndicator(step),
                  if (step < _required)
                    Container(
                      width: 40,
                      height: 3,
                      color: _captures.length >= step
                          ? const Color(0xff1f6f4a)
                          : Colors.grey.shade300,
                    ),
                ],
              ],
            ),
            if (_required > 1) const SizedBox(height: 16),

            // Fingerprint / Door Visual Icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: _captures.length >= _currentStep
                    ? const Color(0xff1f6f4a).withAlpha(30)
                    : (_useTerminal ? const Color(0xFF0F766E).withAlpha(20) : Colors.grey.shade100),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _captures.length >= _currentStep
                      ? const Color(0xff1f6f4a)
                      : (_useTerminal ? const Color(0xFF0F766E) : Colors.grey.shade400),
                  width: 2,
                ),
              ),
              child: Icon(
                _captures.length >= _required
                    ? LucideIcons.circleCheck
                    : (_useTerminal ? LucideIcons.doorClosed : LucideIcons.fingerprint),
                size: 52,
                color: _captures.length >= _currentStep
                    ? const Color(0xff1f6f4a)
                    : (_useTerminal ? const Color(0xFF0F766E) : Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              _hint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            // Bouton pou lanse eskan sou pòt la
            if (_useTerminal && _captures.length < _required) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: (_busy || _scanningTerminal) ? null : _startTerminalScan,
                icon: _scanningTerminal
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(LucideIcons.scanLine, size: 20),
                label: Text(
                  _scanningTerminal
                      ? 'Ap koute lektè pòt la...'
                      : 'Kòmanse Eskane sou Pòt la',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(height: 12),
              if (_lastScanError != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(LucideIcons.circleAlert, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _lastScanError!,
                              style: TextStyle(color: Colors.red.shade900, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0F766E),
                          side: const BorderSide(color: Color(0xFF0F766E)),
                        ),
                        onPressed: () {
                          setState(() {
                            _useTerminal = false;
                            _lastScanError = null;
                            _updateHint();
                          });
                          ref.read(biometricServiceProvider).startCapture();
                        },
                        icon: const Icon(LucideIcons.usb, size: 16),
                        label: const Text('Itilize Lektè USB BioMini pito'),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            // Status Badge (eta reyèl lektè a)
            if (!_useTerminal)
              ValueListenableBuilder<BiometricSensorState>(
                valueListenable: bio.state,
                builder: (context, st, _) {
                  final ok = st == BiometricSensorState.ready ||
                      st == BiometricSensorState.waitingFinger ||
                      st == BiometricSensorState.capturing;
                  final serial = bio.agent.status.value.readerSerial;
                  final label = ok
                      ? 'Lektè USB konekte${serial != null && serial.isNotEmpty ? ' ($serial)' : ''}'
                      : bio.unavailableReason;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ok ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 10, color: ok ? Colors.green : Colors.orange),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              color: ok ? Colors.green.shade800 : Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: bio.terminalAvailable ? Colors.green.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 10, color: bio.terminalAvailable ? Colors.green : Colors.blue),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Pòt: BioEntry W2 (${bio.agent.status.value.terminalIp ?? "192.168.1.41"})',
                        style: TextStyle(
                          fontSize: 12,
                          color: bio.terminalAvailable ? Colors.green.shade800 : Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (_busy) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(s.text('cancel')),
        ),
      ],
    );
  }

  Widget _buildStepIndicator(int step) {
    final isDone = _captures.length >= step;
    final isCurrent = _currentStep == step;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDone
            ? const Color(0xff1f6f4a)
            : (isCurrent ? Colors.orange.shade600 : Colors.grey.shade200),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: isDone
            ? const Icon(LucideIcons.check, size: 20, color: Colors.white)
            : Text(
                '$step',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isCurrent ? Colors.white : Colors.grey.shade700,
                ),
              ),
      ),
    );
  }
}
