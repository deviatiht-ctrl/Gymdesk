/// Hors web : pas d'installation PWA.
class Pwa {
  const Pwa._();
  static bool get supported => false;
  static bool get isStandalone => false;
  static bool get isIos => false;
  static bool get canPrompt => false;
  static Future<String> prompt() async => 'unavailable';
  static void setGymManifest({
    required String name,
    required String startPath,
    String? iconUrl,
    String? themeColor,
  }) {}
}
