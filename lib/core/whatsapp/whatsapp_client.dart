import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Estati koneksyon WhatsApp
enum WhatsAppStatus {
  disconnected,
  initializing,
  scanQr,
  authenticated,
  ready,
  error,
  offline,
}

/// Eta konplè sèvis WhatsApp la
class WhatsAppState {
  const WhatsAppState({
    required this.status,
    this.qrDataUrl,
    this.rawQr,
    this.connectedPhone,
    this.pushName,
    this.validNumber = '',
    this.defaultCountryCode = '509',
    this.autoSendReceipts = true,
    this.autoSendReminders = true,
    this.lastError,
    this.lastChecked,
  });

  final WhatsAppStatus status;
  final String? qrDataUrl;
  final String? rawQr;
  final String? connectedPhone;
  final String? pushName;
  final String validNumber;
  final String defaultCountryCode;
  final bool autoSendReceipts;
  final bool autoSendReminders;
  final String? lastError;
  final DateTime? lastChecked;

  bool get isReady => status == WhatsAppStatus.ready;
  bool get isWaitingForQr => status == WhatsAppStatus.scanQr;
  bool get isOffline => status == WhatsAppStatus.offline;

  WhatsAppState copyWith({
    WhatsAppStatus? status,
    String? qrDataUrl,
    String? rawQr,
    String? connectedPhone,
    String? pushName,
    String? validNumber,
    String? defaultCountryCode,
    bool? autoSendReceipts,
    bool? autoSendReminders,
    String? lastError,
    DateTime? lastChecked,
  }) {
    return WhatsAppState(
      status: status ?? this.status,
      qrDataUrl: qrDataUrl ?? this.qrDataUrl,
      rawQr: rawQr ?? this.rawQr,
      connectedPhone: connectedPhone ?? this.connectedPhone,
      pushName: pushName ?? this.pushName,
      validNumber: validNumber ?? this.validNumber,
      defaultCountryCode: defaultCountryCode ?? this.defaultCountryCode,
      autoSendReceipts: autoSendReceipts ?? this.autoSendReceipts,
      autoSendReminders: autoSendReminders ?? this.autoSendReminders,
      lastError: lastError,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

/// Rezilta voye mesaj
class WhatsAppSendResult {
  const WhatsAppSendResult({
    required this.success,
    this.messageId,
    this.to,
    this.error,
  });

  final bool success;
  final String? messageId;
  final String? to;
  final String? error;
}

/// Kliyan HTTP pou kominike ak sèvis Node.js whatsapp-web.js la
class WhatsAppClient {
  WhatsAppClient({this.baseUrl = 'http://127.0.0.1:47812'});

  final String baseUrl;

  /// Netwaye epi mete nimewo nan bon fòma entènasyonal (egz: 50937001122)
  static String normalizePhone(String raw, {String defaultCountryCode = '509'}) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    final cleanCode = defaultCountryCode.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 8 && cleanCode.isNotEmpty) {
      digits = cleanCode + digits;
    }
    return digits;
  }

  /// Verifye estati sèvis WhatsApp la
  Future<WhatsAppState> checkStatus({String? validNumberFallback}) async {
    final uri = Uri.parse('$baseUrl/api/status');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawStatus = data['status'] as String? ?? 'DISCONNECTED';
        final config = data['config'] as Map<String, dynamic>? ?? {};

        final status = switch (rawStatus.toUpperCase()) {
          'READY' => WhatsAppStatus.ready,
          'SCAN_QR' => WhatsAppStatus.scanQr,
          'AUTHENTICATED' => WhatsAppStatus.authenticated,
          'INITIALIZING' => WhatsAppStatus.initializing,
          'ERROR' => WhatsAppStatus.error,
          _ => WhatsAppStatus.disconnected,
        };

        return WhatsAppState(
          status: status,
          qrDataUrl: data['qr'] as String?,
          rawQr: data['rawQr'] as String?,
          connectedPhone: data['phone'] as String?,
          pushName: data['pushname'] as String?,
          validNumber: (config['validNumber'] as String? ?? validNumberFallback ?? '').trim(),
          defaultCountryCode: (config['defaultCountryCode'] as String? ?? '509').trim(),
          autoSendReceipts: config['autoSendReceipts'] as bool? ?? true,
          autoSendReminders: config['autoSendReminders'] as bool? ?? true,
          lastError: data['lastError'] as String?,
          lastChecked: DateTime.now(),
        );
      }
      return WhatsAppState(
        status: WhatsAppStatus.offline,
        lastError: 'HTTP ${response.statusCode}',
        lastChecked: DateTime.now(),
      );
    } catch (e) {
      return WhatsAppState(
        status: WhatsAppStatus.offline,
        lastError: e.toString(),
        lastChecked: DateTime.now(),
      );
    }
  }

  /// Anrejistre konfigirasyon an nan sèvis la (nimewo valid, etc.)
  Future<bool> saveConfig({
    required String validNumber,
    String defaultCountryCode = '509',
    bool autoSendReceipts = true,
    bool autoSendReminders = true,
  }) async {
    final uri = Uri.parse('$baseUrl/api/config');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'validNumber': validNumber.trim(),
          'defaultCountryCode': defaultCountryCode.trim(),
          'autoSendReceipts': autoSendReceipts,
          'autoSendReminders': autoSendReminders,
        }),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Voye yon mesaj WhatsApp
  Future<WhatsAppSendResult> sendMessage({
    required String to,
    required String message,
  }) async {
    final uri = Uri.parse('$baseUrl/api/send');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'to': to.trim(),
          'message': message.trim(),
        }),
      ).timeout(const Duration(seconds: 25));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['ok'] == true) {
        return WhatsAppSendResult(
          success: true,
          messageId: data['messageId'] as String?,
          to: data['to'] as String?,
        );
      } else {
        return WhatsAppSendResult(
          success: false,
          error: data['error'] as String? ?? 'Echèk voye mesaj',
        );
      }
    } catch (e) {
      return WhatsAppSendResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Voye yon mesaj tès
  Future<WhatsAppSendResult> sendTestMessage({
    String? to,
    String? message,
  }) async {
    final uri = Uri.parse('$baseUrl/api/test');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (to != null && to.isNotEmpty) 'to': to.trim(),
          if (message != null && message.isNotEmpty) 'message': message.trim(),
        }),
      ).timeout(const Duration(seconds: 25));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['ok'] == true) {
        return WhatsAppSendResult(
          success: true,
          messageId: data['messageId'] as String?,
          to: data['to'] as String?,
        );
      } else {
        return WhatsAppSendResult(
          success: false,
          error: data['error'] as String? ?? 'Echèk tès',
        );
      }
    } catch (e) {
      return WhatsAppSendResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Rekonekte / Rafrechi kòd QR
  Future<bool> reconnect() async {
    final uri = Uri.parse('$baseUrl/api/initialize');
    try {
      final response = await http.post(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Dekonekte sesyon WhatsApp la
  Future<bool> logout({bool clearSession = true}) async {
    final uri = Uri.parse('$baseUrl/api/logout');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'clearSession': clearSession}),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

/// Riverpod provider pou kliyan WhatsApp la
final whatsAppClientProvider = Provider<WhatsAppClient>((ref) {
  return WhatsAppClient();
});
