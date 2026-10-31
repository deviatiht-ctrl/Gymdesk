import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Windows : le 2e écran est un 2e processus SecurGYM.exe (`--access-display`),
/// donc une vraie fenêtre indépendante (réduire / changer d'app sans la fermer).
/// Les décisions d'accès arrivent instantanément depuis la fenêtre principale via
/// un flux SSE local (127.0.0.1:47812), sans attendre Supabase.
class DisplayBridgePlatform {
  static const _port = 47812;
  String? _launchRoute;

  bool get launchedAsDisplay => _launchRoute != null;
  String? get launchRoute => _launchRoute;

  void setLaunchArgs(List<String> args) {
    for (final a in args) {
      if (a == '--access-display') _launchRoute = '/access-display';
      if (a == '--tablet-access') _launchRoute = '/tablet-access';
    }
  }

  HttpServer? _server;
  final Set<HttpResponse> _clients = {};

  Future<bool> startHost(void Function(String message) onMessage) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return false;
    if (_server != null) return true;
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      _server = server;
      server.listen((req) async {
        if (req.uri.path != '/events') {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }
        final res = req.response;
        res.bufferOutput = false;
        res.headers
          ..set(HttpHeaders.contentTypeHeader, 'text/event-stream; charset=utf-8')
          ..set(HttpHeaders.cacheControlHeader, 'no-cache');
        _clients.add(res);
        try {
          res.write(': connected\n\n');
          await res.flush();
        } catch (_) {
          _clients.remove(res);
        }
        unawaited(res.done.catchError((_) {}).whenComplete(() => _clients.remove(res)));
      }, onError: (_) {});
      return true;
    } catch (_) {
      return false;
    }
  }

  void stopHost() {
    for (final c in _clients.toList()) {
      try {
        c.close();
      } catch (_) {}
    }
    _clients.clear();
    _server?.close(force: true);
    _server = null;
  }

  void hostPost(String message) {
    if (_clients.isEmpty) return;
    final frame = 'data: $message\n\n';
    for (final c in _clients.toList()) {
      try {
        c.write(frame);
      } catch (_) {
        _clients.remove(c);
      }
    }
  }

  bool _listening = false;

  bool listen(void Function(String message) onMessage, void Function(bool connected) onConnection) {
    if (_listening) return true;
    _listening = true;
    unawaited(_connectLoop(onMessage, onConnection));
    return true;
  }

  Future<void> _connectLoop(void Function(String) onMessage, void Function(bool) onConnection) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    while (_listening) {
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$_port/events'));
        final res = await req.close();
        if (res.statusCode == 200) {
          onConnection(true);
          await for (final line in res.transform(utf8.decoder).transform(const LineSplitter())) {
            if (line.startsWith('data: ')) onMessage(line.substring(6));
          }
        }
      } catch (_) {}
      onConnection(false);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  void post(String message) {}

  Future<bool> openDisplayWindow(String route) async {
    if (!Platform.isWindows) return false;
    try {
      await Process.start(
        Platform.resolvedExecutable,
        [route == '/tablet-access' ? '--tablet-access' : '--access-display'],
        workingDirectory: File(Platform.resolvedExecutable).parent.path,
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void closeCurrentWindow() => exit(0);
}
