import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
/// 4. Voye rapèl abònman otomatik 7 jou anvan li fini
/// 5. Asire tout mesaj gen nòt obligatwa pou anrejistre nimewo a sou non "SecurGYM"
///    epi bay nimewo telefòn ofisyèl gym lan pou yo ka reponn olye yo reponn sou bot la.
class WhatsAppNotificationService {
  WhatsAppNotificationService(this._client, this._ref);

  final WhatsAppClient _client;
  final Ref _ref;

  // Cache pou evite voye menm rapèl la 2 fwa nan menm jounen an
  static final Set<String> _sentReminderKeys = {};

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
    String languageCode = 'ht',
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
    String languageCode = 'ht',
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
      return res.success;
    } catch (e) {
      debugPrint('[WhatsApp] Echèk voye resi peman: $e');
      return false;
    }
  }

  /// 3. RAPÈL FIN ABÒNMAN (7 Jou Avan oswa Jou Finisman)
  Future<bool> sendExpirationReminder({
    required String to,
    required String memberName,
    required String gymName,
    required String planName,
    required DateTime endDate,
    required int daysRemaining,
    String? gymPhone,
    String? gymId,
    String languageCode = 'ht',
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

  /// 4. TCHEKE AK VOYE RAPÈL 7 JOU OTOMATIK POU TOUT MANM KI PRAL EKSPIRE
  Future<int> checkAndSendPendingExpirationReminders({
    int daysBefore = 7,
    String languageCode = 'ht',
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
          // Voye si li nan fenèt la (egz: egzakteman 7 jou, oswa 1 jou, oswa jodi a)
          if (diffDays == daysBefore || diffDays == 1 || diffDays == 0) {
            final phone = (member['whatsapp']?.toString().isNotEmpty ?? false)
                ? member['whatsapp'].toString()
                : member['phone']?.toString() ?? '';

            if (phone.trim().isEmpty) continue;

            final cacheKey = '${memberId}_${endDay.toIso8601String()}_$diffDays';
            if (_sentReminderKeys.contains(cacheKey)) continue;

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
              // Delè sekirite anti-spam ant rapèl yo
              await Future<void>.delayed(const Duration(milliseconds: 1500));
            }
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
    String lang = 'ht',
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

  // --- MODEL TEKS (HT, FR, EN) ---

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
    final period = (data.startDate != null && data.endDate != null)
        ? '${day.format(data.startDate!)} → ${day.format(data.endDate!)}'
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
      final daysText = daysRemaining == 0
          ? "aujourd'hui"
          : daysRemaining == 1
              ? 'demain'
              : 'dans $daysRemaining jours';

      return '⏳ *Rappel Fin d\'Abonnement - $gymName*\n'
          '_Système SecurGYM • https://securgym.com_\n\n'
          'Bonjour *$memberName*,\n'
          'Votre formule (*$planName*) arrive à expiration $daysText (*$formattedDate*).\n\n'
          'Pour conserver votre accès empreinte aux portes sans interruption :\n'
          '1. Passez à l\'accueil de *$gymName* pour renouveler votre pass.\n'
          '2. Ou faites votre demande de renouvellement en ligne :\n'
          '👉 $portalUrl\n'
          '_Connectez-vous avec votre numéro :_ *$phone*\n\n'
          '────────────────────────\n'
          '⚠️ *IMPORTANT :*\n'
          '1. Veuillez enregistrer ce numéro sous le nom *SecurGYM*.\n'
          '2. *Ne répondez pas à ce numéro*. Contactez la salle directement au : *$gymPhone*.';
    } else if (lang == 'en') {
      final daysText = daysRemaining == 0
          ? 'today'
          : daysRemaining == 1
              ? 'tomorrow'
              : 'in $daysRemaining days';

      return '⏳ *Membership Expiration Reminder - $gymName*\n'
          '_SecurGYM System • https://securgym.com_\n\n'
          'Hello *$memberName*,\n'
          'Your membership (*$planName*) will expire $daysText (*$formattedDate*).\n\n'
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
    final daysText = daysRemaining == 0
        ? 'jodi a menm'
        : daysRemaining == 1
            ? 'demen'
            : 'nan $daysRemaining jou';

    return '⏳ *Rapèl Fin Abònman - $gymName*\n'
        '_Sistèm SecurGYM • https://securgym.com_\n\n'
        'Bonjou *$memberName*,\n'
        'Abònman w lan (*$planName*) ap fini $daysText (*$formattedDate*).\n\n'
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

/// Provider pou sèvis notifikasyon WhatsApp la
final whatsAppNotificationServiceProvider = Provider<WhatsAppNotificationService>((ref) {
  final client = ref.watch(whatsAppClientProvider);
  return WhatsAppNotificationService(client, ref);
});
