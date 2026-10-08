import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../settings/domain/gym_settings.dart';
import '../domain/badge.dart';

/// Aperçu recto du badge anonyme V2 (CR80 paysage) :
/// logo + nom de la salle, grand QR, numéro MEMBRE, téléphone.
/// Aucun nom ni photo de membre.
class BadgeCard extends StatelessWidget {
  const BadgeCard({
    super.key,
    required this.badge,
    required this.gym,
    this.logo,
    this.showBack = false,
  });

  final BadgeItem badge;
  final GymSettings gym;
  final Uint8List? logo;
  final bool showBack;

  Color get _accent {
    final value = int.tryParse(
      gym.accentColor.replaceFirst('#', ''),
      radix: 16,
    );
    return value == null ? const Color(0xff1f6f4a) : Color(0xff000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return AspectRatio(
      aspectRatio: 85.6 / 54,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffd9e2dd)),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(14),
        child: showBack ? _verso(accent) : _recto(accent),
      ),
    );
  }

  Widget _recto(Color accent) => Row(
    children: [
      Expanded(
        flex: 5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (logo != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Image.memory(
                      logo!,
                      width: 30,
                      height: 30,
                      fit: BoxFit.contain,
                    ),
                  ),
                Expanded(
                  child: Text(
                    gym.name.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 0.4,
                      color: Color(0xff1c2420),
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 36, height: 3, color: accent),
                const SizedBox(height: 8),
                Text(
                  badge.formattedNumber,
                  style: TextStyle(
                    color: accent,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            Text(
              gym.phone.isNotEmpty ? gym.phone : 'GYMDESK',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xff4a5550),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        flex: 4,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              border: Border.all(color: accent, width: 1.4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: QrImageView(
              data: badge.qrPayload(gym.code),
              version: QrVersions.auto,
              errorCorrectionLevel: QrErrorCorrectLevel.Q,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _verso(Color accent) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xfff2f5f3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accent, width: 0.6),
        ),
        child: Text(
          'CARTE PERSONNELLE — CODE PIN EXIGÉ À L\'ENTRÉE',
          style: TextStyle(
            color: accent,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const Text(
        'En cas de perte ou d\'oubli du code PIN, présentez-vous '
        'à la réception avec une pièce d\'identité.',
        style: TextStyle(fontSize: 9.5, color: Color(0xff3a4440)),
      ),
      Text(
        [
          if (gym.address.isNotEmpty) gym.address,
          if (gym.phone.isNotEmpty) 'Tél : ${gym.phone}',
        ].join(' · '),
        style: const TextStyle(fontSize: 9, color: Color(0xff4a5550)),
      ),
    ],
  );
}
