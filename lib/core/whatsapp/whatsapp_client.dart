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

/// Rezime yon konvèsasyon WhatsApp (pou bouton Agrandi)
class WhatsAppChatSummary {
  const WhatsAppChatSummary({
    required this.id,
    required this.name,
    required this.phone,
    this.isGroup = false,
    this.unreadCount = 0,
    this.timestamp = 0,
    this.lastMessageBody = '',
    this.lastMessageFromMe = false,
    this.lastMessageHasMedia = false,
  });

  final String id;
  final String name;
  final String phone;
  final bool isGroup;
  final int unreadCount;
  final int timestamp;
  final String lastMessageBody;
  final bool lastMessageFromMe;
  final bool lastMessageHasMedia;

  factory WhatsAppChatSummary.fromJson(Map<String, dynamic> json) {
    final lm = json['lastMessage'] is Map
        ? Map<String, dynamic>.from(json['lastMessage'] as Map)
        : const <String, dynamic>{};
    return WhatsAppChatSummary(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['phone']?.toString() ?? 'Contact',
      phone: json['phone']?.toString() ?? '',
      isGroup: json['isGroup'] as bool? ?? false,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      lastMessageBody: lm['body']?.toString() ?? '',
      lastMessageFromMe: lm['fromMe'] as bool? ?? false,
      lastMessageHasMedia: lm['hasMedia'] as bool? ?? false,
    );
  }
}

/// Yon mesaj endividyèl nan yon konvèsasyon WhatsApp
class WhatsAppChatMessage {
  const WhatsAppChatMessage({
    required this.id,
    required this.body,
    required this.fromMe,
    required this.timestamp,
    this.type = 'chat',
    this.hasMedia = false,
  });

  final String id;
  final String body;
  final bool fromMe;
  final int timestamp;
  final String type;
  final bool hasMedia;

  factory WhatsAppChatMessage.fromJson(Map<String, dynamic> json) {
    return WhatsAppChatMessage(
      id: json['id']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      fromMe: json['fromMe'] as bool? ?? false,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      type: json['type']?.toString() ?? 'chat',
      hasMedia: json['hasMedia'] as bool? ?? false,
    );
  }
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

/// Modèl pou yon kont nan Cluster Multi-Kont WhatsApp la
class WhatsAppAccountInfo {
  const WhatsAppAccountInfo({
    required this.id,
    required this.accountIndex,
    required this.label,
    this.phoneNumber,
    this.pushName,
    required this.serviceStatus,
    this.qrCode,
    this.isEnabled = true,
    this.dailyLimit = 40,
    this.sentToday = 0,
    this.totalSent = 0,
    this.lastSentAt,
    this.lastHeartbeat,
    this.isOnline = false,
    this.restrictedUntil,
    this.restrictionReason,
    this.lastError,
  });

  final String id;
  final int accountIndex;
  final String label;
  final String? phoneNumber;
  final String? pushName;
  final String serviceStatus;
  final String? qrCode;
  final bool isEnabled;
  final int dailyLimit;
  final int sentToday;
  final int totalSent;
  final DateTime? lastSentAt;
  final DateTime? lastHeartbeat;
  final bool isOnline;
  final DateTime? restrictedUntil;
  final String? restrictionReason;
  final String? lastError;

  bool get isReady => serviceStatus.toUpperCase() == 'READY';
  bool get isWaitingForQr =>
      serviceStatus.toUpperCase() == 'SCAN_QR' ||
      (qrCode != null && qrCode!.isNotEmpty && serviceStatus.toUpperCase() != 'READY' && serviceStatus.toUpperCase() != 'RESTRICTED');
  bool get isError => serviceStatus.toUpperCase() == 'ERROR';
  bool get isDisconnected => serviceStatus.toUpperCase() == 'DISCONNECTED';
  bool get isInitializing => serviceStatus.toUpperCase() == 'INITIALIZING';
  bool get isRestricted {
    if (serviceStatus.toUpperCase() == 'RESTRICTED') {
      if (restrictedUntil == null) return true;
      return restrictedUntil!.isAfter(DateTime.now());
    }
    return false;
  }

  factory WhatsAppAccountInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      try {
        return DateTime.parse(val.toString());
      } catch (_) {
        return null;
      }
    }

    final rawStatus = (json['service_status'] ?? json['status'])?.toString() ?? 'DISCONNECTED';
    final rawQr = (json['qr_code'] ?? json['qr'] ?? json['rawQr'])?.toString();
    final rawIndex = (json['account_index'] ?? json['index'] as num?)?.toInt() ?? 1;
    final rawLabel = json['label']?.toString() ?? 'Liy ' + rawIndex.toString();
    final rawPhone = (json['phone_number'] ?? json['phone'])?.toString();
    final rawPush = (json['push_name'] ?? json['pushName'])?.toString();
    final rawEnabled = (json['is_enabled'] ?? json['isEnabled'] as bool?) ?? true;
    final rawDailyLimit = (json['daily_limit'] ?? json['dailyLimit'] as num?)?.toInt() ?? 40;
    final rawSentToday = (json['sent_today'] ?? json['sentToday'] as num?)?.toInt() ?? 0;
    final rawTotalSent = (json['total_sent'] ?? json['totalSent'] as num?)?.toInt() ?? 0;
    final rawOnline = (json['is_online'] ?? json['isOnline'] as bool?) ?? false;

    return WhatsAppAccountInfo(
      id: json['id']?.toString() ?? 'acc_' + rawIndex.toString(),
      accountIndex: rawIndex,
      label: rawLabel,
      phoneNumber: rawPhone,
      pushName: rawPush,
      serviceStatus: rawStatus,
      qrCode: rawQr,
      isEnabled: rawEnabled,
      dailyLimit: rawDailyLimit,
      sentToday: rawSentToday,
      totalSent: rawTotalSent,
      lastSentAt: parseDate(json['last_sent_at'] ?? json['lastSentAt']),
      lastHeartbeat: parseDate(json['last_heartbeat'] ?? json['lastHeartbeat']),
      isOnline: rawOnline,
      restrictedUntil: parseDate(json['restricted_until'] ?? json['restrictedUntil']),
      restrictionReason: (json['restriction_reason'] ?? json['restrictionReason'])?.toString(),
      lastError: (json['last_error'] ?? json['lastError'])?.toString(),
    );
  }
}

class WhatsAppClient {
  static const String defaultCloudGatewayUrl = 'https://cvisual-whatsapp-gateway.onrender.com';

  WhatsAppClient({this.baseUrl = defaultCloudGatewayUrl});

  final String baseUrl;

  /// Normalise URL sèvis WhatsApp la: ranplase ansyen adrès lokal (127.0.0.1/localhost) ak Cloud 24/7 la
  static String normalizeGatewayUrl(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isEmpty) return defaultCloudGatewayUrl;
    final lower = cleaned.toLowerCase();
    if (lower == 'http://127.0.0.1:47812' ||
        lower == 'http://localhost:47812' ||
        (kIsWeb && (lower.contains('127.0.0.1') || lower.contains('localhost')))) {
      return defaultCloudGatewayUrl;
    }
    return cleaned;
  }

  String get effectiveBaseUrl => normalizeGatewayUrl(baseUrl);

  static bool isFastLaneKind(String kind) {
    return const {'receipt', 'welcome', 'otp', 'test', 'manual_direct'}.contains(kind.trim().toLowerCase());
  }

  /// Netwaye epi mete nimewo nan bon fòma entènasyonal (egz: 50937001122)
  static String normalizePhone(String raw, {String defaultCountryCode = '509'}) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    final cleanCode = defaultCountryCode.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 8 && cleanCode.isNotEmpty) {
      digits = cleanCode + digits;
    }
    return digits;
  }

  /// Verifye estati sèvis WhatsApp la (Render Cloud HTTP premye, ak fallback Cloud Bridge Supabase)
  Future<WhatsAppState> checkStatus({String? validNumberFallback}) async {
    final targetBase = effectiveBaseUrl;
    // 1. Kominike dirèkteman ak sèvè Cloud 24h/24 la (oswa sèvis konfigire a)
    try {
      final uri = Uri.parse('$targetBase/api/status');
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
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

        final isCloud = data['securgym'] != null || targetBase.contains('onrender.com');
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
          isCloudBridge: isCloud,
        );
      }
    } catch (_) {
      // Fallback via Supabase si HTTP Render pa disponib tanporèman
    }

    // 2. Cloud Bridge: Rale estati a depi Supabase kote sèvis la voye heartbeat
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
          'DISCONNECTED' => isOnline ? WhatsAppStatus.disconnected : WhatsAppStatus.offline,
          'ERROR' => WhatsAppStatus.error,
          _ => WhatsAppStatus.offline,
        };

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
    final targetBase = effectiveBaseUrl;
    // 1. Sove dirèkteman sou sèvis Cloud / lokal la si aksesib
    try {
      final uri = Uri.parse('$targetBase/api/config');
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
      ).timeout(const Duration(seconds: 8));
    } catch (_) {}

    // 2. Sove nan Supabase (pou tout aparèy jwenn li)
    try {
      await Supabase.instance.client.rpc('platform_whatsapp_config_set', params: {
        'p_gateway_url': targetBase,
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
    final uri = Uri.parse('$effectiveBaseUrl/api/switch-account');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (newNumber != null && newNumber.isNotEmpty) 'newNumber': newNumber.trim(),
          if (backupNumber != null) 'backupNumber': backupNumber.trim(),
        }),
      ).timeout(const Duration(seconds: 20));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Voye yon mesaj WhatsApp (Fast Lane dirèk imedya vs Slow Lane pwoteksyon Anti-Ban)
  Future<WhatsAppSendResult> sendMessage({
    required String to,
    required String message,
    String? pdfBase64,
    String? pdfFileName,
    String kind = 'manual',
    String? gymId,
  }) async {
    final cleanPhone = normalizePhone(to);
    final normKind = kind.trim().toLowerCase();

    // 1. Fast Lane (Resi, Byenvini, OTP, Tès, Dirèk): voye imedyatman sou Render Cloud HTTP
    if (isFastLaneKind(normKind)) {
      try {
        final uri = Uri.parse('$effectiveBaseUrl/api/send');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'to': cleanPhone.isNotEmpty ? cleanPhone : to.trim(),
            'message': message.trim(),
            'kind': normKind,
            if (gymId != null && gymId.isNotEmpty) 'gymId': gymId,
            if (pdfBase64 != null && pdfBase64.isNotEmpty) 'pdfBase64': pdfBase64,
            if (pdfBase64 != null && pdfBase64.isNotEmpty) 'pdf_base64': pdfBase64,
            if (pdfFileName != null && pdfFileName.isNotEmpty) 'pdfFileName': pdfFileName,
            if (pdfFileName != null && pdfFileName.isNotEmpty) 'pdf_file_name': pdfFileName,
          }),
        ).timeout(const Duration(seconds: 25));

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if ((response.statusCode == 200 || response.statusCode == 202) && data['ok'] == true) {
          return WhatsAppSendResult(
            success: true,
            messageId: data['messageId']?.toString(),
            to: data['to']?.toString() ?? cleanPhone,
          );
        }
        if (response.statusCode == 422 && data['blocked'] == true) {
          return WhatsAppSendResult(
            success: false,
            error: data['error']?.toString() ?? 'Mesaj bloke pa pwoteksyon Anti-Ban.',
          );
        }
      } catch (e) {
        debugPrint('[WhatsApp] Voye HTTP echwe, n ap pase pa Supabase Outbox: $e');
      }
    }

    // 2. Slow Lane (Rapèl J-7 / J-2, Kanpay Marketing) oswa Fallback Outbox si Cloud HTTP tanporèman okipe
    try {
      final outboxId = await Supabase.instance.client.rpc(
        'whatsapp_enqueue_message',
        params: {
          'p_to_phone': cleanPhone,
          'p_message': message.trim(),
          'p_gym_id': (gymId != null && gymId.isNotEmpty) ? gymId : null,
          'p_kind': normKind,
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

  /// Voye yon mesaj tès dirèkteman (montre erè egzak la si Liy lan poko konekte)
  Future<WhatsAppSendResult> sendTestMessage({
    String? to,
    String? message,
  }) async {
    final targetPhone = to?.trim() ?? '';
    final msg = message?.trim() ?? '🏋️ *SecurGYM* - Tès mesaj koneksyon WhatsApp.';

    // 1. Eseye voye dirèkteman via HTTP Cloud 24h/24
    try {
      final uri = Uri.parse('$effectiveBaseUrl/api/test');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (targetPhone.isNotEmpty) 'to': targetPhone,
          'message': msg,
        }),
      ).timeout(const Duration(seconds: 25));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['ok'] == true) {
        return WhatsAppSendResult(
          success: true,
          messageId: data['messageId']?.toString(),
          to: data['to']?.toString() ?? targetPhone,
        );
      }
      return WhatsAppSendResult(
        success: false,
        error: data['error']?.toString() ?? 'Sèvis WhatsApp la retounen HTTP ${response.statusCode}.',
      );
    } catch (e) {
      debugPrint('[WhatsApp] Tès HTTP Cloud echwe, n ap pase pa Supabase Outbox: $e');
    }

    // 2. Fallback Supabase Outbox sèlman si sèvè HTTP a pa t ka jwenn
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
    final uri = Uri.parse('$effectiveBaseUrl/api/initialize');
    try {
      final response = await http.post(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return true;
    } catch (_) {}
    try {
      await Supabase.instance.client
          .from('platform_whatsapp_accounts')
          .update({'service_status': 'RESTART_REQUESTED'})
          .eq('account_index', 1);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reyinisyalize sesyon an nèt (wipe auth epi kreye nouvo sesyon)
  Future<bool> resetSession() async {
    final uri = Uri.parse('$effectiveBaseUrl/api/reset');
    try {
      final response = await http.post(uri).timeout(const Duration(seconds: 18));
      if (response.statusCode == 200) return true;
    } catch (_) {}
    try {
      await Supabase.instance.client
          .from('platform_whatsapp_accounts')
          .update({'service_status': 'RESET_REQUESTED'})
          .eq('account_index', 1);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Dekonekte sesyon WhatsApp la
  Future<bool> logout({bool clearSession = true}) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/logout');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'clearSession': clearSession}),
      ).timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Lese verifikasyon otomatik rapèl échéance sou Supabase
  Future<Map<String, dynamic>?> triggerExpirationCheck({String? targetGymId}) async {
    // 1. Eseye via sèvis Cloud HTTP
    try {
      final uri = Uri.parse('$effectiveBaseUrl/api/cron/check-expirations');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(targetGymId != null ? {'gymId': targetGymId} : {}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true && data['result'] != null) {
          return Map<String, dynamic>.from(data['result'] as Map);
        }
      }
    } catch (_) {}

    // 2. Cloud Bridge Supabase RPC
    try {
      final res = await Supabase.instance.client.rpc(
        'cron_check_whatsapp_expiration_reminders',
        params: targetGymId != null ? {'p_target_gym_id': targetGymId} : {},
      );
      if (res != null) {
        return Map<String, dynamic>.from(res as Map);
      }
    } catch (e) {
      debugPrint('[WhatsApp] Erè triggerExpirationCheck: $e');
    }
    return null;
  }

  /// Rale lis tout liy WhatsApp nan Cluster a depi sèvis Cloud la oswa Supabase
  Future<List<WhatsAppAccountInfo>> fetchAccountsList() async {
    // 1. Eseye dirèkteman via sèvis Cloud HTTP pou jwenn kòd QR ak estati an tan reyèl
    try {
      final uri = Uri.parse('$effectiveBaseUrl/api/accounts');
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true && data['accounts'] is List) {
          return (data['accounts'] as List)
              .map((a) => WhatsAppAccountInfo.fromJson(Map<String, dynamic>.from(a as Map)))
              .toList();
        }
      }
    } catch (_) {}

    // 2. Cloud Bridge Supabase RPC
    try {
      final res = await Supabase.instance.client.rpc('platform_whatsapp_accounts_list');
      if (res != null && res is List) {
        return res
            .map((a) => WhatsAppAccountInfo.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('[WhatsApp] Erè fetchAccountsList: $e');
    }
    return [];
  }

  /// Kreye yon nouvo plas liy WhatsApp nan cluster a
  Future<bool> createAccountSlot({required String label, int dailyLimit = 40}) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'platform_whatsapp_account_create',
        params: {'p_label': label, 'p_daily_limit': dailyLimit},
      );
      return res != null;
    } catch (e) {
      debugPrint('[WhatsApp] Erè createAccountSlot: $e');
      return false;
    }
  }

  /// Rekonekte / Rafrechi kòd QR yon liy espesifik
  Future<bool> restartAccount(int accountIndex) async {
    bool httpAttemptedAndRejected = false;
    try {
      final uri = Uri.parse('$effectiveBaseUrl/api/accounts/$accountIndex/initialize');
      final res = await http.post(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return true;
      if (res.statusCode == 409 || res.statusCode == 404) {
        httpAttemptedAndRejected = true;
      }
    } catch (_) {}

    if (httpAttemptedAndRejected) return false;

    try {
      await Supabase.instance.client
          .from('platform_whatsapp_accounts')
          .update({'service_status': 'RESTART_REQUESTED'})
          .eq('account_index', accountIndex);
      return true;
    } catch (e) {
      debugPrint('[WhatsApp] Erè restartAccount via Supabase: $e');
      return false;
    }
  }

  /// Efase sesyon yon liy (Wipe) pou eskane yon lòt nimewo
  Future<bool> resetAccountSession(int accountIndex) async {
    bool httpAttemptedAndRejected = false;
    try {
      final uri = Uri.parse('$effectiveBaseUrl/api/accounts/$accountIndex/reset');
      final res = await http.post(uri).timeout(const Duration(seconds: 18));
      if (res.statusCode == 200) return true;
      if (res.statusCode == 409 || res.statusCode == 404) {
        httpAttemptedAndRejected = true;
      }
    } catch (_) {}

    if (httpAttemptedAndRejected) return false;

    try {
      await Supabase.instance.client
          .from('platform_whatsapp_accounts')
          .update({'service_status': 'RESET_REQUESTED'})
          .eq('account_index', accountIndex);
      return true;
    } catch (e) {
      debugPrint('[WhatsApp] Erè resetAccountSession via Supabase: $e');
      return false;
    }
  }

  /// Debloke manyèlman yon liy ki te an restriksyon 24h
  Future<bool> unrestrictAccount(int accountIndex) async {
    try {
      await Supabase.instance.client.rpc(
        'platform_whatsapp_account_unrestrict',
        params: {'p_account_index': accountIndex},
      );
      try {
        final uri = Uri.parse('$effectiveBaseUrl/api/accounts/$accountIndex/unrestrict');
        await http.post(uri).timeout(const Duration(seconds: 10));
      } catch (_) {}
      return true;
    } catch (e) {
      debugPrint('[WhatsApp] Erè unrestrictAccount: $e');
      return false;
    }
  }

  /// Aktive oswa dezaktive yon liy
  Future<bool> toggleAccount(int accountIndex, bool isEnabled) async {
    try {
      await Supabase.instance.client.rpc(
        'platform_whatsapp_account_toggle',
        params: {'p_account_index': accountIndex, 'p_is_enabled': isEnabled},
      );
      return true;
    } catch (e) {
      debugPrint('[WhatsApp] Erè toggleAccount: $e');
      return false;
    }
  }

  /// Efase yon liy nan cluster a
  Future<bool> deleteAccountSlot(int accountIndex) async {
    try {
      await Supabase.instance.client.rpc(
        'platform_whatsapp_account_delete',
        params: {'p_account_index': accountIndex},
      );
      return true;
    } catch (e) {
      debugPrint('[WhatsApp] Erè deleteAccountSlot: $e');
      return false;
    }
  }

  /// Vue globale Contrôle des messages (Super Admin)
  Future<Map<String, dynamic>?> fetchControlOverview() async {
    try {
      final res = await Supabase.instance.client.rpc('platform_whatsapp_control_overview');
      if (res != null && res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('[WhatsApp] Erè fetchControlOverview: $e');
    }
    return null;
  }

  /// Envoi groupé sécurisé anti-doublon (Inscriptions manquées + J-7/J-2 + Retry échecs)
  Future<Map<String, dynamic>?> dispatchControlBatch({
    bool includeMissedRegistrations = true,
    bool includeRenewals = true,
    bool retryFailed = false,
  }) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'platform_whatsapp_dispatch_batch',
        params: {
          'p_include_missed_registrations': includeMissedRegistrations,
          'p_include_renewals': includeRenewals,
          'p_retry_failed': retryFailed,
        },
      );
      if (res != null && res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('[WhatsApp] Erè dispatchControlBatch: $e');
    }
    return null;
  }

  /// Relancer un message spécifique en échec
  Future<bool> retryOutboxItem(String outboxId) async {
    try {
      await Supabase.instance.client
          .from('whatsapp_messages_outbox')
          .update({
            'status': 'pending',
            'error_message': null,
            'attempts': 0,
            'retry_count': 0,
            'processed_at': null,
          })
          .eq('id', outboxId);
      return true;
    } catch (e) {
      debugPrint('[WhatsApp] Erè retryOutboxItem: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> _runRemoteBridgeCommand({
    required int accountIndex,
    required String action,
    required Map<String, dynamic> payload,
    Duration timeout = const Duration(seconds: 16),
  }) async {
    final sb = Supabase.instance.client;
    final inserted = await sb
        .from('whatsapp_bridge_commands')
        .insert({
          'account_index': accountIndex,
          'action': action,
          'payload': payload,
          'status': 'pending',
        })
        .select('id')
        .single();
    final cmdId = inserted['id'].toString();
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      final row = await sb
          .from('whatsapp_bridge_commands')
          .select('status, result, error_message')
          .eq('id', cmdId)
          .single();
      final status = row['status']?.toString() ?? 'pending';
      if (status == 'done') {
        final rawResult = row['result'];
        return rawResult is Map
            ? Map<String, dynamic>.from(rawResult)
            : <String, dynamic>{};
      }
      if (status == 'error') {
        throw Exception(row['error_message']?.toString() ?? 'Erreur serveur WhatsApp');
      }
    }
    throw TimeoutException('Le service WhatsApp Cloud n\'a pas répondu à temps.');
  }

  /// Liste des conversations pour "Agrandir WhatsApp" (Cloud HTTP ou Bridge Web)
  Future<List<WhatsAppChatSummary>> fetchAccountChats(int accountIndex, {int limit = 35}) async {
    try {
      final uri = Uri.parse('$effectiveBaseUrl/api/accounts/$accountIndex/chats?limit=$limit');
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true && data['chats'] is List) {
          return (data['chats'] as List)
              .map((c) => WhatsAppChatSummary.fromJson(Map<String, dynamic>.from(c as Map)))
              .toList();
        }
      }
    } catch (_) {}

    final remote = await _runRemoteBridgeCommand(
      accountIndex: accountIndex,
      action: 'list_chats',
      payload: {'limit': limit},
    );
    final chatsRaw = (remote['chats'] as List?) ?? const [];
    return chatsRaw
        .map((c) => WhatsAppChatSummary.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();
  }

  /// Messages d'un chat pour "Agrandir WhatsApp" (Cloud HTTP ou Bridge Web)
  Future<List<WhatsAppChatMessage>> fetchChatMessages(
    int accountIndex,
    String chatId, {
    int limit = 50,
  }) async {
    try {
      final encoded = Uri.encodeComponent(chatId);
      final uri = Uri.parse('$effectiveBaseUrl/api/accounts/$accountIndex/chats/$encoded/messages?limit=$limit');
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true && data['messages'] is List) {
          return (data['messages'] as List)
              .map((m) => WhatsAppChatMessage.fromJson(Map<String, dynamic>.from(m as Map)))
              .toList();
        }
      }
    } catch (_) {}

    final remote = await _runRemoteBridgeCommand(
      accountIndex: accountIndex,
      action: 'get_messages',
      payload: {'chatId': chatId, 'limit': limit},
    );
    final msgsRaw = (remote['messages'] as List?) ?? const [];
    return msgsRaw
        .map((m) => WhatsAppChatMessage.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  /// Envoyer un message interactif depuis "Agrandir WhatsApp"
  Future<WhatsAppChatMessage?> sendChatMessage(
    int accountIndex,
    String chatId,
    String message,
  ) async {
    try {
      final uri = Uri.parse('$effectiveBaseUrl/api/accounts/$accountIndex/chats/send');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'chatId': chatId, 'message': message.trim()}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true && data['message'] is Map) {
          return WhatsAppChatMessage.fromJson(Map<String, dynamic>.from(data['message'] as Map));
        }
      }
    } catch (_) {}

    final remote = await _runRemoteBridgeCommand(
      accountIndex: accountIndex,
      action: 'send_chat',
      payload: {'chatId': chatId, 'message': message.trim()},
    );
    if (remote['message'] is Map) {
      return WhatsAppChatMessage.fromJson(Map<String, dynamic>.from(remote['message'] as Map));
    }
    return null;
  }

}

/// Riverpod provider pou kliyan WhatsApp la
final whatsAppClientProvider = Provider<WhatsAppClient>((ref) {
  return WhatsAppClient();
});
