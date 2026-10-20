import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../app/runtime.dart';
import '../../../core/biometrics/biometric_models.dart';
import '../../../features/staff/domain/staff_profile.dart';
import '../../../l10n/app_strings.dart';

class UnlockPage extends ConsumerStatefulWidget {
  const UnlockPage({super.key});
  @override
  ConsumerState<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends ConsumerState<UnlockPage> {
  final _controller = TextEditingController();
  StreamSubscription<BiometricEvent>? _eventSub;
  bool _scanning = false;
  String? _biometricError;

  @override
  void initState() {
    super.initState();
    final bio = ref.read(biometricServiceProvider);
    _eventSub = bio.events.listen((event) {
      if (event.type == 'fingerprint_captured' && event.template != null) {
        _verifyFingerprint(event.template!);
      }
    });
    bio.startCapture();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    ref.read(biometricServiceProvider).stopCapture();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    await ref.read(appRuntimeProvider).unlock(_controller.text);
    if (mounted && ref.read(appRuntimeProvider).phase == SessionPhase.ready) {
      _controller.clear();
    }
  }

  Future<void> _scanFingerprint() async {
    if (_scanning || ref.read(appRuntimeProvider).busy) return;
    setState(() {
      _scanning = true;
      _biometricError = null;
    });

    final bio = ref.read(biometricServiceProvider);
    bio.startCapture();

    try {
      final sample = await bio.captureFingerprintSample().timeout(const Duration(seconds: 15));
      if (sample.isNotEmpty) {
        await _verifyFingerprint(sample);
      } else {
        if (mounted) {
          setState(() {
            _scanning = false;
            _biometricError = AppStrings.of(context).text('fingerprint_unrecognized');
          });
        }
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _scanning = false;
          _biometricError = 'Délai d’attente dépassé. Réessayez.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _biometricError = e.toString();
        });
      }
    } finally {
      if (mounted && !_scanning) {
        bio.stopCapture();
      }
    }
  }

  Future<void> _verifyFingerprint(String template) async {
    if (_scanning) {
      setState(() => _scanning = false);
    }
    final runtime = ref.read(appRuntimeProvider);
    if (runtime.busy) return;

    setState(() {
      _biometricError = null;
    });

    try {
      final db = runtime.database;
      if (db == null) return;

      // 1. Charger tout le personnel depuis Drift
      final rows = await db.customSelect(
        "SELECT payload FROM records WHERE entity = 'staff' AND deleted_at IS NULL",
        readsFrom: {db.records},
      ).get();

      final staffList = rows.map((r) {
        final payload = jsonDecode(r.read<String>('payload')) as Map<String, dynamic>;
        return StaffProfile.fromJson(payload);
      }).where((s) => s.active && s.fingerprintRegistered && s.fingerprintTemplate != null).toList();

      if (staffList.isEmpty) {
        if (mounted) {
          setState(() {
            _biometricError = AppStrings.of(context).text('no_staff_fingerprint');
          });
        }
        return;
      }

      // 2. Recherche 1:N
      final bio = ref.read(biometricServiceProvider);
      StaffProfile? matched;

      final candidates = <Map<String, String>>[];
      final byId = <String, StaffProfile>{};
      for (final s in staffList) {
        byId[s.id] = s;
        if (s.fingerprintTemplate != null && s.fingerprintTemplate!.isNotEmpty) {
          candidates.add({'id': s.id, 'template': s.fingerprintTemplate!});
        }
        if (s.fingerprintBackupTemplate != null && s.fingerprintBackupTemplate!.isNotEmpty) {
          candidates.add({'id': s.id, 'template': s.fingerprintBackupTemplate!});
        }
      }

      final identifiedId = await bio.agent.identify(template, candidates);
      if (identifiedId != null && byId.containsKey(identifiedId)) {
        matched = byId[identifiedId];
      }

      if (matched == null) {
        for (final candidate in candidates) {
          final res = await bio.match1to1(
            candidateTemplate: template,
            enrolledTemplate: candidate['template']!,
          );
          if (res.isMatch) {
            matched = byId[candidate['id']];
            break;
          }
        }
      }

      if (matched != null) {
        await runtime.unlockWithStaff(matched);
        if (mounted) {
          final s = AppStrings.of(context);
          final jobTitle = matched.jobTitle;
          final jobLabel = switch (jobTitle) {
            'caissier' => s.text('job_title_cashier'),
            'secretaire' => s.text('job_title_secretary'),
            'superviseur' => s.text('job_title_supervisor'),
            _ => matched.role == 'owner' ? s.text('owner') : s.text(matched.role),
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xff1f6f4a),
              content: Text(
                s.text('staff_unlocked').replaceAll('{name}', matched.fullName).replaceAll('{job}', jobLabel),
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() {
            _biometricError = AppStrings.of(context).text('fingerprint_unrecognized');
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _biometricError = 'Erreur : $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(appRuntimeProvider);
    final s = AppStrings.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(LucideIcons.lockKeyhole, size: 40),
                  const SizedBox(height: 20),
                  Text(
                    s.text('unlock_session'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.text('scan_fingerprint_hint'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Panneau Empreinte USB
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _scanning ? const Color(0xFFBBF7D0) : Colors.white,
                          ),
                          child: const Icon(
                            LucideIcons.fingerprint,
                            size: 48,
                            color: Color(0xFF15803D),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          s.text('scan_fingerprint_to_unlock'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF166534),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _scanning ? 'En attente de votre doigt...' : s.text('scan_fingerprint_hint'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: (_scanning || runtime.busy) ? null : _scanFingerprint,
                          icon: _scanning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(LucideIcons.fingerprint, size: 18),
                          label: Text(_scanning ? 'Scan en cours...' : s.text('scan_fingerprint_to_unlock')),
                        ),
                      ],
                    ),
                  ),

                  if (_biometricError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.circleAlert, size: 18, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _biometricError!,
                                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          s.text('or_with_pin'),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _controller,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.number,
                    maxLength: 12,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _unlock(),
                    decoration: InputDecoration(
                      labelText: s.text('pin'),
                      counterText: '',
                      prefixIcon: const Icon(LucideIcons.keyRound, size: 18),
                    ),
                  ),
                  if (runtime.errorCode != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        s.text(runtime.errorCode!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if ({'pin_storage', 'pin_missing', 'pin_password_required'}
                      .contains(runtime.errorCode))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        s.text('pin_use_password_hint'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: runtime.busy ? null : _unlock,
                    icon: runtime.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.lockOpen),
                    label: Text(
                      s.text(runtime.busy ? 'verifying' : 'unlock'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: runtime.busy ? null : runtime.signOut,
                    child: Text(s.text('use_password')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
