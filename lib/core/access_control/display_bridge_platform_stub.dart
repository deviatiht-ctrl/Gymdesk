/// Plateformes sans multi-fenêtre (Android/iOS) : le 2e écran s'ouvre dans l'app.
class DisplayBridgePlatform {
  bool get launchedAsDisplay => false;
  String? get launchRoute => null;
  void setLaunchArgs(List<String> args) {}
  Future<bool> startHost(void Function(String message) onMessage) async => false;
  void stopHost() {}
  void hostPost(String message) {}
  bool listen(void Function(String message) onMessage, void Function(bool connected) onConnection) => false;
  void post(String message) {}
  Future<bool> openDisplayWindow(String route) async => false;
  void closeCurrentWindow() {}
}
