import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/providers.dart';
import '../../../core/auth/kiosk_service.dart';
import '../../../core/sync/sync_models.dart';
import '../../../l10n/app_strings.dart';
import '../../../core/widgets/scanner_camera_view.dart';
import '../../members/data/members_repository.dart';
import '../data/attendance_repository.dart';
import '../domain/attendance_entry.dart';

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  late final AttendanceRepository _repository;
  late final MembersRepository _membersRepo;

  final _input = TextEditingController();
  final _focus = FocusNode();

  final bool _cameraOn = true;
  bool _processing = false;
  String _lastRaw = '';
  DateTime _lastRawAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Étape PIN après scan
  BadgeLookupResult? _activeLookup;
  Uint8List? _activeMemberPhoto;
  String _inputPin = '';
  Timer? _pinTimeout;
  bool _randomizeKeypad = false;
  List<String> _keypadDigits = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];

  // Résultat temporaire après PIN
  ScanOutcome? _lastOutcome;
  Timer? _outcomeDismissTimer;

  bool get _cameraAvailable =>
      kIsWeb ||
      {TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS}.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = AttendanceRepository(runtime.database!, runtime.session!);
    _membersRepo = MembersRepository(runtime.client, runtime.database!, runtime.session!);
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _pinTimeout?.cancel();
    _outcomeDismissTimer?.cancel();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processing || !_cameraOn || _activeLookup != null) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _process(raw);
        break;
      }
    }
  }

  Future<void> _process(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || _processing || _activeLookup != null) return;
    if (trimmed == _lastRaw && DateTime.now().difference(_lastRawAt) < const Duration(seconds: 3)) {
      return;
    }
    _lastRaw = trimmed;
    _lastRawAt = DateTime.now();

    setState(() => _processing = true);
    final runtime = ref.read(appRuntimeProvider);
    final state = runtime.sync?.state.value;
    final scanTime = runtime.sync?.clock.correctedNow ?? DateTime.now().toUtc();

    try {
      final lookup = await _repository.resolveBadge(trimmed);
      if (!mounted) return;

      if (!lookup.requiresPin) {
        // Refus immédiat sans PIN (inconnu, bloqué, vierge)
        final outcome = await _repository.logImmediateDenial(
          lookup,
          scannedAt: scanTime,
          offline: state?.phase == SyncPhase.offline,
          suspectClock: state?.clockSuspect == true,
        );
        _showOutcome(outcome);
      } else {
        // Badge lié : afficher l'overlay de saisie du PIN
        Uint8List? photo;
        if (lookup.member != null) {
          photo = await _membersRepo.localPhoto(lookup.member!.id);
        }

        if (_randomizeKeypad) {
          final digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
          digits.shuffle(Random.secure());
          _keypadDigits = digits;
        }

        setState(() {
          _activeLookup = lookup;
          _activeMemberPhoto = photo;
          _inputPin = '';
        });

        // Annulation automatique après 20 secondes
        _pinTimeout?.cancel();
        _pinTimeout = Timer(const Duration(seconds: 20), () {
          if (mounted && _activeLookup != null) {
            setState(() {
              _activeLookup = null;
              _inputPin = '';
            });
          }
        });
      }
      _input.clear();
      _focus.requestFocus();
    } catch (_) {
      // Erreur de lecture
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _submitPin() async {
    if (_activeLookup == null || _inputPin.isEmpty || _processing) return;
    setState(() => _processing = true);
    _pinTimeout?.cancel();

    final runtime = ref.read(appRuntimeProvider);
    final state = runtime.sync?.state.value;
    final scanTime = runtime.sync?.clock.correctedNow ?? DateTime.now().toUtc();

    try {
      final outcome = await _repository.verifyPinAndGrant(
        badgeResult: _activeLookup!,
        pin: _inputPin,
        scannedAt: scanTime,
        offline: state?.phase == SyncPhase.offline,
        suspectClock: state?.clockSuspect == true,
      );

      final settings = runtime.session?.settings ?? const <String, dynamic>{};
      if (settings['scan_vibrate'] == true) await HapticFeedback.mediumImpact();
      if (settings['scan_sound'] == true) await SystemSound.play(SystemSoundType.click);

      unawaited(runtime.sync?.synchronize());
      _showOutcome(outcome);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _activeLookup = null;
          _inputPin = '';
          _processing = false;
        });
      }
    }
  }

  void _showOutcome(ScanOutcome outcome) {
    _outcomeDismissTimer?.cancel();
    setState(() => _lastOutcome = outcome);
    // Affichage pendant 2.5 secondes puis réinitialisation
    _outcomeDismissTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _lastOutcome = null);
    });
  }

  Future<void> _lockKioskDialog() async {
    final s = AppStrings.of(context);
    final runtime = ref.read(appRuntimeProvider);
    final emailController = TextEditingController(text: runtime.session?.staff['email'] ?? '');
    final passController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.text('lock_kiosk_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.text('lock_kiosk_warning')),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: InputDecoration(labelText: s.text('email')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: InputDecoration(labelText: s.text('password')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.text('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.text('lock_kiosk_confirm')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await runtime.lockKiosk(
          email: emailController.text.trim(),
          password: passController.text,
        );
      } catch (_) {}
    }
  }

  Future<void> _unlockKioskDialog() async {
    final s = AppStrings.of(context);
    final runtime = ref.read(appRuntimeProvider);
    final emailController = TextEditingController();
    final passController = TextEditingController();
    String? errorMsg;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(s.text('unlock_kiosk_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (errorMsg != null) ...[
                Text(s.text(errorMsg!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: emailController,
                decoration: InputDecoration(labelText: s.text('email')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passController,
                obscureText: true,
                decoration: InputDecoration(labelText: s.text('password')),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('cancel'))),
            FilledButton(
              onPressed: () async {
                try {
                  await runtime.unlockKiosk(
                    email: emailController.text.trim(),
                    password: passController.text,
                  );
                  if (context.mounted) Navigator.pop(context);
                } on KioskUnlockFailure catch (e) {
                  setModalState(() => errorMsg = e.code);
                } catch (_) {
                  setModalState(() => errorMsg = 'unlock_credentials_invalid');
                }
              },
              child: Text(s.text('unlock')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final runtime = ref.watch(appRuntimeProvider);
    final session = runtime.session;
    final kioskLocked = runtime.kioskLocked;
    final canLock =
        session != null && (session.isOwner || session.isSupervisor);

    final content = Stack(
      children: [
        // Page de scan principale
        Column(
          children: [
            // Entête / Kiosk Banner anti-collision
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.surface,
              child: Row(
                children: [
                  if (!kioskLocked) ...[
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft),
                      tooltip: s.text('back'),
                      onPressed: () => context.go('/'),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: GestureDetector(
                      onLongPress: kioskLocked ? _unlockKioskDialog : null,
                      child: Row(
                        children: [
                          Icon(LucideIcons.dumbbell, color: theme.colorScheme.primary, size: 24),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              session?.name ?? 'GYMDESK',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat.Hm().format(DateTime.now()),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  if (!kioskLocked && canLock)
                    IconButton.filledTonal(
                      icon: const Icon(LucideIcons.lock, size: 18),
                      tooltip: s.text('lock_scanner_kiosk'),
                      onPressed: _lockKioskDialog,
                    ),
                  if (kioskLocked)
                    IconButton(
                      icon: const Icon(LucideIcons.keyRound, size: 20),
                      tooltip: s.text('unlock'),
                      onPressed: _unlockKioskDialog,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Zone scanner et lecteur USB responsive
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 640;

                  Widget buildCameraView({required double height}) {
                    if (!_cameraAvailable || !_cameraOn) return const SizedBox.shrink();
                    return SizedBox(
                      height: height,
                      width: double.infinity,
                      child: ScannerCameraView(
                        onDetect: _onDetect,
                        overlay: Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.primary.withAlpha(200),
                              width: 2.5,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    );
                  }

                  if (isMobile) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          buildCameraView(height: 230),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _input,
                            focusNode: _focus,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: s.text('scan_badge_usb_hint'),
                              prefixIcon: const Icon(LucideIcons.barcode),
                              suffixIcon: IconButton(
                                icon: const Icon(LucideIcons.arrowRight),
                                onPressed: () => _process(_input.text),
                              ),
                              helperText: s.text('scan_hardware_hint'),
                            ),
                            onSubmitted: _process,
                          ),
                          const SizedBox(height: 16),
                          _buildOutcomeBanner(s, theme),
                        ],
                      ),
                    );
                  }

                  // Grand écran / Ordinateur de réception
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        // Colonne gauche : Saisie USB + Feedback
                        Expanded(
                          flex: 5,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextField(
                                controller: _input,
                                focusNode: _focus,
                                autofocus: true,
                                decoration: InputDecoration(
                                  labelText: s.text('scan_badge_usb_hint'),
                                  prefixIcon: const Icon(LucideIcons.barcode),
                                  suffixIcon: IconButton(
                                    icon: const Icon(LucideIcons.arrowRight),
                                    onPressed: () => _process(_input.text),
                                  ),
                                  helperText: s.text('scan_hardware_hint'),
                                ),
                                onSubmitted: _process,
                              ),
                              const SizedBox(height: 24),
                              _buildOutcomeBanner(s, theme),
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),
                        // Colonne droite : Caméra grand format
                        if (_cameraAvailable && _cameraOn)
                          Expanded(
                            flex: 5,
                            child: buildCameraView(height: 380),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        // Overlay PIN membre plein écran
        if (_activeLookup != null)
          _buildPinOverlay(s, theme),
      ],
    );

    if (kioskLocked) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          body: SafeArea(child: content),
        ),
      );
    }

    return content;
  }

  Widget _buildOutcomeBanner(AppStrings s, ThemeData theme) {
    if (_lastOutcome == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(LucideIcons.scanLine, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 10),
            Text(
              s.text('scan_badge_prompt'),
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final outcome = _lastOutcome!;
    final isGranted = outcome.result == 'granted';
    final isExit = outcome.isCheckOut || outcome.message == 'goodbye_member';

    final Color color;
    final IconData icon;
    final String greetingTitle;

    if (isGranted) {
      if (isExit) {
        color = Colors.teal;
        icon = LucideIcons.logOut;
        greetingTitle = s.text('goodbye_member');
      } else {
        color = Colors.green;
        icon = LucideIcons.circleCheck;
        greetingTitle = s.text('welcome_member');
      }
    } else {
      final isExp = outcome.result == 'denied_expired' || outcome.result == 'denied_pending_renewal';
      color = isExp ? Colors.orange : theme.colorScheme.error;
      icon = LucideIcons.circleAlert;
      greetingTitle = s.text(outcome.message);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 44),
          const SizedBox(height: 8),
          Text(
            greetingTitle,
            style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          if (outcome.member != null) ...[
            const SizedBox(height: 6),
            Text(
              outcome.member!.fullName,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isExit
                    ? '${s.text('check_out_recorded')} • #${outcome.entry?.entryNumberToday ?? 1}'
                    : '${s.text('check_in_recorded')} • #${outcome.entry?.entryNumberToday ?? 1}',
                style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPinOverlay(AppStrings s, ThemeData theme) {
    final member = _activeLookup!.member!;
    return Container(
      color: Colors.black.withAlpha(200),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          elevation: 8,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Photo et prénom du membre pour contrôle visuel
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: _activeMemberPhoto != null ? MemoryImage(_activeMemberPhoto!) : null,
                      child: _activeMemberPhoto == null
                          ? Text(member.firstName.isNotEmpty ? member.firstName[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(member.firstName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                          Text(s.text('enter_pin_to_access'), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => setState(() => _activeLookup = null),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Points masqués du PIN
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    final filled = i < _inputPin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? theme.colorScheme.primary : Colors.transparent,
                        border: Border.all(color: theme.colorScheme.primary, width: 2),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),

                // Pavé tactile (option disposition aléatoire)
                _buildKeypad(theme),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      icon: Icon(_randomizeKeypad ? LucideIcons.shuffle : LucideIcons.arrowDownUp, size: 16),
                      label: Text(s.text('randomize_keys')),
                      onPressed: () {
                        setState(() {
                          _randomizeKeypad = !_randomizeKeypad;
                          if (_randomizeKeypad) {
                            _keypadDigits.shuffle(Random.secure());
                          } else {
                            _keypadDigits = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
                          }
                        });
                      },
                    ),
                    FilledButton(
                      onPressed: _inputPin.length >= 4 ? _submitPin : null,
                      child: Text(s.text('validate')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad(ThemeData theme) {
    return Column(
      children: [
        for (int r = 0; r < 3; r++)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int c = 0; c < 3; c++)
                _keyButton(_keypadDigits[r * 3 + c]),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 80, height: 56),
            _keyButton(_keypadDigits[9]),
            SizedBox(
              width: 80,
              height: 56,
              child: IconButton(
                icon: const Icon(LucideIcons.delete),
                onPressed: () {
                  if (_inputPin.isNotEmpty) {
                    setState(() => _inputPin = _inputPin.substring(0, _inputPin.length - 1));
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _keyButton(String digit) {
    return Container(
      margin: const EdgeInsets.all(4),
      width: 72,
      height: 54,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: EdgeInsets.zero,
        ),
        onPressed: () {
          if (_inputPin.length < 6) {
            setState(() => _inputPin += digit);
          }
        },
        child: Text(digit, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
