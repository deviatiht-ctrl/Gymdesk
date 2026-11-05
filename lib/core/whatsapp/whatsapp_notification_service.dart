import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/providers.dart';
import '../sync/sync_models.dart';
import '../whatsapp/whatsapp_client.dart';
import '../../features/payments/data/receipt_pdf.dart';

/// Sèvis Otomatik pou notifikasyon WhatsApp SecurGYM
/// Responsab pou:
/// 1. Verifye si gym nan gen aksè abònman aktif pou sèvis WhatsApp
/// 2. Voye mesaj byenvini lè yon moun fin enskri (ak lyen espas manm li, nimewo li, etc.)
/// 3. Voye resi peman an otomatikman an PDF sou WhatsApp
/// 4. Sistèm Entèlijan Otomatik: Voye rapèl abònman (7 jou, 2 jou, jou fen an ak lè l fini) san entèvansyon manyèl
/// 5. Asire tout mesaj gen nòt obligatwa pou anrejistre nimewo a sou non "SecurGYM"
///    epi bay nimewo telefòn ofisyèl gym lan pou yo ka reponn olye yo reponn sou bot la.
class WhatsAppNotificationService {
  WhatsAppNotificationService(this._client, this._ref);

  final WhatsAppClient _client;
  final Ref _ref;

  // Cache pou evite voye menm rapèl la 2 fwa nan menm jounen an
  static final Set<String> _sentReminderKeys = {};

  // Jesyon Automatizasyon an background
  Timer? _autoTimer;
  DateTime? _lastAutoCheckTime;
  int _lastAutoSentCount = 0;
  bool _isAutoChecking = false;

  DateTime? get lastAutoCheckTime => _lastAutoCheckTime;
  int get lastAutoSentCount => _lastAutoSentCount;
  bool get isAutoChecking => _isAutoChecking;
  bool get isAutomationRunning => _autoTimer != null;

  /// Demare siveyans otomatik la an background (kouri otomatikman san klik)
  void startAutomatedBackgroundChecker() {
    if (_autoTimer != null) return;
    debugPrint('[WhatsApp] Demaraj sèvis automatizasyon entèlijan SecurGYM (tcheke chak 60 minit)...');

    // Premye verifikasyon apre 15 segond lè tout baz ak sesyon fin estabilize
    Timer(const Duration(seconds: 15), () {
      runAutomatedExpirationCheck();
    });

    // Kouri chak 60 minit regilyèman
    _autoTimer = Timer.periodic(const Duration(minutes: 60), (_) {
      runAutomatedExpirationCheck();
    });
  }

  /// Kanpe siveyans otomatik la si sa nesesè
  void stopAutomatedBackgroundChecker() {
    _autoTimer?.cancel();
    _autoTimer = null;
    debugPrint('[WhatsApp] Sèvis automatizasyon rapèl kanpe.');
  }

  /// Kouri yon sik verifikasyon entèlijan konplè
  Future<int> runAutomatedExpirationCheck() async {
    if (_isAutoChecking) return 0;
    _isAutoChecking = true;
    try {
      final lang = _ref.read(appLanguageProvider).languageCode;
      final count = await checkAndSendPendingExpirationReminders(languageCode: lang);
      _lastAutoCheckTime = DateTime.now();
      _lastAutoSentCount = count;
      debugPrint('[WhatsApp] Verifikasyon otomatik fini: $count rapèl voye.');
      return count;
    } catch (e) {
      debugPrint('[WhatsApp] Erè pandan automatizasyon rapèl: $e');
      return 0;
    } finally {
      _isAutoChecking = false;
    }
  }

  /// Verifye si gym nan gen dwa voye mesaj WhatsApp (Abònman valab, pa sispann, pa ekspire)
  Future<WhatsAppAccessCheckResult> checkGymAccess({String? gymId}) async {
    final runtime = _ref.read(appRuntimeProvider);
    final isSuper = runtime.session?.isPlatformAdmin == true;
    if (isSuper) {
      return const WhatsAppAccessCheckResult(
        hasAccess: true,
        status: 'active',
        daysRemaining: 999,
        message: 'Aksè Super Admin aktif.',
      );
    }

    final targetGymId = gymId ?? runtime.session?.gymId;
    if (targetGymId == null || targetGymId.isEmpty) {
      return const WhatsAppAccessCheckResult(
        hasAccess: false,
        status: 'inactive',
        message: 'Gym pa idantifye.',
      );
    }

    try {
      final res = await Supabase.instance.client.rpc(
        'gym_whatsapp_access_check',
        params: {'p_gym_id': targetGymId},
      );
      if (res != null && res is Map) {
        return WhatsAppAccessCheckResult.fromJson(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      debugPrint('[WhatsApp] Erè verifikasyon rpc gym_whatsapp_access_check: $e');
    }

    // Fallback si offline oswa tab la poko gen antre a
    return const WhatsAppAccessCheckResult(
      hasAccess: true,
      status: 'active',
      daysRemaining: 30,
      message: 'Aksè lokal aktif.',
    );
  }

  /// 1. MESAJ BYENVINI AK ENSKRIPSYON (Welcome / Inscription)
  Future<bool> sendWelcomeMessage({
    required String to,
    required String memberName,
    required String memberNumber,
    required String gymName,
    String? gymPhone,
    String? gymId,
    String languageCode = 'fr',
  }) async {
    final cleanTo = WhatsAppClient.normalizePhone(to);
    if (cleanTo.length < 8) return false;

    final targetGymId = gymId ?? _ref.read(appRuntimeProvider).session?.gymId ?? '';

    // Verifye aksè abònman gym nan
    final access = await checkGymAccess(gymId: targetGymId);
    if (!access.hasAccess) {
      debugPrint('[WhatsApp] Mesaj Byenvini bloke: ${access.message}');
      return false;
    }

    final portalUrl = targetGymId.isNotEmpty
        ? 'https://securgym.com/m/$targetGymId'
        : 'https://securgym.com/espace-membre';

    final effectiveGymPhone = (gymPhone != null && gymPhone.trim().isNotEmpty)
        ? gymPhone.trim()
        : 'gym';

    final message = _buildWelcomeText(
      memberName: memberName,
      memberNumber: memberNumber,
      gymName: gymName,
      gymPhone: effectiveGymPhone,
      portalUrl: portalUrl,
      phone: cleanTo,
      lang: languageCode,
    );

    try {
      final res = await _client.sendMessage(to: cleanTo, message: message);
      if (res.success && targetGymId.isNotEmpty) {
        try {
          await Supabase.instance.client.from('whatsapp_notification_logs').insert({
            'gym_id': targetGymId,
            'kind': 'welcome',
            'recipient_phone': cleanTo,
            'recipient_name': memberName,
            'status': 'sent',
            'metadata': {'portal_url': portalUrl},
          });
        } catch (_) {}
      }
      return res.success;
    } catch (e) {
      debugPrint('[WhatsApp] Echèk voye mesaj byenvini: $e');
      return false;
    }
  }

  /// 2. MESAJ RESI PEMAN OTOMATIK (ak dokiman PDF si disponib)
  Future<bool> sendPaymentReceipt({
    required String to,
    required ReceiptData data,
    Uint8List? pdfBytes,
    String? pdfUrl,
    String? gymPhone,
    String languageCode = 'fr',
  }) async {
    final cleanTo = WhatsAppClient.normalizePhone(to);
    if (cleanTo.length < 8) return false;

    // Verifye aksè abònman gym nan
    final targetGymId = _ref.read(appRuntimeProvider).session?.gymId;
    final access = await checkGymAccess(gymId: targetGymId);
    if (!access.hasAccess) {
      debugPrint('[WhatsApp] Resi bloke: ${access.message}');
      return false;
    }

    final effectiveGymPhone = (gymPhone != null && gymPhone.trim().isNotEmpty)
        ? gymPhone.trim()
        : (data.gymPhone != null && data.gymPhone!.trim().isNotEmpty)
            ? data.gymPhone!.trim()
            : 'gym';

    final message = _buildReceiptText(
      data: data,
      pdfUrl: pdfUrl,
      gymPhone: effectiveGymPhone,
      lang: languageCode,
    );

    String? pdfBase64;
    String? pdfFileName;
    if (pdfBytes != null && pdfBytes.isNotEmpty) {
      pdfBase64 = base64Encode(pdfBytes);
      pdfFileName = 'Recu_${data.receiptNo}.pdf';
    }

    try {
      final res = await _client.sendMessage(
        to: cleanTo,
        message: message,
        pdfBase64: pdfBase64,
        pdfFileName: pdfFileName,
      );
      if (res.success && targetGymId != null && targetGymId.isNotEmpty) {
        try {
          await Supabase.instance.client.from('whatsapp_notification_logs').insert({
            'gym_id': targetGymId,
            'kind': 'receipt',
            'recipient_phone': cleanTo,
            'recipient_name': data.memberName,
            'status': 'sent',
            'metadata': {
              'receipt_no': data.receiptNo,
              'amount': data.amount,
              'plan_name': data.planName,
            },
          });
        } catch (_) {}
      }
      return res.success;
    } catch (e) {
      debugPrint('[WhatsApp] Echèk voye resi peman: $e');
      return false;
    }
  }

  /// 3. RAPÈL FIN ABÒNMAN (7 Jou, 2 Jou, Jou Fini oswa Ekspire)
  Future<bool> sendExpirationReminder({
    required String to,
    required String memberName,
    required String gymName,
    required String planName,
    required DateTime endDate,
    required int daysRemaining,
    String? gymPhone,
    String? gymId,
    String languageCode = 'fr',
  }) async {
    final cleanTo = WhatsAppClient.normalizePhone(to);
    if (cleanTo.length < 8) return false;

    final targetGymId = gymId ?? _ref.read(appRuntimeProvider).session?.gymId ?? '';

    // Verifye aksè abònman gym nan
    final access = await checkGymAccess(gymId: targetGymId);
    if (!access.hasAccess) {
      debugPrint('[WhatsApp] Rapèl bloke: ${access.message}');
      return false;
    }

    final portalUrl = targetGymId.isNotEmpty
        ? 'https://securgym.com/m/$targetGymId'
        : 'https://securgym.com/espace-membre';

    final effectiveGymPhone = (gymPhone != null && gymPhone.trim().isNotEmpty)
        ? gymPhone.trim()
        : 'gym';

    final message = _buildReminderText(
      memberName: memberName,
      gymName: gymName,
      planName: planName,
      endDate: endDate,
      daysRemaining: daysRemaining,
      gymPhone: effectiveGymPhone,
      portalUrl: portalUrl,
      phone: cleanTo,
      lang: languageCode,
    );

    try {
      final res = await _client.sendMessage(to: cleanTo, message: message);
      return res.success;
    } catch (e) {
      debugPrint('[WhatsApp] Echèk voye rapèl abònman: $e');
      return false;
    }
  }

  /// 4. SISTÈM ENTÈLIJAN: TCHEKE AK VOYE RAPÈL OTOMATIK POU TOUT MANM KI NAN 7 JOU, 2 JOU, OUBYEN KI EKSPIRE
  Future<int> checkAndSendPendingExpirationReminders({
    String languageCode = 'fr',
  }) async {
    final runtime = _ref.read(appRuntimeProvider);
    final db = runtime.database;
    final session = runtime.session;
    if (db == null || session == null) return 0;

    final gymId = session.gymId ?? '';

    // Verifye aksè abònman WhatsApp gym nan
    final access = await checkGymAccess(gymId: gymId);
    if (!access.hasAccess) {
      debugPrint('[WhatsApp] Tcheke rapèl bloke: ${access.message}');
      return 0;
    }

    final gym = session.gym ?? const <String, dynamic>{};
    final gymName = gym['name'] as String? ?? 'SecurGYM';
    final gymPhone = gym['phone'] as String? ?? '';

    // Verifye si sèvis WhatsApp la pare
    final state = await _client.checkStatus();
    if (!state.isReady) {
      debugPrint('[WhatsApp] Sèvis la pa READY, rapèl pa ka voye kounye a.');
      return 0;
    }

    int sentCount = 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    try {
      // 1. Chaje manm yo
      final memberRows = await db.watchRecords(SyncEntity.members, limit: 10000).first;
      final Map<String, Map<String, dynamic>> memberMap = {};
      for (final r in memberRows) {
        try {
          final p = jsonDecode(r.payload) as Map<String, dynamic>;
          final id = p['id']?.toString();
          if (id != null) memberMap[id] = p;
        } catch (_) {}
      }

      // 2. Chaje abònman yo
      final subRows = await db.watchRecords(SyncEntity.subscriptions, limit: 10000).first;
      for (final r in subRows) {
        try {
          final p = jsonDecode(r.payload) as Map<String, dynamic>;
          if (p['status'] != 'active') continue;
          final memberId = p['member_id']?.toString();
          if (memberId == null || !memberMap.containsKey(memberId)) continue;

          final member = memberMap[memberId]!;
          final endRaw = p['end_date']?.toString();
          if (endRaw == null) continue;

          final end = DateTime.tryParse(endRaw);
          if (end == null) continue;
          final endDay = DateTime(end.year, end.month, end.day);

          final diffDays = endDay.difference(today).inDays;

          // Etap Entèlijan: 7 jou avan, 2 jou avan, jou fen an (0 jou), oswa fenk fini (-1 jou)
          String? milestoneKind;
          if (diffDays == 7) {
            milestoneKind = 'reminder_7d';
          } else if (diffDays == 2) {
            milestoneKind = 'reminder_2d';
          } else if (diffDays == 0) {
            milestoneKind = 'reminder_0d';
          } else if (diffDays == -1) {
            milestoneKind = 'reminder_expired';
          }

          if (milestoneKind == null) continue;

          final phone = (member['whatsapp']?.toString().isNotEmpty ?? false)
              ? member['whatsapp'].toString()
              : member['phone']?.toString() ?? '';

          if (phone.trim().isEmpty) continue;

          // Anti-doublon lokal
          final cacheKey = '${memberId}_${endDay.toIso8601String()}_$milestoneKind';
          if (_sentReminderKeys.contains(cacheKey)) continue;

          // Anti-doublon Supabase nan whatsapp_notification_logs
          try {
            final logs = await Supabase.instance.client
                .from('whatsapp_notification_logs')
                .select('id')
                .eq('member_id', memberId)
                .eq('kind', milestoneKind)
                .gte('created_at', now.subtract(const Duration(days: 3)).toIso8601String())
                .limit(1);
            if (logs.isNotEmpty) {
              _sentReminderKeys.add(cacheKey);
              continue; // Te deja voye nan dènye 3 jou yo
            }
          } catch (_) {}

          final memberName = '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim();
          final planName = p['plan_name']?.toString() ?? 'Abonnement Gym';

          final ok = await sendExpirationReminder(
            to: phone,
            memberName: memberName,
            gymName: gymName,
            planName: planName,
            endDate: endDay,
            daysRemaining: diffDays,
            gymPhone: gymPhone,
            gymId: gymId,
            languageCode: languageCode,
          );

          if (ok) {
            _sentReminderKeys.add(cacheKey);
            sentCount++;

            // Enskri nan journal Supabase
            try {
              await Supabase.instance.client.from('whatsapp_notification_logs').insert({
                'gym_id': gymId,
                'member_id': memberId,
                'kind': milestoneKind,
                'recipient_phone': WhatsAppClient.normalizePhone(phone),
                'recipient_name': memberName,
                'status': 'sent',
                'metadata': {
                  'days_remaining': diffDays,
                  'plan_name': planName,
                  'end_date': endDay.toIso8601String(),
                  'auto': true,
                },
              });
            } catch (_) {}

            // Delè sekirite anti-spam ant rapèl yo (2.5 segonn)
            await Future<void>.delayed(const Duration(milliseconds: 2500));
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[WhatsApp] Erè pandan tcheke rapèl: $e');
    }

    return sentCount;
  }

  /// 5. FOOTER OBLIGATWA POU KANPAY WHATSAPP (Gen Non Gym nan, Kontak li, ak Lyen SecurGYM)
  static String buildCampaignFooter({
    required String gymName,
    required String gymPhone,
    String lang = 'fr',
    String securgymUrl = 'https://securgym.com',
  }) {
    final effectiveGym = gymName.trim().isNotEmpty ? gymName.trim() : 'Gym';
    final effectivePhone = gymPhone.trim().isNotEmpty ? gymPhone.trim() : 'gym';
    if (lang == 'fr') {
      return '\n\n────────────────────────\n'
          '🏢 *$effectiveGym*\n'
          'ℹ️ Message envoyé via le système *SecurGYM* ($securgymUrl).\n'
          '📌 Veuillez *enregistrer ce numéro* sous le nom *SecurGYM* dans vos contacts pour activer les liens.\n'
          '📞 *Ne répondez pas à ce message*. Pour toute question, contactez directement *$effectiveGym* au : *$effectivePhone*.';
    } else if (lang == 'en') {
      return '\n\n────────────────────────\n'
          '🏢 *$effectiveGym*\n'
          'ℹ️ Message sent via *SecurGYM* system ($securgymUrl).\n'
          '📌 Please *save this number* as *SecurGYM* in your contacts to enable clickable links.\n'
          '📞 *Do not reply to this message*. For any questions, contact *$effectiveGym* directly at: *$effectivePhone*.';
    }
    return '\n\n────────────────────────\n'
        '🏢 *$effectiveGym*\n'
        'ℹ️ Mesaj voye depi sistèm *SecurGYM* ($securgymUrl).\n'
        '📌 Tanpri *anrejistre nimewo sa a* nan kontak ou sou non *SecurGYM* pou w ka klike sou lyen yo.\n'
        '📞 *Pa reponn sou nimewo sa a*. Pou nenpòt kesyon, kontakte *$effectiveGym* dirèkteman nan: *$effectivePhone*.';
  }

  // --- MODÈL TÈKS (FR, HT, EN) ---

  String _buildWelcomeText({
    required String memberName,
    required String memberNumber,
    required String gymName,
    required String gymPhone,
    required String portalUrl,
    required String phone,
    required String lang,
  }) {
    if (lang == 'fr') {
      return '🏋️ *Bienvenue chez $gymName !*\n'
          '_Système SecurGYM • https://securgym.com_\n\n'
          'Bonjour *$memberName*,\n'
          'Votre inscription a été validée avec succès (N° Membre : *$memberNumber*).\n\n'
          '📱 *Votre Espace Membre en Ligne :*\n'
          '👉 $portalUrl\n'
          '_Connectez-vous simplement avec votre numéro :_ *$phone*\n\n'
          'Dans votre espace, vous pouvez consulter votre formule et soumettre vos demandes de renouvellement à tout moment.\n\n'
          '────────────────────────\n'
          '⚠️ *IMPORTANT :*\n'
          '1. Veuillez *enregistrer ce numéro* sous le nom *SecurGYM* dans vos contacts pour activer les liens et recevoir vos rappels.\n'
          '2. *Ne répondez pas à ce numéro*. Pour toute question ou assistance, contactez directement l\'accueil de *$gymName* au : *$gymPhone*.';
    } else if (lang == 'en') {
      return '🏋️ *Welcome to $gymName!*\n'
          '_SecurGYM System • https://securgym.com_\n\n'
          'Hello *$memberName*,\n'
          'Your membership registration has been approved (Member ID: *$memberNumber*).\n\n'
          '📱 *Your Online Member Portal:*\n'
          '👉 $portalUrl\n'
          '_Log in using your phone number:_ *$phone*\n\n'
          'From your portal, you can view your plan status and submit renewal requests anytime.\n\n'
          '────────────────────────\n'
          '⚠️ *IMPORTANT:*\n'
          '1. Please *save this number* as *SecurGYM* in your contacts to enable clickable links and updates.\n'
          '2. *Do not reply to this number*. For any questions or support, contact *$gymName* directly at: *$gymPhone*.';
    }

    // Haitian Creole
    return '🏋️ *Byenvini nan $gymName !*\n'
        '_Sistèm SecurGYM • https://securgym.com_\n\n'
        'Bonjou *$memberName*,\n'
        'Enskripsyon w lan valide avèk siksè (N° Manm : *$memberNumber*).\n\n'
        '📱 *Espas Manm Ou sou Entènèt :*\n'
        '👉 $portalUrl\n'
        '_Konekte fasilman ak nimewo telefòn ou :_ *$phone*\n\n'
        'Nan espas sa a, w ap ka wè tout detay sou abònman w, epi fè demand renouvèlman dirèkteman.\n\n'
        '────────────────────────\n'
        '⚠️ *ENPÒTAN :*\n'
        '1. Li *obligatwa pou w anrejistre nimewo sa a* nan kontak ou sou non *SecurGYM* pou w ka klike sou lyen yo.\n'
        '2. *Pa reponn sou nimewo sa a*. Pou nenpòt kesyon oswa asistans, kontakte resepsyon *$gymName* nan: *$gymPhone*.';
  }

  String _buildReceiptText({
    required ReceiptData data,
    String? pdfUrl,
    required String gymPhone,
    required String lang,
  }) {
    final day = DateFormat('dd/MM/yyyy');
    final period = (data.periodStart != null && data.periodEnd != null)
        ? '${day.format(data.periodStart!)} → ${day.format(data.periodEnd!)}'
        : null;

    final linkSection = (pdfUrl != null && pdfUrl.isNotEmpty)
        ? '\n\n📄 *Télécharger votre reçu complet :*\n👉 $pdfUrl'
        : '';

    if (lang == 'fr') {
      return '🧾 *${data.gymName}* · _Système SecurGYM • https://securgym.com_\n'
          '*Reçu de Paiement #${data.receiptNo}* - Confirmé ✅\n\n'
          'Bonjour *${data.memberName}* (${data.memberNumber}),\n'
          'Nous vous confirmons la bonne réception de votre paiement :\n\n'
          '• Formule : *${data.planName}*\n'
          '• Montant : *${data.amount.toStringAsFixed(2)} ${data.currency}*\n'
          '${period != null ? "• Période : *$period*\n" : ""}'
          '$linkSection\n'
          '────────────────────────\n'
          '⚠️ *IMPORTANT :*\n'
          '1. Veuillez enregistrer ce numéro sous le nom *SecurGYM* dans vos contacts.\n'
          '2. *Ne répondez pas à ce message*. Contactez l\'accueil de *${data.gymName}* au : *$gymPhone*.';
    } else if (lang == 'en') {
      return '🧾 *${data.gymName}* · _SecurGYM System • https://securgym.com_\n'
          '*Payment Receipt #${data.receiptNo}* - Confirmed ✅\n\n'
          'Hello *${data.memberName}* (${data.memberNumber}),\n'
          'We have successfully received your payment:\n\n'
          '• Plan: *${data.planName}*\n'
          '• Amount: *${data.amount.toStringAsFixed(2)} ${data.currency}*\n'
          '${period != null ? "• Period: *$period*\n" : ""}'
          '$linkSection\n'
          '────────────────────────\n'
          '⚠️ *IMPORTANT:*\n'
          '1. Please save this number as *SecurGYM* in your contacts.\n'
          '2. *Do not reply to this message*. Contact *${data.gymName}* directly at: *$gymPhone*.';
    }

    // Haitian Creole
    return '🧾 *${data.gymName}* · _Sistèm SecurGYM • https://securgym.com_\n'
        '*Resi Peman #${data.receiptNo}* - Konfime ✅\n\n'
        'Bonjou *${data.memberName}* (${data.memberNumber}),\n'
        'Nou byen resevwa peman w lan :\n\n'
        '• Fòmil : *${data.planName}*\n'
        '• Montan : *${data.amount.toStringAsFixed(2)} ${data.currency}*\n'
        '${period != null ? "• Validite : *$period*\n" : ""}'
        '$linkSection\n'
        '────────────────────────\n'
        '⚠️ *ENPÒTAN :*\n'
        '1. Tanpri anrejistre nimewo sa a nan kontak ou sou non *SecurGYM*.\n'
        '2. *Pa reponn sou nimewo sa a*. Kontakte *${data.gymName}* dirèkteman nan: *$gymPhone*.';
  }

  String _buildReminderText({
    required String memberName,
    required String gymName,
    required String planName,
    required DateTime endDate,
    required int daysRemaining,
    required String gymPhone,
    required String portalUrl,
    required String phone,
    required String lang,
  }) {
    final day = DateFormat('dd/MM/yyyy');
    final formattedDate = day.format(endDate);

    if (lang == 'fr') {
      String headline;
      String bodyLine;
      if (daysRemaining == 7) {
        headline = '⏳ *Rappel Fin d\'Abonnement (7 jours) - $gymName*';
        bodyLine = 'Votre formule (*$planName*) arrive à expiration dans 7 jours (*$formattedDate*).';
      } else if (daysRemaining == 2) {
        headline = '⚠️ *Rappel Urgent : Fin d\'Abonnement dans 2 Jours - $gymName*';
        bodyLine = 'Votre formule (*$planName*) expire dans seulement 2 jours (*$formattedDate*).';
      } else if (daysRemaining == 0) {
        headline = '🚨 *Dernier Jour d\'Abonnement - $gymName*';
        bodyLine = 'Votre formule (*$planName*) expire aujourd\'hui même (*$formattedDate*).';
      } else {
        headline = '🔒 *Abonnement Expiré - $gymName*';
        bodyLine = 'Votre formule (*$planName*) a expiré le *$formattedDate*. Votre accès biométrique est suspendu.';
      }

      return '$headline\n'
          '_Système SecurGYM • https://securgym.com_\n\n'
          'Bonjour *$memberName*,\n'
          '$bodyLine\n\n'
          'Pour conserver votre accès empreinte aux portes sans interruption :\n'
          '1. Passez à l\'accueil de *$gymName* pour renouveler votre formule.\n'
          '2. Ou faites votre demande de renouvellement en ligne :\n'
          '👉 $portalUrl\n'
          '_Connectez-vous avec votre numéro :_ *$phone*\n\n'
          '────────────────────────\n'
          '⚠️ *IMPORTANT :*\n'
          '1. Veuillez enregistrer ce numéro sous le nom *SecurGYM* dans vos contacts.\n'
          '2. *Ne répondez pas à ce numéro*. Contactez la salle directement au : *$gymPhone*.';
    } else if (lang == 'en') {
      String headline;
      String bodyLine;
      if (daysRemaining == 7) {
        headline = '⏳ *Membership Expiration Reminder (7 days) - $gymName*';
        bodyLine = 'Your membership (*$planName*) expires in 7 days (*$formattedDate*).';
      } else if (daysRemaining == 2) {
        headline = '⚠️ *Urgent Reminder: Expiring in 2 Days - $gymName*';
        bodyLine = 'Your membership (*$planName*) expires in just 2 days (*$formattedDate*).';
      } else if (daysRemaining == 0) {
        headline = '🚨 *Final Day of Membership - $gymName*';
        bodyLine = 'Your membership (*$planName*) expires today (*$formattedDate*).';
      } else {
        headline = '🔒 *Membership Expired - $gymName*';
        bodyLine = 'Your membership (*$planName*) expired on *$formattedDate*. Door access is currently suspended.';
      }

      return '$headline\n'
          '_SecurGYM System • https://securgym.com_\n\n'
          'Hello *$memberName*,\n'
          '$bodyLine\n\n'
          'To keep your biometric door access without interruption:\n'
          '1. Visit *$gymName* reception to renew.\n'
          '2. Or submit your renewal request online:\n'
          '👉 $portalUrl\n'
          '_Log in with your phone number:_ *$phone*\n\n'
          '────────────────────────\n'
          '⚠️ *IMPORTANT:*\n'
          '1. Please save this number as *SecurGYM* in your contacts.\n'
          '2. *Do not reply to this number*. Contact the gym directly at: *$gymPhone*.';
    }

    // Haitian Creole
    String headline;
    String bodyLine;
    if (daysRemaining == 7) {
      headline = '⏳ *Rapèl Fin Abònman (7 Jou) - $gymName*';
      bodyLine = 'Abònman w lan (*$planName*) ap fini nan 7 jou (*$formattedDate*).';
    } else if (daysRemaining == 2) {
      headline = '⚠️ *Rapèl Enpòtan : Abònman w fini nan 2 Jou - $gymName*';
      bodyLine = 'Abònman w lan (*$planName*) ap fini nan sèlman 2 jou (*$formattedDate*).';
    } else if (daysRemaining == 0) {
      headline = '🚨 *Dènye Jou Abònman - $gymName*';
      bodyLine = 'Abònman w lan (*$planName*) ap fini jodi a menm (*$formattedDate*).';
    } else {
      headline = '🔒 *Abònman Ekspire - $gymName*';
      bodyLine = 'Abònman w lan (*$planName*) te fini nan dat *$formattedDate*. Aksè anprent ou bloke kounye a.';
    }

    return '$headline\n'
        '_Sistèm SecurGYM • https://securgym.com_\n\n'
        'Bonjou *$memberName*,\n'
        '$bodyLine\n\n'
        'Pou w pa pèdi aksè anprent ou devan pòt la epi pou w kontinye antrene san rete :\n'
        '1. Pase nan resepsyon *$gymName* pou w renouvle l.\n'
        '2. Oswa fè demand renouvèlman an sou espas manm ou :\n'
        '👉 $portalUrl\n'
        '_Konekte ak nimewo telefòn ou :_ *$phone*\n\n'
        '────────────────────────\n'
        '⚠️ *ENPÒTAN :*\n'
        '1. Tanpri anrejistre nimewo sa a nan kontak ou sou non *SecurGYM*.\n'
        '2. *Pa reponn sou nimewo sa a*. Kontakte *$gymName* dirèkteman nan: *$gymPhone*.';
  }
}

/// Provider pou sèvis notifikasyon WhatsApp la (Kenbe aktif pou background automation)
final whatsAppNotificationServiceProvider = Provider<WhatsAppNotificationService>((ref) {
  final client = ref.watch(whatsAppClientProvider);
  final service = WhatsAppNotificationService(client, ref);
  ref.onDispose(service.stopAutomatedBackgroundChecker);
  return service;
});
