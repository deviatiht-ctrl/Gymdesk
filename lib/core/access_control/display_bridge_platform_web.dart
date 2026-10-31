import 'dart:js_interop';

@JS('securgymBridgePost')
external void _bridgePost(JSString message);

@JS('securgymBridgeListen')
external JSBoolean? _bridgeListen(JSFunction callback);

@JS('securgymOpenWindow')
external JSBoolean? _openWindow(JSString url, JSString name);

@JS('securgymCloseWindow')
external void _closeWindow();

/// Web : fenêtre navigateur séparée (window.open) + BroadcastChannel entre
/// la fenêtre principale (qui reçoit les scans) et la fenêtre « 2e écran ».
class DisplayBridgePlatform {
  bool get launchedAsDisplay => Uri.base.queryParameters['display'] == '1';
  String? get launchRoute => launchedAsDisplay ? Uri.base.path : null;
  void setLaunchArgs(List<String> args) {}

  bool _hostListening = false;
  void Function(String)? _hostHandler;

  Future<bool> startHost(void Function(String message) onMessage) async {
    _hostHandler = onMessage;
    if (_hostListening) return true;
    try {
      _hostListening = _bridgeListen(((JSString m) => _hostHandler?.call(m.toDart)).toJS)?.toDart ?? false;
    } catch (_) {
      _hostListening = false;
    }
    return _hostListening;
  }

  void stopHost() => _hostHandler = null;

  void hostPost(String message) => post(message);

  bool listen(void Function(String message) onMessage, void Function(bool connected) onConnection) {
    try {
      final ok = _bridgeListen(((JSString m) => onMessage(m.toDart)).toJS)?.toDart ?? false;
      onConnection(ok);
      return ok;
    } catch (_) {
      return false;
    }
  }

  void post(String message) {
    try {
      _bridgePost(message.toJS);
    } catch (_) {}
  }

  Future<bool> openDisplayWindow(String route) async {
    try {
      final url = Uri.base.replace(path: route, queryParameters: {'display': '1'}, fragment: '').toString();
      return _openWindow(url.toJS, 'securgym_access_display'.toJS)?.toDart ?? false;
    } catch (_) {
      return false;
    }
  }

  void closeCurrentWindow() {
    try {
      _closeWindow();
    } catch (_) {}
  }
}
