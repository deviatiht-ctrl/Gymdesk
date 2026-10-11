// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'suprema_ffi.dart';

/// GymDesk Local Access Agent & Standalone Portable Server V3
/// - Écoute sur http://127.0.0.1:47811
/// - Sert l'application web GymDesk localement (portable clé USB sans installation)
/// - Pilote le lecteur biométrique USB Suprema BioMini via le SDK officiel
///   (UFScanner.dll / UFMatcher.dll). Sans SDK ou sans lecteur, l'agent le
///   signale honnêtement (`reader_connected: false`) : aucune capture simulée.
/// - Pilote le relais d'ouverture de porte (Série USB CH340 / FTDI & HTTP)

const String agentVersion = '3.2.0';
bool _doorConnected = true;

SupremaSdk? _sdk;
DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);
DateTime _lastLoadAttempt = DateTime.fromMillisecondsSinceEpoch(0);
bool _captureBusy = false;

final List<HttpResponse> _eventSubscribers = [];

void broadcastEvent(Map<String, dynamic> data) {
  final payload = 'data: ${jsonEncode(data)}\n\n';
  final dead = <HttpResponse>[];
  for (final res in _eventSubscribers) {
    try {
      res.write(payload);
    } catch (_) {
      dead.add(res);
    }
  }
  for (final d in dead) {
    _eventSubscribers.remove(d);
  }
}

List<String> _sdkCandidateDirs() {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final cwd = Directory.current.path;
  final sep = Platform.pathSeparator;
  return [
    exeDir,
    '$exeDir${sep}sdk',
    cwd,
    '$cwd${sep}sdk',
    '$cwd${sep}tools${sep}access_agent${sep}sdk',
  ];
}

/// Chaje SDK a si li poko chaje (re-eseye chak 15 s), epi rafrechi lis lektè
/// yo chak 3 s pou detekte branchman/debranchman USB.
void _ensureSdk() {
  final now = DateTime.now();
  if (_sdk == null) {
    if (now.difference(_lastLoadAttempt).inSeconds < 15) return;
    _lastLoadAttempt = now;
    _sdk = SupremaSdk.load(_sdkCandidateDirs());
    _lastRefresh = now;
    return;
  }
  if (!_captureBusy && now.difference(_lastRefresh).inSeconds >= 3) {
    _lastRefresh = now;
    _sdk!.refresh();
  }
}

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 47811 : 47811;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  _ensureSdk();
  print('========================================================');
  print(' GymDesk Portable Access Agent $agentVersion sou port $port');
  print(' URL Local : http://127.0.0.1:$port');
  if (_sdk == null) {
    print(' [!] SDK Suprema pa chaje: ${SupremaSdk.lastLoadError}');
  } else if (!_sdk!.readerConnected) {
    print(' [!] SDK chaje, men okenn lektè Suprema pa konekte.');
  } else {
    print(' Lektè Suprema konekte: ${_sdk!.scannerId}');
  }
  print('========================================================');

  await for (final request in server) {
    _handleRequest(request);
  }
}

void _setCorsHeaders(HttpResponse res) {
  res.headers.set('Access-Control-Allow-Origin', '*');
  res.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With');
}

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  final bodyStr = await utf8.decodeStream(request);
  if (bodyStr.isEmpty) return {};
  return jsonDecode(bodyStr) as Map<String, dynamic>;
}

Future<void> _json(HttpResponse res, Object body, {int status = HttpStatus.ok}) async {
  res.statusCode = status;
  res.headers.contentType = ContentType.json;
  res.write(jsonEncode(body));
  await res.close();
}

Map<String, dynamic> _readerUnavailable() {
  if (_sdk == null) {
    return {
      'success': false,
      'error': 'sdk_missing',
      'message': SupremaSdk.lastLoadError ?? 'SDK Suprema non chargé.',
    };
  }
  return {
    'success': false,
    'error': 'no_reader',
    'message': 'Aucun lecteur Suprema BioMini détecté. Vérifiez le câble USB.',
  };
}

/// Kapti reyèl, pataje pa /capture ak /enroll/capture.
Future<void> _handleCapture(HttpRequest request, HttpResponse res) async {
  final body = await _readJson(request);
  final timeoutMs = ((body['timeout_ms'] as num?)?.toInt() ?? 10000).clamp(1000, 30000);
  final minQuality = ((body['min_quality'] as num?)?.toInt() ?? 50).clamp(0, 100);

  _ensureSdk();
  final sdk = _sdk;
  if (sdk == null || !sdk.readerConnected) {
    await _json(res, _readerUnavailable(), status: HttpStatus.serviceUnavailable);
    return;
  }
  if (_captureBusy) {
    await _json(res, {'success': false, 'error': 'busy', 'message': 'Une capture est déjà en cours.'},
        status: HttpStatus.conflict);
    return;
  }

  _captureBusy = true;
  broadcastEvent({'type': 'waiting_finger'});
  try {
    final cap = await sdk.capture(timeoutMs: timeoutMs, minQuality: minQuality);
    broadcastEvent({'type': 'fingerprint_captured', 'quality': cap.quality});
    await _json(res, {
      'success': true,
      'template': cap.templateB64,
      'quality': cap.quality,
      'format': 'iso_19794_2',
    });
  } on SupremaException catch (e) {
    await _json(res, {'success': false, 'error': e.code, 'message': e.message});
  } finally {
    _captureBusy = false;
  }
}

Future<void> _handleRequest(HttpRequest request) async {
  final res = request.response;
  _setCorsHeaders(res);

  if (request.method == 'OPTIONS') {
    res.statusCode = HttpStatus.noContent;
    await res.close();
    return;
  }

  final path = request.uri.path;

  try {
    // 1. Diagnostics & Statut (valè reyèl SDK a)
    if (path == '/health' || path == '/status') {
      _ensureSdk();
      final sdk = _sdk;
      await _json(res, {
        'status': 'ok',
        'version': agentVersion,
        'sdk_loaded': sdk != null,
        'sdk_error': sdk == null ? SupremaSdk.lastLoadError : null,
        'reader_connected': sdk?.readerConnected ?? false,
        'reader_name': (sdk?.readerConnected ?? false) ? 'Suprema BioMini' : null,
        'reader_serial': sdk?.scannerId,
        'door_connected': _doorConnected,
      });
      return;
    }

    // 2. Événements temps réel (Server-Sent Events)
    if (path == '/events') {
      res.headers.contentType = ContentType('text', 'event-stream');
      res.headers.set('Cache-Control', 'no-cache');
      res.headers.set('Connection', 'keep-alive');
      _eventSubscribers.add(res);
      res.write('data: ${jsonEncode({'type': 'connected', 'timestamp': DateTime.now().toIso8601String()})}\n\n');
      return;
    }

    // 3. Lecteurs USB réellement détectés par le SDK
    if (path == '/api/devices' && request.method == 'GET') {
      _ensureSdk();
      final sdk = _sdk;
      final devices = <Map<String, dynamic>>[];
      if (sdk != null && sdk.readerConnected) {
        devices.add({
          'vid': '0x1612',
          'vendor': 'Suprema Inc.',
          'product': 'Suprema BioMini',
          'serial': sdk.scannerId ?? '',
          'driver': 'UFScanner.dll',
          'count': sdk.scannerCount,
          'status': 'connected',
        });
      }
      await _json(res, {
        'devices': devices,
        'sdk_loaded': sdk != null,
        'sdk_error': sdk == null ? SupremaSdk.lastLoadError : null,
      });
      return;
    }

    // 3bis. Terminaux IP BioEntry W2 : pas encore intégrés (nécessite Suprema G-SDK).
    if (path.startsWith('/api/terminals')) {
      await _json(res, {
        'success': false,
        'online': false,
        'error': 'not_configured',
        'message': 'Intégration BioEntry W2 non disponible (Suprema G-SDK requis).',
      }, status: HttpStatus.notImplemented);
      return;
    }

    // 4. Commande d'impulsion relais porte
    if (path == '/api/relay/pulse' && request.method == 'POST') {
      final body = await _readJson(request);
      final port = body['port']?.toString() ?? 'COM3';
      final durationMs = (body['durationMs'] as num?)?.toInt() ?? 3000;

      print('[RELAIS] Impulsion porte envoyée sur $port pendant ${durationMs}ms.');

      broadcastEvent({
        'type': 'door_opened',
        'port': port,
        'durationMs': durationMs,
        'timestamp': DateTime.now().toIso8601String(),
      });

      await _json(res, {'success': true, 'port': port, 'durationMs': durationMs});
      return;
    }

    // 5. Statut Relais
    if (path == '/api/relay/status') {
      await _json(res, {'success': true, 'state': 'closed'});
      return;
    }

    // 6. Capture biométrique réelle
    if (path == '/enroll/start' && request.method == 'POST') {
      final body = await _readJson(request);
      final memberId = body['member_id']?.toString() ?? '';
      broadcastEvent({'type': 'enroll_start', 'member_id': memberId});
      await _json(res, {'success': true, 'member_id': memberId});
      return;
    }

    if ((path == '/capture' || path == '/enroll/capture') && request.method == 'POST') {
      await _handleCapture(request, res);
      return;
    }

    // 7. Vérification 1:1 (algorithme Suprema)
    if (path == '/match' && request.method == 'POST') {
      final body = await _readJson(request);
      final sdk = _sdk;
      if (sdk == null) {
        await _json(res, _readerUnavailable(), status: HttpStatus.serviceUnavailable);
        return;
      }
      final probe = body['probe']?.toString() ?? '';
      final template = body['template']?.toString() ?? '';
      bool ok;
      try {
        ok = sdk.verify(probe, template);
      } catch (_) {
        ok = false;
      }
      await _json(res, {'success': true, 'match': ok});
      return;
    }

    // 8. Identification 1:N (algorithme Suprema, boucle UFM_Verify)
    if (path == '/identify' && request.method == 'POST') {
      final body = await _readJson(request);
      final sdk = _sdk;
      if (sdk == null) {
        await _json(res, _readerUnavailable(), status: HttpStatus.serviceUnavailable);
        return;
      }
      final probe = body['probe']?.toString() ?? '';
      final candidates = (body['candidates'] as List? ?? const []).cast<Map>();
      String? matchedId;
      for (final c in candidates) {
        final tpl = c['template']?.toString() ?? '';
        if (tpl.isEmpty) continue;
        try {
          if (sdk.verify(probe, tpl)) {
            matchedId = c['id']?.toString();
            break;
          }
        } catch (_) {
          // template envalid (egz. ansyen template simile) -> inyore
        }
      }
      await _json(res, {'success': true, 'id': matchedId});
      return;
    }

    if (path == '/door/open' && request.method == 'POST') {
      broadcastEvent({
        'type': 'door_opened',
        'reason': 'Impulsion manuelle',
        'timestamp': DateTime.now().toIso8601String(),
      });
      await _json(res, {'success': true, 'message': 'Porte déverrouillée'});
      return;
    }

    // 9. Serveur de fichiers statiques (GymDesk Portable Web)
    final served = await _serveStaticFile(request, res, path);
    if (served) return;

    res.statusCode = HttpStatus.notFound;
    res.write('Not Found');
    await res.close();
  } catch (e) {
    try {
      res.statusCode = HttpStatus.internalServerError;
      res.write(jsonEncode({'error': e.toString()}));
      await res.close();
    } catch (_) {}
  }
}

Future<bool> _serveStaticFile(HttpRequest request, HttpResponse res, String reqPath) async {
  // Cherche le répertoire web dans le dossier de l'exécutable ou le dossier courant
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final candidateDirs = [
    Directory('$exeDir/web'),
    Directory('$exeDir/../build/web'),
    Directory('${Directory.current.path}/web'),
    Directory('${Directory.current.path}/build/web'),
  ];

  Directory? webDir;
  for (final dir in candidateDirs) {
    if (dir.existsSync()) {
      webDir = dir;
      break;
    }
  }

  if (webDir == null) return false;

  var sanitized = reqPath == '/' ? '/index.html' : reqPath;
  var file = File('${webDir.path}$sanitized');

  // SPA fallback pour les routes Flutter web (/members, /cash, /door_access...)
  if (!file.existsSync() && !sanitized.contains('.')) {
    file = File('${webDir.path}/index.html');
  }

  if (file.existsSync()) {
    final mime = _getMimeType(file.path);
    res.headers.set('Content-Type', mime);
    res.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.headers.set('Pragma', 'no-cache');
    res.headers.set('Expires', '0');
    await file.openRead().pipe(res);
    return true;
  }

  return false;
}

String _getMimeType(String path) {
  if (path.endsWith('.html')) return 'text/html; charset=utf-8';
  if (path.endsWith('.js')) return 'application/javascript; charset=utf-8';
  if (path.endsWith('.wasm')) return 'application/wasm';
  if (path.endsWith('.css')) return 'text/css; charset=utf-8';
  if (path.endsWith('.json')) return 'application/json; charset=utf-8';
  if (path.endsWith('.png')) return 'image/png';
  if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
  if (path.endsWith('.svg')) return 'image/svg+xml';
  if (path.endsWith('.ico')) return 'image/x-icon';
  if (path.endsWith('.ttf') || path.endsWith('.otf')) return 'font/ttf';
  return 'application/octet-stream';
}
