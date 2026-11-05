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
    this.backupNumber = '',
    this.defaultCountryCode = '509',
    this.autoSendWelcome = true,
    this.autoSendReceipts = true,
    this.autoSendReminders = true,
    this.reminderDaysBefore = 7,
    this.queueLength = 0,
    this.lastError,
    this.lastChecked,
  });

  final WhatsAppStatus status;
  final String? qrDataUrl;
  final String? rawQr;
  final String? connectedPhone;
  final String? pushName;
  final String validNumber;
  final String backupNumber;
  final String defaultCountryCode;
  final bool autoSendWelcome;
  final bool autoSendReceipts;
  final bool autoSendReminders;
  final int reminderDaysBefore;
  final int queueLength;
  final String? lastError;
  final DateTime? lastChecked;

  bool get isReady => status == WhatsAppStatus.ready;
  bool get isWaitingForQr => status == WhatsAppStatus.scanQr;
  bool get isOffline => status == WhatsAppStatus.offline;
  bool get isError => status == WhatsAppStatus.error;
  bool get isInitializing => status == WhatsAppStatus.initializing;

  WhatsAppState copyWith({
    WhatsAppStatus? status,
    String? qrDataUrl,
    String? rawQr,
    String? connectedPhone,
    String? pushName,
    String? validNumber,
    String? backupNumber,
    String? defaultCountryCode,
    bool? autoSendWelcome,
    bool? autoSendReceipts,
    bool? autoSendReminders,
    int? reminderDaysBefore,
    int? queueLength,
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
      backupNumber: backupNumber ?? this.backupNumber,
      defaultCountryCode: defaultCountryCode ?? this.defaultCountryCode,
      autoSendWelcome: autoSendWelcome ?? this.autoSendWelcome,
      autoSendReceipts: autoSendReceipts ?? this.autoSendReceipts,
      autoSendReminders: autoSendReminders ?? this.autoSendReminders,
      reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
      queueLength: queueLength ?? this.queueLength,
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

/// Modèl pou jesyon aksè abònman WhatsApp yon Gym pa Super Admin
class GymWhatsAppAccess {
  const GymWhatsAppAccess({
    required this.gymId,
    required this.gymName,
    required this.gymCode,
    this.gymPhone = '',
    required this.isEnabled,
    required this.status,
    this.startDate,
    this.endDate,
    this.backupPhone = '',
    this.notes = '',
    this.daysRemaining = 0,
    this.isValid = false,
  });

  final String gymId;
  final String gymName;
  final String gymCode;
  final String gymPhone;
  final bool isEnabled;
  final String status; // 'active', 'suspended', 'expired', 'inactive'
  final DateTime? startDate;
  final DateTime? endDate;
  final String backupPhone;
  final String notes;
  final int daysRemaining;
  final bool isValid;

  factory GymWhatsAppAccess.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      try {
        return DateTime.parse(val.toString());
      } catch (_) {
        return null;
      }
    }

    return GymWhatsAppAccess(
      gymId: json['gym_id']?.toString() ?? '',
      gymName: json['gym_name']?.toString() ?? 'Gym',
      gymCode: json['gym_code']?.toString() ?? '',
      gymPhone: json['gym_phone']?.toString() ?? '',
      isEnabled: json['is_enabled'] as bool? ?? false,
      status: json['status']?.toString() ?? 'inactive',
      startDate: parseDate(json['start_date']),
      endDate: parseDate(json['end_date']),
      backupPhone: json['backup_phone']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      daysRemaining: (json['days_remaining'] as num?)?.toInt() ?? 0,
      isValid: json['is_valid'] as bool? ?? false,
    );
  }
}

/// Rezilta verifikasyon aksè abònman WhatsApp pou yon Gym
class WhatsAppAccessCheckResult {
  const WhatsAppAccessCheckResult({
    required this.hasAccess,
    required this.status,
    this.daysRemaining = 0,
    this.startDate,
    this.endDate,
    this.backupPhone = '',
    this.message = '',
  });

  final bool hasAccess;
  final String status; // 'active', 'suspended', 'expired', 'inactive'
  final int daysRemaining;
  final DateTime? startDate;
  final DateTime? endDate;
  final String backupPhone;
  final String message;

  factory WhatsAppAccessCheckResult.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      try {
        return DateTime.parse(val.toString());
      } catch (_) {
        return null;
      }
    }

    return WhatsAppAccessCheckResult(
      hasAccess: json['has_access'] as bool? ?? false,
      status: json['status']?.toString() ?? 'inactive',
      daysRemaining: (json['days_remaining'] as num?)?.toInt() ?? 0,
      startDate: parseDate(json['start_date']),
      endDate: parseDate(json['end_date']),
      backupPhone: json['backup_phone']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
    );
  }
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
          backupNumber: (config['backupNumber'] as String? ?? '').trim(),
          defaultCountryCode: (config['defaultCountryCode'] as String? ?? '509').trim(),
          autoSendWelcome: config['autoSendWelcome'] as bool? ?? true,
          autoSendReceipts: config['autoSendReceipts'] as bool? ?? true,
          autoSendReminders: config['autoSendReminders'] as bool? ?? true,
          reminderDaysBefore: config['reminderDaysBefore'] as int? ?? 7,
          queueLength: (data['queueLength'] as num?)?.toInt() ?? 0,
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

  /// Anrejistre konfigirasyon an nan sèvis la (nimewo valid, backup, etc.)
  Future<bool> saveConfig({
    required String validNumber,
    String backupNumber = '',
    String defaultCountryCode = '509',
    bool autoSendWelcome = true,
    bool autoSendReceipts = true,
    bool autoSendReminders = true,
    int reminderDaysBefore = 7,
  }) async {
    final uri = Uri.parse('$baseUrl/api/config');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'validNumber': validNumber.trim(),
          'backupNumber': backupNumber.trim(),
          'defaultCountryCode': defaultCountryCode.trim(),
          'autoSendWelcome': autoSendWelcome,
          'autoSendReceipts': autoSendReceipts,
          'autoSendReminders': autoSendReminders,
          'reminderDaysBefore': reminderDaysBefore,
        }),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Chanje nimewo WhatsApp oswa konekte yon nouvo nimewo (Switch Account / Clear Auth)
  Future<bool> switchAccount({String? newNumber, String? backupNumber}) async {
    final uri = Uri.parse('$baseUrl/api/switch-account');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (newNumber != null && newNumber.isNotEmpty) 'newNumber': newNumber.trim(),
          if (backupNumber != null) 'backupNumber': backupNumber.trim(),
        }),
      ).timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Voye yon mesaj WhatsApp (ak sipò dokiman PDF si bay)
  Future<WhatsAppSendResult> sendMessage({
    required String to,
    required String message,
    String? pdfBase64,
    String? pdfFileName,
  }) async {
    final uri = Uri.parse('$baseUrl/api/send');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'to': to.trim(),
          'message': message.trim(),
          if (pdfBase64 != null && pdfBase64.isNotEmpty) 'pdfBase64': pdfBase64,
          if (pdfFileName != null && pdfFileName.isNotEmpty) 'pdfFileName': pdfFileName,
        }),
      ).timeout(const Duration(seconds: 40));

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
      final response = await http.post(uri).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Reyinisyalize sesyon an nèt (wipe .wwebjs_auth epi kreye nouvo sesyon)
  Future<bool> resetSession() async {
    final uri = Uri.parse('$baseUrl/api/reset');
    try {
      final response = await http.post(uri).timeout(const Duration(seconds: 15));
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
      ).timeout(const Duration(seconds: 10));
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
