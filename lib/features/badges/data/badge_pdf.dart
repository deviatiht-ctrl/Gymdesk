import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../settings/domain/gym_settings.dart';
import '../domain/badge.dart';

PdfColor _pdfColor(String raw) {
  final value = int.tryParse(raw.replaceFirst('#', ''), radix: 16);
  return value == null ? PdfColor.fromHex('#1F6F4A') : PdfColor.fromInt(0xff000000 | value);
}

/// Construction du recto du badge V2 (Anonyme : Grand QR >=32mm, Numéro, Logo, Nom, Tél)
pw.Widget buildV2BadgeRecto({
  required BadgeItem badge,
  required GymSettings gym,
  Uint8List? logo,
  required double width,
  required double height,
  bool withBorder = true,
}) {
  final accent = _pdfColor(gym.accentColor);
  return pw.Container(
    width: width,
    height: height,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      border: withBorder ? pw.Border.all(color: PdfColors.grey300, width: 0.8) : null,
      borderRadius: withBorder ? const pw.BorderRadius.all(pw.Radius.circular(6)) : null,
    ),
    child: pw.Row(
      children: [
        // Colonne de gauche : Logo, Nom de la salle, Numéro de membre, Tél
        pw.Expanded(
          flex: 5,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Haut : Logo + Nom de salle
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logo != null)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 6),
                      child: pw.Image(pw.MemoryImage(logo), width: 22, height: 22, fit: pw.BoxFit.contain),
                    ),
                  pw.Expanded(
                    child: pw.Text(
                      gym.name.toUpperCase(),
                      maxLines: 2,
                      style: pw.TextStyle(
                        color: PdfColors.grey900,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              // Milieu : Grand numéro de membre (MEMBRE 01)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    height: 2,
                    width: 32,
                    color: accent,
                    margin: const pw.EdgeInsets.only(bottom: 6),
                  ),
                  pw.Text(
                    badge.formattedNumber,
                    style: pw.TextStyle(
                      color: accent,
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'CARTE D\'ACCÈS OFFICIELLE',
                    style: pw.TextStyle(
                      color: PdfColors.grey600,
                      fontSize: 6,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // Bas : Téléphone de la salle
              pw.Text(
                gym.phone.isNotEmpty ? gym.phone : 'GYMDESK',
                style: pw.TextStyle(
                  color: PdfColors.grey700,
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 8),
        // Colonne de droite : Grand QR Code (>= 32mm)
        pw.Expanded(
          flex: 4,
          child: pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: accent, width: 1.2),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.high),
                data: badge.qrPayload(gym.code),
                width: 33 * PdfPageFormat.mm,
                height: 33 * PdfPageFormat.mm,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Construction du verso du badge V2 (Consignes, PIN obligatoire, Perte)
pw.Widget buildV2BadgeVerso({
  required GymSettings gym,
  required double width,
  required double height,
  bool withBorder = true,
}) {
  final accent = _pdfColor(gym.accentColor);
  return pw.Container(
    width: width,
    height: height,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      border: withBorder ? pw.Border.all(color: PdfColors.grey300, width: 0.8) : null,
      borderRadius: withBorder ? const pw.BorderRadius.all(pw.Radius.circular(6)) : null,
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        // Avertissement PIN
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            border: pw.Border.all(color: accent, width: 0.5),
          ),
          child: pw.Text(
            'CARTE PERSONNELLE — CODE PIN EXIGÉ À L\'ENTRÉE',
            style: pw.TextStyle(
              color: accent,
              fontSize: 6.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        // Instructions
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '• Présentez cette carte au scanner puis saisissez votre code PIN.',
              style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '• Cette carte est strictement personnelle et incessible.',
              style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '• En cas de perte ou d\'oubli de PIN, présentez-vous à la réception avec une pièce d\'identité.',
              style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey800),
            ),
          ],
        ),
        // Coordonnées de la salle
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (gym.address.isNotEmpty)
              pw.Text(
                gym.address,
                style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
              ),
            pw.Text(
              'Tél : ${gym.phone.isNotEmpty ? gym.phone : "Réception"}',
              style: pw.TextStyle(fontSize: 6, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ],
    ),
  );
}

/// PDF d'impression unitaire ou par lot (1 carte par page, format CR80 85.6 x 54 mm, option fond perdu 3mm)
Future<Uint8List> buildV2BadgeCardsPdf({
  required List<BadgeItem> badges,
  required GymSettings gym,
  Uint8List? logo,
  bool withBleed = false,
}) async {
  final document = pw.Document();
  final cardWidth = (85.6 + (withBleed ? 6 : 0)) * PdfPageFormat.mm;
  final cardHeight = (54.0 + (withBleed ? 6 : 0)) * PdfPageFormat.mm;
  final pageFormat = PdfPageFormat(cardWidth, cardHeight);

  for (final badge in badges) {
    // Recto
    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (context) => buildV2BadgeRecto(
          badge: badge,
          gym: gym,
          logo: logo,
          width: cardWidth,
          height: cardHeight,
          withBorder: !withBleed,
        ),
      ),
    );
    // Verso
    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (context) => buildV2BadgeVerso(
          gym: gym,
          width: cardWidth,
          height: cardHeight,
          withBorder: !withBleed,
        ),
      ),
    );
  }

  return document.save();
}

/// Mode Planche A4 (8 à 10 cartes par feuille avec traits de coupe)
Future<Uint8List> buildV2BatchPlanchePdf({
  required List<BadgeItem> badges,
  required GymSettings gym,
  Uint8List? logo,
}) async {
  final document = pw.Document();
  const cardW = 85.6 * PdfPageFormat.mm;
  const cardH = 54.0 * PdfPageFormat.mm;

  // 8 cartes par page (2 colonnes x 4 rangées)
  const perPage = 8;
  for (var i = 0; i < badges.length; i += perPage) {
    final pageBadges = badges.skip(i).take(perPage).toList();

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(15 * PdfPageFormat.mm),
        build: (context) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
          children: [
            pw.Text(
              '${gym.name.toUpperCase()} — Planche de Badges (${pageBadges.first.formattedNumber} à ${pageBadges.last.formattedNumber})',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 6),
            pw.Wrap(
              spacing: 8 * PdfPageFormat.mm,
              runSpacing: 6 * PdfPageFormat.mm,
              children: [
                for (final badge in pageBadges)
                  pw.Container(
                    width: cardW,
                    height: cardH,
                    child: buildV2BadgeRecto(
                      badge: badge,
                      gym: gym,
                      logo: logo,
                      width: cardW,
                      height: cardH,
                      withBorder: true,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  return document.save();
}
