import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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
    this.isCloudBridge = false,
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
  final bool isCloudBridge;

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
    bool? isCloudBridge,
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
      isCloudBridge: isCloudBridge ?? this.isCloudBridge,
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

/// Kliyan HTTP ak Cloud Bridge pou kominike ak WhatsApp Web
class WhatsAppClient {
  WhatsAppClient({this.baseUrl = 'http://127.0.0.1:47812'});

  final String baseUrl;
  static bool _lastUsedCloudBridge = false;

  /// Netwaye epi mete nimewo nan bon fòma entènasyonal (egz: 50937001122)
  static String normalizePhone(String raw, {String defaultCountryCode = '509'}) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    final cleanCode = defaultCountryCode.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 8 && cleanCode.isNotEmpty) {
      digits = cleanCode + digits;
    }
    return digits;
  }

  /// Verifye estati sèvis WhatsApp la (Lokal premye, oswa Cloud Bridge Supabase si sou Web/Tablet)
  Future<WhatsAppState> checkStatus({String? validNumberFallback}) async {
    // 1. Eseye kominike dirèkteman ak sèvis lokal la (si nou sou PC)
    try {
      final uri = Uri.parse('$baseUrl/api/status');
      final response = await http.get(uri).timeout(const Duration(milliseconds: 1800));
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

        _lastUsedCloudBridge = false;
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
          isCloudBridge: false,
        );
      }
    } catch (_) {
      // Sèvis lokal la pa reponn (egz: nou sou yon Tablet, Telefòn, oswa Vercel Web)
    }

    // 2. Cloud Bridge: Rale estati a depi Supabase kote sèvis background lan voye heartbeat
    return await _checkStatusFromSupabase(validNumberFallback: validNumberFallback);
  }

  /// Rale estati sèvis la depi Supabase (Cloud Bridge)
  Future<WhatsAppState> _checkStatusFromSupabase({String? validNumberFallback}) async {
    try {
      final res = await Supabase.instance.client.rpc('platform_whatsapp_config_get');
      if (res != null) {
        final data = Map<String, dynamic>.from(res as Map);
        final isOnline = data['is_online'] as bool? ?? false;
        final rawStatus = data['service_status'] as String? ?? 'OFFLINE';

        final status = switch (rawStatus.toUpperCase()) {
          'READY' => isOnline ? WhatsAppStatus.ready : WhatsAppStatus.offline,
          'SCAN_QR' => isOnline ? WhatsAppStatus.scanQr : WhatsAppStatus.offline,
          'AUTHENTICATED' => isOnline ? WhatsAppStatus.authenticated : WhatsAppStatus.offline,
          'INITIALIZING' => isOnline ? WhatsAppStatus.initializing : WhatsAppStatus.offline,
          'ERROR' => WhatsAppStatus.error,
          _ => WhatsAppStatus.offline,
        };

        _lastUsedCloudBridge = true;
        return WhatsAppState(
          status: status,
          qrDataUrl: data['qr_code'] as String?,
          connectedPhone: data['connected_phone'] as String?,
          pushName: data['push_name'] as String?,
          validNumber: (data['valid_number'] as String? ?? validNumberFallback ?? '').trim(),
          defaultCountryCode: (data['default_country_code'] as String? ?? '509').trim(),
          autoSendWelcome: data['auto_send_welcome'] as bool? ?? true,
          autoSendReceipts: data['auto_send_receipts'] as bool? ?? true,
          autoSendReminders: data['auto_send_reminders'] as bool? ?? true,
          reminderDaysBefore: data['reminder_days_before'] as int? ?? 7,
          queueLength: (data['queue_length'] as num?)?.toInt() ?? 0,
          lastError: data['last_error'] as String?,
          lastChecked: DateTime.now(),
          isCloudBridge: true,
        );
      }
    } catch (e) {
      debugPrint('[WhatsApp] Erè lekti Supabase heartbeat: $e');
    }

    return WhatsAppState(
      status: WhatsAppStatus.offline,
      lastError: 'Sèvis WhatsApp la pa reponn',
      lastChecked: DateTime.now(),
    );
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
    // 1. Sove lokal si sèvis la aksesib
    try {
      final uri = Uri.parse('$baseUrl/api/config');
      await http.post(
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
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}

    // 2. Sove nan Supabase (pou tout aparèy jwenn li)
    try {
      await Supabase.instance.client.rpc('platform_whatsapp_config_set', params: {
        'p_gateway_url': baseUrl,
        'p_valid_number': validNumber.trim(),
        'p_default_country_code': defaultCountryCode.trim(),
        'p_auto_send_receipts': autoSendReceipts,
        'p_auto_send_reminders': autoSendReminders,
        'p_auto_send_welcome': autoSendWelcome,
        'p_reminder_days_before': reminderDaysBefore,
      });
      return true;
    } catch (e) {
      debugPrint('[WhatsApp] Erè sovgad config nan Supabase: $e');
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
    String kind = 'manual',
  }) async {
    // 1. Eseye voye lokalman si nou sou PC epi CloudBridge pa t nesesè
    if (!_lastUsedCloudBridge) {
      try {
        final uri = Uri.parse('$baseUrl/api/send');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'to': to.trim(),
            'message': message.trim(),
            if (pdfBase64 != null && pdfBase64.isNotEmpty) 'pdfBase64': pdfBase64,
            if (pdfFileName != null && pdfFileName.isNotEmpty) 'pdfFileName': pdfFileName,
          }),
        ).timeout(const Duration(seconds: 25));

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (response.statusCode == 200 && data['ok'] == true) {
          return WhatsAppSendResult(
            success: true,
            messageId: data['messageId'] as String?,
            to: data['to'] as String?,
          );
        }
      } catch (e) {
        debugPrint('[WhatsApp] Voye lokal echwe, n ap pase pa Cloud Bridge: $e');
      }
    }

    // 2. Voye atravè Cloud Bridge Supabase (Pou Tablet, Telefòn, ak Web)
    try {
      final cleanPhone = normalizePhone(to);
      final outboxId = await Supabase.instance.client.rpc(
        'whatsapp_enqueue_message',
        params: {
          'p_to_phone': cleanPhone,
          'p_message': message.trim(),
          'p_kind': kind,
          'p_pdf_base64': pdfBase64,
          'p_pdf_file_name': pdfFileName,
        },
      );
      return WhatsAppSendResult(
        success: true,
        messageId: outboxId?.toString(),
        to: cleanPhone,
      );
    } catch (cloudErr) {
      return WhatsAppSendResult(
        success: false,
        error: cloudErr.toString(),
      );
    }
  }

  /// Voye yon mesaj tès
  Future<WhatsAppSendResult> sendTestMessage({
    String? to,
    String? message,
  }) async {
    final targetPhone = to?.trim() ?? '';
    final msg = message?.trim() ?? '🏋️ *SecurGYM* - Tès mesaj koneksyon WhatsApp.';

    // 1. Eseye voye lokalman
    if (!_lastUsedCloudBridge) {
      try {
        final uri = Uri.parse('$baseUrl/api/test');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            if (targetPhone.isNotEmpty) 'to': targetPhone,
            'message': msg,
          }),
        ).timeout(const Duration(seconds: 15));

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (response.statusCode == 200 && data['ok'] == true) {
          return WhatsAppSendResult(
            success: true,
            messageId: data['messageId'] as String?,
            to: data['to'] as String? ?? targetPhone,
          );
        } else if (data['error'] != null) {
          return WhatsAppSendResult(
            success: false,
            error: data['error'] as String,
          );
        }
      } catch (e) {
        debugPrint('[WhatsApp] Tès lokal echwe, n ap pase pa Cloud Bridge: $e');
      }
    }

    // 2. Fallback Cloud Bridge Supabase
    try {
      final cleanPhone = normalizePhone(targetPhone);
      final outboxId = await Supabase.instance.client.rpc(
        'whatsapp_enqueue_message',
        params: {
          'p_to_phone': cleanPhone,
          'p_message': msg,
          'p_kind': 'test',
        },
      );
      return WhatsAppSendResult(
        success: true,
        messageId: outboxId?.toString(),
        to: cleanPhone,
      );
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
