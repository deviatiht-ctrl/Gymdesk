import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AccessAgentStatus {
  const AccessAgentStatus({
    required this.connected,
    required this.readerConnected,
    required this.doorConnected,
    this.readerName,
    this.readerSerial,
    this.sdkError,
    this.doorName,
    this.version,
  });

  final bool connected;
  final bool readerConnected;
  final bool doorConnected;
  final String? readerName;
  final String? readerSerial;
  final String? sdkError;
  final String? doorName;
  final String? version;

  factory AccessAgentStatus.disconnected() => const AccessAgentStatus(
        connected: false,
        readerConnected: false,
        doorConnected: false,
      );
}

class AccessAgentClient {
  AccessAgentClient({this.baseUrl = 'http://127.0.0.1:47811'});

  final String baseUrl;
  final ValueNotifier<AccessAgentStatus> status =
      ValueNotifier<AccessAgentStatus>(AccessAgentStatus.disconnected());

  Timer? _pollTimer;

  void startMonitoring() {
    checkHealth();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => checkHealth());
  }

  Future<AccessAgentStatus> checkHealth() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/health')).timeout(
            const Duration(seconds: 2),
          );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final current = AccessAgentStatus(
          connected: true,
          readerConnected: data['reader_connected'] == true,
          doorConnected: data['door_connected'] == true,
          readerName: data['reader_name']?.toString(),
          readerSerial: data['reader_serial']?.toString(),
          sdkError: data['sdk_error']?.toString(),
          doorName: data['door_name']?.toString(),
          version: data['version']?.toString(),
        );
        status.value = current;
        return current;
      }
    } catch (_) {}

    final disconnected = AccessAgentStatus.disconnected();
    status.value = disconnected;
    return disconnected;
  }

  Future<bool> startEnrollment(String memberId) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/enroll/start'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'member_id': memberId}),
          )
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Kapti reyèl sou lektè a. Bloke jiskaske yon dwèt poze oswa [timeout].
  /// Retounen `{success, template, quality}` oswa `{success:false, error, message}`.
  Future<Map<String, dynamic>> capture({
    Duration timeout = const Duration(seconds: 10),
    int minQuality = 50,
    // 'suprema' = fòma natif 384B (konpatib BioEntry W2); defo ISO 19794-2.
    String? tpl,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/capture'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'timeout_ms': timeout.inMilliseconds,
              'min_quality': minQuality,
              'tpl': ?tpl,
            }),
          )
          .timeout(timeout + const Duration(seconds: 5));
      final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
      if (body is Map<String, dynamic>) return body;
    } on TimeoutException {
      return {'success': false, 'error': 'timeout', 'message': 'Délai de capture dépassé.'};
    } catch (_) {}
    return {
      'success': false,
      'error': 'agent_offline',
      'message': 'Agent SecurGYM (access_agent.exe) injoignable.',
    };
  }

  /// Verifikasyon 1:1 pa algorit SDK a. `null` si agent la pa disponib.
  Future<bool?> match(String probe, String template) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/match'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'probe': probe, 'template': template}),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['match'] == true;
      }
    } catch (_) {}
    return null;
  }

  /// Idantifikasyon 1:N. Retounen id kandida a, oswa `null`.
  Future<String?> identify(String probe, List<Map<String, String>> candidates) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/identify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'probe': probe, 'candidates': candidates}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['id']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<bool> manualDoorOpen(String reason) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/door/open'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'reason': reason}),
          )
          .timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> listUsbDevices() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/devices'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = data['devices'] as List? ?? [];
        return List<Map<String, dynamic>>.from(list);
      }
    } catch (_) {}
    return [];
  }

  Future<bool> syncTerminalMember({
    required String userId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required List<String> templates,
    String? terminalIp,
  }) async {
    try {
      const start = 978307200; // 2001-01-01 00:00:00 UTC (defaultStart BioStar 2)
      final endRaw = DateTime.utc(
                endDate.year,
                endDate.month,
                endDate.day,
                23,
                59,
                59,
              ).millisecondsSinceEpoch ~/
              1000 +
          5 * 3600;
      final end = endRaw.clamp(978307201, 1924991999);
      final fingers = [
        for (final t in templates)
          if (t.trim().isNotEmpty) [t.trim()],
      ];
      final res = await syncTerminalMembers([
        {
          'id': userId,
          'name': name.length > 48 ? name.substring(0, 48) : name,
          'start': start,
          'end': end,
          'fingers': fingers,
        }
      ], terminalIp: terminalIp);
      return res?['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pingTerminal({String? terminalIp}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/terminals/ping'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (terminalIp != null && terminalIp.isNotEmpty) 'ip': terminalIp,
        }),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['online'] == true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> pulseTerminalRelay({String? terminalIp, int seconds = 3}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/terminals/pulse'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'terminal': 'BioEntry W2',
          if (terminalIp != null && terminalIp.isNotEmpty) 'ip': terminalIp,
          'seconds': seconds,
        }),
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body);
      return data is! Map || data['success'] != false;
    } catch (_) {
      return false;
    }
  }

  /// Chèche tèminal Suprema sou rezo lokal la (via BioStar Device SDK)
  Future<List<Map<String, dynamic>>> searchTerminals() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/terminals'),
      ).timeout(const Duration(seconds: 25));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return [
          for (final d in (data['devices'] as List? ?? const []))
            Map<String, dynamic>.from(d as Map),
        ];
      }
    } catch (_) {}
    return const [];
  }

  /// Pouse anprent manm yo sou tèminal BioEntry W2 a (BS2_EnrollUser).
  /// [members]: [{id, name, fingers: [[b64 t1, b64 t2?], ...]}]
  /// Template yo dwe fòma natif Suprema (384B) — capture ak tpl:'suprema'.
  Future<Map<String, dynamic>?> syncTerminalMembers(
    List<Map<String, dynamic>> members, {
    String? terminalIp,
    List<String> remove = const [],
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/terminals/sync'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'members': members,
          'remove': remove,
          if (terminalIp != null && terminalIp.isNotEmpty) 'ip': terminalIp,
        }),
      ).timeout(const Duration(seconds: 90));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  /// Chwazi tèminal agent la siveye (evènman an tan reyèl) epi retounen eta l.
  Future<bool> watchTerminal({String? terminalIp}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/terminals/watch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ip': ?terminalIp}),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return (jsonDecode(res.body) as Map<String, dynamic>)['online'] == true;
      }
    } catch (_) {}
    return false;
  }

  /// Flux evènman agent la (tèminal W2: idantifikasyon, refi, pòt) via
  /// long-polling — mache sou web kote package:http pa ka li SSE.
  Stream<Map<String, dynamic>> terminalEvents() {
    late final StreamController<Map<String, dynamic>> controller;
    var running = true;
    Future<void> loop() async {
      var since = -1;
      while (running) {
        try {
          final res = await http
              .get(Uri.parse('$baseUrl/api/events/poll?since=$since&wait=20'))
              .timeout(const Duration(seconds: 30));
          if (res.statusCode != 200) throw const FormatException();
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final seq = (data['seq'] as num?)?.toInt() ?? 0;
          for (final e in (data['events'] as List? ?? const [])) {
            if (running) controller.add(Map<String, dynamic>.from(e as Map));
          }
          if (running) {
            controller.add({'type': 'agent_status', 'online': true, 'terminal_watch': data['terminal_watch'] == true});
          }
          since = seq;
        } catch (_) {
          if (running) controller.add({'type': 'agent_status', 'online': false, 'terminal_watch': false});
          await Future<void>.delayed(const Duration(seconds: 3));
          since = -1;
        }
      }
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () => unawaited(loop()),
      onCancel: () => running = false,
    );
    return controller.stream;
  }

  Future<bool> releaseTerminalDoor({String? terminalIp}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/terminals/release'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (terminalIp != null && terminalIp.isNotEmpty) 'ip': terminalIp,
        }),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    status.dispose();
  }
}
