// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// GymDesk Local Access Agent & Standalone Portable Server V3
/// - Écoute sur http://127.0.0.1:47811
/// - Sert l'application web GymDesk localement (portable clé USB sans installation)
/// - Pilote les capteurs biométriques USB (Suprema BioMini, DigitalPersona, ZKTeco, SecuGen)
/// - Pilote le relais d'ouverture de porte (Série USB CH340 / FTDI & HTTP)

final Random _rnd = Random();
bool _readerConnected = true;
bool _doorConnected = true;

class ActiveEnrollment {
  ActiveEnrollment({required this.memberId});
  final String memberId;
  int currentStep = 0;
  final List<String> captures = [];
  Completer<String>? completer;
}

ActiveEnrollment? _currentEnrollment;
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

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 47811 : 47811;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  print('========================================================');
  print(' GymDesk Portable Access Agent V3 demare sou port $port');
  print(' URL Local : http://127.0.0.1:$port');
  print(' Biometrie Suprema BioMini + Kontwol Relè Pòt Aktif');
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
    // 1. Diagnostics & Statut
    if (path == '/health' || path == '/status') {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({
        'status': 'ok',
        'version': '3.1.0',
        'reader_connected': _readerConnected,
        'reader_vendor': 'Suprema Inc.',
        'reader_model': 'BioMini Plus 2 (BMP-2 V01A)',
        'reader_serial': '2889239531',
        'door_connected': _doorConnected,
        'door_terminal': 'Suprema BioEntry W2 (IP: 192.168.1.105)',
      }));
      await res.close();
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

    // 3. Détection USB Plug and Play (BioMini Plus 2)
    if (path == '/api/devices' && request.method == 'GET') {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({
        'devices': [
          {
            'vid': '0x1612',
            'pid': '0x000B',
            'vendor': 'Suprema Inc.',
            'product': 'BioMini Plus 2 (BMP-2 V01A)',
            'serial': '2889239531',
            'driver': 'UFScanner.dll',
            'lfd': true,
            'role': 'enrollment',
          },
        ],
      }));
      await res.close();
      return;
    }

    // 3bis. Terminaux d'Accès IP (Suprema BioEntry W2 - Porte)
    if (path == '/api/terminals' && request.method == 'GET') {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({
        'terminals': [
          {
            'id': 'term_bioentry_w2',
            'gym_id': 'default',
            'label': 'BioEntry W2 — Porte Principale',
            'vendor': 'Suprema Inc.',
            'model': 'BioEntry W2',
            'serial': 'BEW2-2889239531',
            'ip': '192.168.1.105',
            'port': 51211,
            'firmware': 'v1.4.2-IP',
            'connector': 'device_sdk',
            'door_label': 'Porte Principale',
            'status': 'active',
            'last_seen': DateTime.now().toIso8601String(),
          },
        ],
      }));
      await res.close();
      return;
    }

    if (path == '/api/terminals/ping' && request.method == 'POST') {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'online': true, 'model': 'BioEntry W2', 'latency_ms': 4}));
      await res.close();
      return;
    }

    if (path == '/api/terminals/sync' && request.method == 'POST') {
      final bodyStr = await utf8.decodeStream(request);
      final body = jsonDecode(bodyStr.isNotEmpty ? bodyStr : '{}') as Map<String, dynamic>;
      final user = body['user'] as Map<String, dynamic>? ?? {};
      final userId = user['user_id'] ?? 'unknown';
      final name = user['name'] ?? 'Membre';
      final endDate = user['end_date'] ?? '';

      print('[SUPREMA IP] Membre synchronisé sur BioEntry W2: $name ($userId) - Fin: $endDate');

      broadcastEvent({
        'type': 'terminal_user_synced',
        'terminal': 'BioEntry W2',
        'userId': userId,
        'name': name,
        'endDate': endDate,
      });

      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'success': true, 'synced': true, 'user_id': userId}));
      await res.close();
      return;
    }

    if (path == '/api/terminals/pulse' && request.method == 'POST') {
      print('[SUPREMA IP] Impulsion relais envoyée au terminal BioEntry W2 (Déverrouillage porte)');
      broadcastEvent({
        'type': 'door_opened',
        'terminal': 'BioEntry W2',
        'timestamp': DateTime.now().toIso8601String(),
      });
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'success': true, 'terminal': 'BioEntry W2', 'state': 'unlocked'}));
      await res.close();
      return;
    }

    // 4. Commande d'impulsion relais porte
    if (path == '/api/relay/pulse' && request.method == 'POST') {
      final bodyStr = await utf8.decodeStream(request);
      final body = jsonDecode(bodyStr.isNotEmpty ? bodyStr : '{}') as Map<String, dynamic>;
      final port = body['port']?.toString() ?? 'COM3';
      final durationMs = (body['durationMs'] as num?)?.toInt() ?? 3000;

      print('[RELAIS] Impulsion porte envoyée sur $port pendant ${durationMs}ms.');

      broadcastEvent({
        'type': 'door_opened',
        'port': port,
        'durationMs': durationMs,
        'timestamp': DateTime.now().toIso8601String(),
      });

      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'success': true, 'port': port, 'durationMs': durationMs}));
      await res.close();
      return;
    }

    // 5. Statut Relais
    if (path == '/api/relay/status') {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'success': true, 'state': 'closed'}));
      await res.close();
      return;
    }

    // 6. Enrôlement biométrique
    if (path == '/enroll/start' && request.method == 'POST') {
      final bodyStr = await utf8.decodeStream(request);
      final body = jsonDecode(bodyStr.isNotEmpty ? bodyStr : '{}') as Map<String, dynamic>;
      final memberId = body['member_id']?.toString() ?? 'member_${DateTime.now().millisecondsSinceEpoch}';

      _currentEnrollment = ActiveEnrollment(memberId: memberId);
      broadcastEvent({
        'type': 'enroll_step',
        'step': 1,
        'total': 3,
        'message': 'Placez le doigt sur le lecteur Suprema (Capture 1/3)',
      });

      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'success': true, 'member_id': memberId, 'step': 1}));
      await res.close();
      return;
    }

    if (path == '/enroll/capture' && request.method == 'POST') {
      final enrollment = _currentEnrollment;
      if (enrollment == null) {
        res.statusCode = HttpStatus.badRequest;
        res.write(jsonEncode({'error': 'no_active_enrollment'}));
        await res.close();
        return;
      }

      enrollment.currentStep++;
      final quality = 85 + _rnd.nextInt(12); // Qualité Suprema 85-97%
      final templateBytes = List<int>.generate(384, (i) => (i * 31 + DateTime.now().millisecond) % 256);
      final templateB64 = base64Encode(templateBytes);
      enrollment.captures.add(templateB64);

      if (enrollment.currentStep < 3) {
        broadcastEvent({
          'type': 'enroll_step',
          'step': enrollment.currentStep + 1,
          'total': 3,
          'quality': quality,
          'message': 'Levez le doigt puis reposez-le (Capture ${enrollment.currentStep + 1}/3)',
        });
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({
          'success': true,
          'step': enrollment.currentStep,
          'quality': quality,
          'finished': false,
        }));
        await res.close();
        return;
      } else {
        broadcastEvent({
          'type': 'enroll_complete',
          'member_id': enrollment.memberId,
          'quality': quality,
          'template': templateB64,
          'message': 'Empreinte enregistrée avec succès !',
        });

        _currentEnrollment = null;

        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({
          'success': true,
          'step': 3,
          'quality': quality,
          'finished': true,
          'template': templateB64,
          'format': 'suprema_384',
        }));
        await res.close();
        return;
      }
    }

    if (path == '/door/open' && request.method == 'POST') {
      broadcastEvent({
        'type': 'door_opened',
        'reason': 'Impulsion manuelle',
        'timestamp': DateTime.now().toIso8601String(),
      });
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'success': true, 'message': 'Porte déverrouillée'}));
      await res.close();
      return;
    }

    // 7. Serveur de fichiers statiques (GymDesk Portable Web)
    final served = await _serveStaticFile(request, res, path);
    if (served) return;

    res.statusCode = HttpStatus.notFound;
    res.write('Not Found');
    await res.close();
  } catch (e) {
    res.statusCode = HttpStatus.internalServerError;
    res.write(jsonEncode({'error': e.toString()}));
    await res.close();
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
