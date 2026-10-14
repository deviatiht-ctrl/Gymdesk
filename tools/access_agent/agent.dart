// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'suprema_bridge.dart';
import 'suprema_ffi.dart';

/// GymDesk Local Access Agent & Standalone Portable Server V3
/// - Écoute sur http://127.0.0.1:47811
/// - Sert l'application web GymDesk localement (portable clé USB sans installation)
/// - Pilote le lecteur biométrique USB Suprema BioMini via le SDK officiel
///   (UFScanner.dll / UFMatcher.dll). Sans SDK ou sans lecteur, l'agent le
///   signale honnêtement (`reader_connected: false`) : aucune capture simulée.
/// - Pilote le relais d'ouverture de porte (Série USB CH340 / FTDI & HTTP)

const String agentVersion = '3.3.0';
bool _doorConnected = true;

ReaderBackend? _sdk;
DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);
DateTime _lastLoadAttempt = DateTime.fromMillisecondsSinceEpoch(0);
bool _captureBusy = false;

Map<String, dynamic>? _terminalConfig;
DateTime _terminalSearchAt = DateTime.fromMillisecondsSinceEpoch(0);
List<Map<String, dynamic>> _terminalCache = const [];

/// Konfigirasyon tèminal la: terminal.json bò kote access_agent.exe
/// {"ip": "192.168.1.41", "port": 51211}
Map<String, dynamic> terminalConfig() {
  final c = _terminalConfig;
  if (c != null) return c;
  var ip = '192.168.1.41';
  var port = 51211;
  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final f = File('$exeDir${Platform.pathSeparator}terminal.json');
    if (f.existsSync()) {
      final j = jsonDecode(f.readAsStringSync());
      if (j is Map) {
        ip = j['ip']?.toString() ?? ip;
        port = (j['port'] as num?)?.toInt() ?? port;
      }
    }
  } catch (_) {}
  return _terminalConfig = {'ip': ip, 'port': port};
}

/// Jwenn biostar_tool.exe ak dosye DLL BioStar SDK a (x64).
Map<String, String>? _biostarTool() {
  final sep = Platform.pathSeparator;
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final cwd = Directory.current.path;
  final exeDirs = [exeDir, cwd, '$cwd${sep}GymDesk_USB'];
  final dllDirs = [
    '$exeDir${sep}Lib${sep}Window${sep}lib${sep}x64',
    '$exeDir${sep}biostar',
    '$cwd${sep}GymDesk_USB${sep}Lib${sep}Window${sep}lib${sep}x64',
    exeDir,
  ];
  String? tool;
  for (final d in exeDirs) {
    final f = '$d${sep}biostar_tool.exe';
    if (File(f).existsSync()) {
      tool = f;
      break;
    }
  }
  if (tool == null) return null;
  for (final d in dllDirs) {
    if (File('$d${sep}BS_SDK_V2.dll').existsSync()) return {'tool': tool, 'dllDir': d};
  }
  return null;
}

/// Lanse biostar_tool.exe yon fwa; retounen lis liy repons yo.
Future<List<List<String>>> _biostarCall(List<String> args, {Duration timeout = const Duration(seconds: 20)}) async {
  final cfg = _biostarTool();
  if (cfg == null) throw SupremaException('sdk_missing', 'biostar_tool.exe oswa BS_SDK_V2.dll (x64) manke.');
  final process = await Process.start(cfg['tool']!, [cfg['dllDir']!, ...args], workingDirectory: cfg['dllDir']);
  final out = StringBuffer();
  unawaited(process.stderr.drain<void>());
  final sub = process.stdout.transform(utf8.decoder).listen(out.write);
  final timer = Timer(timeout, () => process.kill());
  await process.exitCode;
  timer.cancel();
  await sub.cancel();
  return [
    for (final l in out.toString().split('\n'))
      if (l.trim().isNotEmpty) l.trim().split('\t')
  ];
}

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

/// Chaje SDK a (FFI dirèk si DLL yo gen menm achitekti, sinon pon 32-bit la),
/// re-eseye chak 15 s, epi rafrechi lis lektè yo chak 3 s (USB plug-and-play).
Future<void> _ensureSdk() async {
  final now = DateTime.now();
  final sdk = _sdk;
  if (sdk is SupremaBridge && !sdk.alive) _sdk = null;
  if (_sdk == null) {
    if (now.difference(_lastLoadAttempt).inSeconds < 15) return;
    _lastLoadAttempt = now;
    _lastRefresh = now;
    _sdk = SupremaSdk.load(_sdkCandidateDirs()) ?? await _startBridge();
    return;
  }
  if (!_captureBusy && now.difference(_lastRefresh).inSeconds >= 3) {
    _lastRefresh = now;
    await _sdk!.refresh();
  }
}

Future<ReaderBackend?> _startBridge() async {
  final sep = Platform.pathSeparator;
  final dirs = _sdkCandidateDirs();
  for (final dir in dirs) {
    final dll = '$dir${sep}UFScanner.dll';
    if (!File(dll).existsSync() || dllBits(dll) != 32) continue;
    for (final exeDir in dirs) {
      final bridge = '$exeDir$sep${SupremaBridge.exeName}';
      if (File(bridge).existsSync()) return SupremaBridge.start(bridge, dir);
    }
    SupremaSdk.lastLoadError = 'UFScanner.dll se 32-bit: ${SupremaBridge.exeName} manke bò kote access_agent.exe.';
  }
  return null;
}

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 47811 : 47811;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  await _ensureSdk();
  print('========================================================');
  print(' GymDesk Portable Access Agent $agentVersion sou port $port');
  print(' URL Local : http://127.0.0.1:$port');
  if (_sdk == null) {
    print(' [!] SDK Suprema pa chaje: ${SupremaSdk.lastLoadError}');
  } else if (!_sdk!.readerConnected) {
    print(' [!] SDK chaje, men okenn lektè Suprema pa konekte.');
  } else {
    print(' Lektè Suprema konekte (${_sdk!.mode}): ${_sdk!.scannerId}');
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
  // Private Network Access: pèmèt paj HTTPS (Vercel) rele agent lokal la.
  res.headers.set('Access-Control-Allow-Private-Network', 'true');
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
  // 'suprema' = fòma natif 384B pou enroll sou tèminal W2; default ISO.
  final tplType = body['tpl']?.toString() == 'suprema'
      ? templateTypeSuprema
      : (body['tpl_type'] as num?)?.toInt() ?? templateTypeIso19794_2;

  await _ensureSdk();
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
    final cap = await sdk.capture(timeoutMs: timeoutMs, minQuality: minQuality, tplType: tplType);
    broadcastEvent({'type': 'fingerprint_captured', 'quality': cap.quality});
    await _json(res, {
      'success': true,
      'template': cap.templateB64,
      'quality': cap.quality,
      'format': tplType == templateTypeSuprema ? 'suprema_native' : 'iso_19794_2',
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
      await _ensureSdk();
      final sdk = _sdk;
      await _json(res, {
        'status': 'ok',
        'version': agentVersion,
        'sdk_loaded': sdk != null,
        'sdk_mode': sdk?.mode,
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
      await _ensureSdk();
      final sdk = _sdk;
      final devices = <Map<String, dynamic>>[];
      if (sdk != null && sdk.readerConnected) {
        devices.add({
          'vid': '0x16D1',
          'vendor': 'Suprema Inc.',
          'product': 'Suprema BioMini',
          'serial': sdk.scannerId ?? '',
          'driver': sdk.mode == 'bridge32' ? 'UFScanner.dll (32-bit)' : 'UFScanner.dll',
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

    // 3bis. Terminaux IP Suprema (BioEntry W2) atravè BioStar Device SDK.
    if (path == '/api/terminals' && request.method == 'GET') {
      try {
        if (DateTime.now().difference(_terminalSearchAt).inSeconds >= 15) {
          final lines = await _biostarCall(['search'], timeout: const Duration(seconds: 25));
          _terminalCache = [
            for (final l in lines)
              if (l.first == 'device' && l.length >= 5)
                {'id': l[1], 'type': l[2], 'ip': l[3], 'port': int.tryParse(l[4]) ?? 51211}
          ];
          _terminalSearchAt = DateTime.now();
        }
        final cfg = terminalConfig();
        await _json(res, {
          'success': true,
          'devices': _terminalCache,
          'configured': cfg,
          'sdk': 'biostar_v2',
        });
      } on SupremaException catch (e) {
        await _json(res, {'success': false, 'online': false, 'error': e.code, 'message': e.message},
            status: HttpStatus.serviceUnavailable);
      }
      return;
    }

    if (path == '/api/terminals/ping' && request.method == 'POST') {
      final body = await _readJson(request);
      final cfg = terminalConfig();
      final ip = body['ip']?.toString() ?? cfg['ip'] as String;
      final port = (body['port'] as num?)?.toInt() ?? cfg['port'] as int;
      try {
        final lines = await _biostarCall(['ping', ip, '$port'], timeout: const Duration(seconds: 20));
        final ok = lines.any((l) => l.first == 'ok');
        await _json(res, {'success': true, 'online': ok, 'ip': ip, 'port': port});
      } on SupremaException catch (e) {
        await _json(res, {'success': false, 'online': false, 'error': e.code, 'message': e.message});
      }
      return;
    }

    if (path == '/api/terminals/pulse' && request.method == 'POST') {
      final body = await _readJson(request);
      final cfg = terminalConfig();
      final ip = body['ip']?.toString() ?? cfg['ip'] as String;
      final port = (body['port'] as num?)?.toInt() ?? cfg['port'] as int;
      final seconds = ((body['seconds'] as num?)?.toInt() ?? 3).clamp(1, 30);
      try {
        final lines = await _biostarCall(['pulse', ip, '$port', '$seconds'],
            timeout: const Duration(seconds: 25));
        if (lines.any((l) => l.first == 'ok')) {
          broadcastEvent({
            'type': 'door_opened',
            'reason': 'Terminal pulse',
            'timestamp': DateTime.now().toIso8601String(),
          });
          await _json(res, {'success': true, 'message': 'Porte déverrouillée ${seconds}s'});
        } else {
          final err = lines.firstWhere((l) => l.first == 'err', orElse: () => const ['err', 'unknown', 'Erreur inconnue']);
          await _json(res, {'success': false, 'error': err.length > 1 ? err[1] : 'unknown', 'message': err.length > 2 ? err[2] : 'Erreur'});
        }
      } on SupremaException catch (e) {
        await _json(res, {'success': false, 'error': e.code, 'message': e.message});
      }
      return;
    }

    // Fòse pòt la fèmen: release retire tout flag unlock/lock ki te ka rete
    // (ex. yon ansyen unlock ak flag 0xFF ki kenbe relè a louvri).
    if ((path == '/api/terminals/lock' || path == '/api/terminals/release') && request.method == 'POST') {
      final body = await _readJson(request);
      final cfg = terminalConfig();
      final ip = body['ip']?.toString() ?? cfg['ip'] as String;
      final port = (body['port'] as num?)?.toInt() ?? cfg['port'] as int;
      final verb = path.endsWith('/lock') ? 'lock' : 'release';
      try {
        final lines = await _biostarCall([verb, ip, '$port'], timeout: const Duration(seconds: 20));
        final ok = lines.any((l) => l.first == 'ok');
        await _json(res, {'success': ok, 'online': ok, 'ip': ip, 'command': verb});
      } on SupremaException catch (e) {
        await _json(res, {'success': false, 'error': e.code, 'message': e.message});
      }
      return;
    }

    // Pouse anprent manm GymDesk yo sou tèminal W2 a (BS2_EnrollUser).
    // Body: {members:[{id, name, fingers:[[b64 t1, b64 t2?], ...]}], ip?}
    // Template yo dwe fòma natif Suprema (384B) — capture ak tpl:'suprema'.
    if (path == '/api/terminals/sync' && request.method == 'POST') {
      final body = await _readJson(request);
      final cfg = terminalConfig();
      final ip = body['ip']?.toString() ?? cfg['ip'] as String;
      final port = (body['port'] as num?)?.toInt() ?? cfg['port'] as int;
      final members = (body['members'] as List?) ?? const [];
      if (members.isEmpty) {
        await _json(res, {'success': false, 'error': 'empty', 'message': 'Okenn manm yo voye.'});
        return;
      }
      try {
        final lines = <String>[];
        for (final m in members) {
          final mm = Map<String, dynamic>.from(m as Map);
          final uid = (mm['id']?.toString() ?? '').replaceAll('-', '');
          if (uid.isEmpty) continue;
          lines.add('user\t$uid\t${(mm['name']?.toString() ?? '').replaceAll('\t', ' ')}');
          var idx = 0;
          for (final f in (mm['fingers'] as List? ?? const [])) {
            final tpls = (f as List).map((t) => t.toString()).toList();
            lines.add('finger\t$uid\t${idx++}\t${tpls.join('\t')}');
          }
        }
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final tmp = File('$exeDir${Platform.pathSeparator}enroll_${DateTime.now().millisecondsSinceEpoch}.tsv');
        try {
          await tmp.writeAsString(lines.join('\n'), flush: true);
          final out = await _biostarCall(['enroll', ip, tmp.path, '$port'], timeout: const Duration(seconds: 60));
          final ok = out.any((l) => l.first == 'ok');
          await _json(res, {
            'success': ok,
            'enrolled': ok ? int.tryParse(out.firstWhere((l) => l.first == 'ok')[1]) ?? 0 : 0,
            'errors': [for (final l in out) if (l.first == 'err') l.skip(1).join(': ')],
          });
        } finally {
          try { await tmp.delete(); } catch (_) {}
        }
      } on SupremaException catch (e) {
        await _json(res, {'success': false, 'error': e.code, 'message': e.message});
      }
      return;
    }

    if (path.startsWith('/api/terminals')) {
      await _json(res, {
        'success': false,
        'online': false,
        'error': 'not_configured',
        'message': 'Endpoint terminal inconnu.',
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
        ok = await sdk.verify(probe, template);
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
      try {
        final index = await sdk.identify(probe, [for (final c in candidates) c['template']?.toString() ?? '']);
        if (index >= 0) matchedId = candidates[index]['id']?.toString();
      } catch (_) {
        // template envalid (egz. ansyen template simile) -> pa gen koresponn
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
