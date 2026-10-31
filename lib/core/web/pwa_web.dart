import 'dart:js_interop';

@JS('securgymCanInstall')
external JSBoolean? _canInstall();

@JS('securgymPromptInstall')
external JSPromise<JSString>? _promptInstall();

@JS('securgymIsStandalone')
external JSBoolean? _isStandalone();

@JS('securgymIsIOS')
external JSBoolean? _isIos();

@JS('securgymSetManifest')
external void _setManifest(JSString name, JSString startPath, JSString icon, JSString color);

/// Installation de l'espace membre sur le téléphone (helpers JS dans web/index.html).
class Pwa {
  const Pwa._();

  static bool get supported => true;

  static bool _call(JSBoolean? Function() f) {
    try {
      return f()?.toDart ?? false;
    } catch (_) {
      return false;
    }
  }

  static bool get isStandalone => _call(() => _isStandalone());
  static bool get isIos => _call(() => _isIos());
  static bool get canPrompt => _call(() => _canInstall());

  static Future<String> prompt() async {
    try {
      final p = _promptInstall();
      if (p == null) return 'unavailable';
      return (await p.toDart).toDart;
    } catch (_) {
      return 'unavailable';
    }
  }

  /// Manifest propre au gym : nom + logo du gym sur l'écran d'accueil,
  /// ouverture directe sur son espace membre.
  static void setGymManifest({
    required String name,
    required String startPath,
    String? iconUrl,
    String? themeColor,
  }) {
    try {
      _setManifest(name.toJS, startPath.toJS, (iconUrl ?? '').toJS, (themeColor ?? '').toJS);
    } catch (_) {}
  }
}
