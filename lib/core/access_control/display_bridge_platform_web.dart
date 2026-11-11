import 'dart:js_interop';

@JS('securgymBridgePost')
external void _bridgePost(JSString message);

@JS('securgymBridgeListen')
external JSBoolean? _bridgeListen(JSFunction callback);

@JS('securgymOpenWindow')
external JSBoolean? _openWindow(JSString url, JSString name);

@JS('securgymCloseWindow')
external void _closeWindow();

/// Web : fenêtre navigateur séparée (window.open) + BroadcastChannel/localStorage
/// entre la fenêtre principale (qui reçoit les scans) et la fenêtre « 2e écran ».
class DisplayBridgePlatform {
  DisplayBridgePlatform()
      : _launchedAsDisplay = Uri.base.queryParameters['display'] == '1',
        _launchPath = Uri.base.path;

  final bool _launchedAsDisplay;
  final String _launchPath;

  bool get launchedAsDisplay => _launchedAsDisplay;
  String? get launchRoute {
    if (!_launchedAsDisplay) return null;
    final p = _launchPath == '/tablet-access' ? '/tablet-access' : '/access-display';
    return '$p?display=1';
  }

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

  String displayUrlFor(String route) {
    final cleanRoute = route.startsWith('/') ? route : '/$route';
    return Uri.base.replace(path: cleanRoute, queryParameters: {'display': '1'}, fragment: '').toString();
  }

  Future<bool> openDisplayWindow(String route) async {
    try {
      final url = displayUrlFor(route);
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
