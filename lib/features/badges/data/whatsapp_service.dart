import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../members/domain/member.dart';
import '../../settings/domain/gym_settings.dart';
import '../domain/badge.dart';

class WhatsAppService {
  /// Netwaye epi fòmate yon nimewo pou WhatsApp (Ayiti 509 pa defo si pa gen kòd peyi)
  static String formatPhoneNumber(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('00')) {
      cleaned = cleaned.substring(2);
    }
    // Si nimewo an gen 8 chif (egz: 37123456 oswa 48123456 an Ayiti)
    if (cleaned.length == 8) {
      cleaned = '509$cleaned';
    }
    // Si li kòmanse ak 0, retire 0 an
    if (cleaned.startsWith('0') && cleaned.length == 9) {
      cleaned = '509${cleaned.substring(1)}';
    }
    return cleaned;
  }

  /// Voye mesaj aktivasyon badj konplè sou WhatsApp
  static Future<bool> sendBadgeActivation({
    required BuildContext context,
    required Member member,
    required BadgeItem badge,
    required GymSettings gym,
    String? planName,
    DateTime? endDate,
  }) async {
    final phone = _resolvePhone(member);
    if (phone.isEmpty) {
      final updatedPhone = await promptWhatsAppNumber(context, member);
      if (updatedPhone == null || updatedPhone.isEmpty) return false;
      return _launchWhatsApp(
        updatedPhone,
        buildBadgeActivationMessage(
          gym: gym,
          member: member,
          badge: badge,
          planName: planName,
          endDate: endDate,
        ),
      );
    }

    return _launchWhatsApp(
      phone,
      buildBadgeActivationMessage(
        gym: gym,
        member: member,
        badge: badge,
        planName: planName,
        endDate: endDate,
      ),
    );
  }

  /// Voye rapèl ekspirasyon abònman sou WhatsApp
  static Future<bool> sendSubscriptionReminder({
    required BuildContext context,
    required Member member,
    required GymSettings gym,
    required String planName,
    required DateTime endDate,
    int? daysRemaining,
  }) async {
    final phone = _resolvePhone(member);
    if (phone.isEmpty) {
      final updatedPhone = await promptWhatsAppNumber(context, member);
      if (updatedPhone == null || updatedPhone.isEmpty) return false;
      return _launchWhatsApp(
        updatedPhone,
        buildExpirationReminderMessage(
          gym: gym,
          member: member,
          planName: planName,
          endDate: endDate,
          daysRemaining: daysRemaining,
        ),
      );
    }

    return _launchWhatsApp(
      phone,
      buildExpirationReminderMessage(
        gym: gym,
        member: member,
        planName: planName,
        endDate: endDate,
        daysRemaining: daysRemaining,
      ),
    );
  }

  static String _resolvePhone(Member member) {
    final wa = member.whatsapp?.trim() ?? '';
    if (wa.isNotEmpty) return wa;
    final ph = member.phone?.trim() ?? '';
    if (ph.isNotEmpty) return ph;
    return '';
  }

  static String buildBadgeActivationMessage({
    required GymSettings gym,
    required Member member,
    required BadgeItem badge,
    String? planName,
    DateTime? endDate,
  }) {
    final endStr = endDate != null
        ? DateFormat('dd/MM/yyyy').format(endDate.toLocal())
        : 'Aktif';

    return '''
🏋️ *${gym.name.toUpperCase()}* — KAT AKSÈ OFISYÈL

Bonjou *${member.fullName}*,

Nou kontan konfime ke kat aksè ou a byen aktive avèk siksè nan sal nou an !

📋 *Enfòmasyon sou Kont ou :*
• *Manb :* ${member.fullName}
• *Nimewo Manb :* ${member.memberNumber}
• *Nimewo Badj :* ${badge.formattedNumber}
• *Plan :* ${planName ?? 'Abònman Gym'}
• *Dat Ekspirasyon :* $endStr
• *Statut :* Aktif ✅

🔐 *Kòd Aksè Sekirize (PIN) :*
Tanpri prezante kat fizik ou oswa kòd QR ou devan eskanè a nan antre a, epi tape kòd PIN ou. Si w ta bliye PIN ou, pase nan resepsyon an avèk yon pyès idantite.

📞 *Kontak Gym :* ${gym.phone.isNotEmpty ? gym.phone : 'Resepsyon'}
📍 *Adrès :* ${gym.address.isNotEmpty ? gym.address : 'Sal GymDesk'}

Mèsi dèske w fè nou konfyans ! Antrenman an kòmanse kounye a ! 💪🔥
''';
  }

  static String buildExpirationReminderMessage({
    required GymSettings gym,
    required Member member,
    required String planName,
    required DateTime endDate,
    int? daysRemaining,
  }) {
    final endStr = DateFormat('dd/MM/yyyy').format(endDate.toLocal());
    final statusNotice = (daysRemaining != null && daysRemaining <= 0)
        ? '⚠️ *Abònman ou a ekspire jodi a !*'
        : '⏳ *Abònman ou an ap fini nan ${daysRemaining ?? 3} jou ($endStr) !*';

    return '''
🏋️ *${gym.name.toUpperCase()}* — RAPÈL ABÒNMAN

Bonjou *${member.fullName}*,

$statusNotice

📋 *Detay sou Abònman an :*
• *Nimewo Manb :* ${member.memberNumber}
• *Plan Aktyèl :* $planName
• *Dat Fen :* $endStr

Pou evite okenn entèripsyon nan aksè ou nan sal la, tanpri pase nan resepsyon an pou w renouvle abònman ou anvan dat limit la.

📞 *Kontak Gym :* ${gym.phone.isNotEmpty ? gym.phone : 'Resepsyon'}
Mèsi pou fidelite w ! 💪⚡
''';
  }

  static Future<bool> _launchWhatsApp(String rawPhone, String message) async {
    final clean = formatPhoneNumber(rawPhone);
    final encoded = Uri.encodeComponent(message.trim());
    final url = Uri.parse('https://wa.me/$clean?text=$encoded');
    try {
      if (await canLaunchUrl(url)) {
        return await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        return await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      return false;
    }
  }

  /// Modal pou antre nimewo WhatsApp si manb lan pa genyen
  static Future<String?> promptWhatsAppNumber(
    BuildContext context,
    Member member,
  ) async {
    final controller = TextEditingController(
      text: (member.phone != null && member.phone!.isNotEmpty) ? member.phone! : '',
    );
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.messageSquare, color: Color(0xff25D366)),
            SizedBox(width: 10),
            Text('Nimewo WhatsApp Manb lan'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Antre nimewo WhatsApp pou ${member.fullName} pou w ka voye detay badj la ba li :',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nimewo WhatsApp',
                  hintText: '509 3412 3456',
                  prefixIcon: Icon(LucideIcons.phone),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().length < 8)
                    ? 'Antre yon nimewo valab (omwen 8 chif)'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anile'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff25D366),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            icon: const Icon(LucideIcons.send, size: 16),
            label: const Text('Voye sou WhatsApp'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      return controller.text.trim();
    }
    return null;
  }
}
