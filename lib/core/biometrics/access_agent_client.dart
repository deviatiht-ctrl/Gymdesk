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
    this.doorName,
    this.version,
  });

  final bool connected;
  final bool readerConnected;
  final bool doorConnected;
  final String? readerName;
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
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => checkHealth());
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

  Future<Map<String, dynamic>> captureStep() async {
    try {
      final res = await http
          .post(Uri.parse('$baseUrl/enroll/capture'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'success': false};
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
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/terminals/sync'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user': {
            'user_id': userId,
            'name': name,
            'start_date': startDate.toIso8601String(),
            'end_date': endDate.toIso8601String(),
            'templates': templates,
          }
        }),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pingTerminal({String? terminalIp}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/terminals/ping'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ip': terminalIp ?? '192.168.1.105'}),
      ).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['online'] == true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> pulseTerminalRelay() async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/terminals/pulse'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'terminal': 'BioEntry W2'}),
      ).timeout(const Duration(seconds: 4));
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
