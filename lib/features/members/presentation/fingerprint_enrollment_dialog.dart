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

  /// Menm popup 3 kapti a, pou lòt moun pase manm (ex. anplwaye yo):
  /// [onCaptured] resevwa 3 kapti yo (menm dwèt, verifye) epi anrejistre yo.
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
  int _currentStep = 1; // 1, 2, 3
  final List<String> _captures = [];
  bool _busy = false;
  String _hint = '';
  StreamSubscription<BiometricEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    final bio = ref.read(biometricServiceProvider);
    _eventSub = bio.events.listen(_onBiometricEvent);
    bio.startCapture();
    _updateHint();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    ref.read(biometricServiceProvider).stopCapture();
    super.dispose();
  }

  void _updateHint() {
    setState(() {
      _hint = switch (_currentStep) {
        1 => 'Poze dwèt la sou lektè a (Kapti 1/3)',
        2 => 'Retire dwèt la epi repoze l ankò (Kapti 2/3)',
        _ => 'Repoze l yon dènye fwa pou konfimasyon (Kapti 3/3)',
      };
    });
  }

  void _onBiometricEvent(BiometricEvent event) {
    if (_busy) return;
    if (event.type == 'fingerprint_captured' && event.template != null) {
      _processCapture(event.template!);
    } else if (event.type == 'low_quality') {
      setState(() => _hint = event.message ?? 'Kalite pa ase. Repoze dwèt la byen plat.');
    } else if (event.type == 'waiting_finger') {
      _updateHint();
    }
  }

  Future<void> _processCapture(String template) async {
    if (_captures.length >= _currentStep) return;

    // Kapti 2 ak 3 dwe matche ak premye a (menm dwèt).
    if (_captures.isNotEmpty) {
      final bio = ref.read(biometricServiceProvider);
      final res = await bio.match1to1(
        candidateTemplate: template,
        enrolledTemplate: _captures.first,
      );
      if (!mounted) return;
      if (!res.isMatch) {
        setState(() => _hint =
            'Anprent sa a pa koresponn ak premye a. Itilize menm dwèt la (Kapti $_currentStep/3).');
        return;
      }
    }

    setState(() {
      _captures.add(template);
      if (_currentStep < 3) {
        _currentStep++;
        _updateHint();
      } else {
        _hint = 'Tout 3 kapti yo fin fèt! Ap anrejistre...';
        _saveEnrollment();
      }
    });
  }

  Future<void> _saveEnrollment() async {
    if (_captures.length < 3) return;
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
            unawaited(
              AccessAgentClient()
                  .syncTerminalMember(
                    userId: member.id,
                    name: member.fullName,
                    startDate: startDate,
                    endDate: endDate,
                    templates: tmpls,
                    terminalIp: AccessMonitor.instance.config.terminalIp,
                  )
                  .catchError((_) => false),
            );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xff1f6f4a),
            content: Text(
              'Anprent anrejistre avèk siksè pou $name!',
            ),
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
            const SizedBox(height: 24),

            // 3-Step Circles Progress Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var step = 1; step <= 3; step++) ...[
                  _buildStepIndicator(step),
                  if (step < 3)
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
            const SizedBox(height: 24),

            // Fingerprint Visual Icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: _captures.length >= _currentStep
                    ? const Color(0xff1f6f4a).withAlpha(30)
                    : Colors.grey.shade100,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _captures.length >= _currentStep
                      ? const Color(0xff1f6f4a)
                      : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: Icon(
                _captures.length == 3
                    ? LucideIcons.circleCheck
                    : LucideIcons.fingerprint,
                size: 56,
                color: _captures.length >= _currentStep
                    ? const Color(0xff1f6f4a)
                    : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),

            Text(
              _hint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            // Status Badge (eta reyèl lektè a)
            ValueListenableBuilder<BiometricSensorState>(
              valueListenable: bio.state,
              builder: (context, st, _) {
                final ok = st == BiometricSensorState.ready ||
                    st == BiometricSensorState.waitingFinger ||
                    st == BiometricSensorState.capturing;
                final serial = bio.agent.status.value.readerSerial;
                final label = ok
                    ? 'Lektè konekte${serial != null && serial.isNotEmpty ? ' ($serial)' : ''}'
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
