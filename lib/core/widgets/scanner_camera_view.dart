import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/app_strings.dart';

/// Vue caméra de scan QR robuste, partagée par le scanner de présence et
/// l'activation de carte.
///
/// Pourquoi un widget dédié :
/// * Le [MobileScannerController] appartient à ce State. Placé sous une
///   `GlobalKey`, il survit aux changements de mise en page (rotation
///   tablette, passage mobile ↔ large) au lieu d'être détruit/recréé.
/// * Toutes les opérations caméra (start/stop/switch) sont sérialisées dans
///   une file : jamais deux appels concurrents vers le plugin natif (cause
///   classique de `controllerAlreadyInitialized` / `genericError`).
/// * Cycle de vie : arrêt quand l'app passe en arrière-plan, redémarrage au
///   retour (y compris après avoir accordé la permission dans Paramètres).
/// * Repli automatique sur la caméra frontale si l'arrière est absente.
/// * Erreurs explicites : permission refusée (+ bouton Paramètres), caméra
///   indisponible, ou détail technique de l'erreur pour le diagnostic.
class ScannerCameraView extends StatefulWidget {
  const ScannerCameraView({
    super.key,
    required this.onDetect,
    this.overlay,
    this.borderRadius = 16,
  });

  final void Function(BarcodeCapture capture) onDetect;

  /// Repère visuel dessiné par-dessus l'aperçu (non interactif).
  final Widget? overlay;
  final double borderRadius;

  @override
  State<ScannerCameraView> createState() => _ScannerCameraViewState();
}

class _ScannerCameraViewState extends State<ScannerCameraView>
    with WidgetsBindingObserver {
  static const _system = MethodChannel('gymdesk/system');

  late final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
  );

  CameraFacing _facing = CameraFacing.back;
  bool _triedFrontFallback = false;
  bool _disposed = false;
  Future<void> _queue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Le widget MobileScanner s'attache au contrôleur pendant ce frame ;
    // on démarre juste après.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _start();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _stop();
      case AppLifecycleState.inactive:
      // `inactive` = boîte de dialogue de permission, volet de
      // notifications… On garde la caméra : l'arrêter ici casserait le
      // démarrage en cours pendant la demande de permission.
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Exécute [op] après les opérations caméra précédentes, sans jamais
  /// laisser une exception remonter (le plugin expose l'erreur via
  /// `controller.value.error`).
  Future<void> _serialize(Future<void> Function() op) {
    final next = _queue.then((_) async {
      if (_disposed) return;
      try {
        await op();
      } catch (error) {
        debugPrint('ScannerCameraView: $error');
      }
    });
    _queue = next;
    return next;
  }

  Future<void> _start() => _serialize(() async {
    final value = _controller.value;
    if (value.isRunning || value.isStarting) return;
    await _controller.start(cameraDirection: _facing);
    if (_disposed) return;

    // Tablettes sans caméra arrière (ou arrière défaillante) : repli
    // automatique, une seule fois, sur la caméra frontale.
    final error = _controller.value.error;
    if (error?.errorCode == MobileScannerErrorCode.unsupported &&
        _facing == CameraFacing.back &&
        !_triedFrontFallback) {
      _triedFrontFallback = true;
      _facing = CameraFacing.front;
      await _controller.start(cameraDirection: _facing);
    }
  });

  Future<void> _stop() => _serialize(() async {
    if (_controller.value.isRunning) await _controller.stop();
  });

  Future<void> _restart() => _serialize(() async {
    if (_controller.value.isRunning) await _controller.stop();
    await _controller.start(cameraDirection: _facing);
  });

  Future<void> _switchCamera() => _serialize(() async {
    _facing = _facing == CameraFacing.back
        ? CameraFacing.front
        : CameraFacing.back;
    if (_controller.value.isRunning) await _controller.stop();
    await _controller.start(cameraDirection: _facing);
  });

  Future<void> _openSettings() async {
    try {
      await _system.invokeMethod<bool>('openAppSettings');
    } on PlatformException catch (error) {
      debugPrint('openAppSettings: $error');
    } on MissingPluginException {
      // Plateforme sans canal natif (web/desktop) : rien à faire.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppStrings.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: widget.onDetect,
              placeholderBuilder: (context) => const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white70,
                  ),
                ),
              ),
              errorBuilder: (context, error) =>
                  _ErrorView(
                    error: error,
                    onRetry: _restart,
                    onSwitch: _switchCamera,
                    onOpenSettings: _openSettings,
                  ),
            ),
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, value, _) {
                if (!value.isRunning) return const SizedBox.shrink();
                final canSwitch =
                    value.availableCameras == null ||
                    value.availableCameras! > 1;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.overlay != null)
                      IgnorePointer(child: Center(child: widget.overlay)),
                    if (canSwitch && !kIsWeb)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton.filledTonal(
                          icon: const Icon(LucideIcons.switchCamera, size: 20),
                          tooltip: s.text('switch_camera'),
                          onPressed: _switchCamera,
                          style: IconButton.styleFrom(
                            backgroundColor: theme.colorScheme.surface
                                .withAlpha(200),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.error,
    required this.onRetry,
    required this.onSwitch,
    required this.onOpenSettings,
  });

  final MobileScannerException error;
  final VoidCallback onRetry;
  final VoidCallback onSwitch;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppStrings.of(context);
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;

    final title = denied
        ? s.text('camera_permission_denied')
        : unsupported
        ? s.text('camera_unavailable')
        : s.text('camera_start_failed');
    final details = denied
        ? s.text('camera_permission_settings_hint')
        : [
            error.errorCode.name,
            ...?error.errorDetails?.code != null ? [error.errorDetails!.code!] : null,
            ...?error.errorDetails?.message != null ? [error.errorDetails!.message!] : null,
          ].join(' · ');

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.cameraOff,
                size: 34,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                details,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(LucideIcons.refreshCw, size: 14),
                    label: Text(s.text('retry')),
                    onPressed: onRetry,
                  ),
                  if (denied)
                    FilledButton.icon(
                      icon: const Icon(LucideIcons.settings, size: 14),
                      label: Text(s.text('open_settings')),
                      onPressed: onOpenSettings,
                    )
                  else
                    OutlinedButton.icon(
                      icon: const Icon(LucideIcons.switchCamera, size: 14),
                      label: Text(s.text('switch_camera')),
                      onPressed: onSwitch,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
