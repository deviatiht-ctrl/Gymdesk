import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/biometrics/biometric_models.dart';
import '../../../core/sync/sync_models.dart';
import '../../../l10n/app_strings.dart';
import '../domain/member.dart';

class FingerprintEnrollmentDialog extends ConsumerStatefulWidget {
  const FingerprintEnrollmentDialog({
    super.key,
    required this.member,
    required this.onSaved,
  });

  final Member member;
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
        1 => 'Poze dwèt la sou lektè DigitalPersona a (Kapti 1/3)',
        2 => 'Retire dwèt la epi repoze l ankò (Kapti 2/3)',
        _ => 'Repoze l yon dènye fwa pou konfimasyon (Kapti 3/3)',
      };
    });
  }

  void _onBiometricEvent(BiometricEvent event) {
    if (_busy) return;
    if (event.type == 'fingerprint_captured' && event.template != null) {
      _processCapture(event.template!);
    } else if (event.type == 'waiting_finger') {
      _updateHint();
    }
  }

  void _processCapture(String template) {
    if (_captures.length >= _currentStep) return;
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

  /// Simile yon kapti pou anviwònman tès oswa Web kote lektè a pa ploge
  void _simulateCapture() {
    final rand = Random();
    final bytes = List<int>.generate(
      512,
      (i) => (widget.member.id.hashCode + i + rand.nextInt(3)) % 256,
    );
    final simulatedTemplate = base64Encode(bytes);
    _processCapture(simulatedTemplate);
  }

  Future<void> _saveEnrollment() async {
    if (_captures.length < 3) return;
    setState(() => _busy = true);

    final template = _captures.last; // Final validated template
    final runtime = ref.read(appRuntimeProvider);

    try {
      // 1. Ekri dirèkteman sou Supabase si gen rezo
      try {
        await runtime.client.rpc('register_member_fingerprint', params: {
          'p_member': widget.member.id,
          'p_template': template,
        });
      } catch (e) {
        debugPrint('Supabase direct biometric registration error: $e');
        try {
          await runtime.client.from('members').update({
            'fingerprint_template': template,
            'fingerprint_registered': true,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', widget.member.id);
        } catch (_) {}
      }

      // 2. Mete ajou baz done Drift lokal la
      final now = runtime.sync?.clock.correctedNow ?? DateTime.now().toUtc();
      final updatedRow = {
        ...widget.member.row,
        'fingerprint_template': template,
        'fingerprint_registered': true,
        'updated_at': now.toIso8601String(),
      };

      await runtime.database?.save(
        SyncEntity.members,
        updatedRow,
        changedAt: now,
      );

      // 3. Senkronize imedyatman
      unawaited(runtime.sync?.synchronize());

      widget.onSaved();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xff1f6f4a),
            content: Text(
              'Anprent anrejistre avèk siksè pou ${widget.member.fullName}!',
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
            content: Text(': '),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final bioState = ref.watch(biometricServiceProvider).state.value;

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
              widget.member.fullName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              widget.member.memberNumber,
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

            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: bioState == BiometricSensorState.ready ||
                        bioState == BiometricSensorState.waitingFinger
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: bioState == BiometricSensorState.ready ||
                            bioState == BiometricSensorState.waitingFinger
                        ? Colors.green
                        : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    bioState == BiometricSensorState.ready ||
                            bioState == BiometricSensorState.waitingFinger
                        ? 'Lektè U.are.U 4500 Konekte'
                        : 'Lektè ap tann USB...',
                    style: TextStyle(
                      fontSize: 12,
                      color: bioState == BiometricSensorState.ready ||
                              bioState == BiometricSensorState.waitingFinger
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),

            if (_busy) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],

            const SizedBox(height: 12),
            // Bouton pou teste/simile si lektè USB a pa ploge sou machin dev la
            TextButton.icon(
              onPressed: _busy ? null : _simulateCapture,
              icon: const Icon(LucideIcons.sparkles, size: 16),
              label: Text(
                'Simile Kapti Dwèt (Kapti /3)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
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
                '',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isCurrent ? Colors.white : Colors.grey.shade700,
                ),
              ),
      ),
    );
  }
}
