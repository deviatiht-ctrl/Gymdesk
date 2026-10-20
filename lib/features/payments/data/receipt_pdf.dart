import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/sync/sync_models.dart';
import '../../members/domain/member.dart';
import '../domain/payment.dart';

/// Tout done resi a — konplete anvan yo jenere PDF la.
class ReceiptData {
  const ReceiptData({
    required this.paymentId,
    required this.memberName,
    required this.memberNumber,
    required this.planName,
    required this.amount,
    required this.currency,
    required this.method,
    required this.paidAt,
    required this.gymName,
    required this.accentColor,
    this.periodStart,
    this.periodEnd,
    this.receivedAmount,
    this.creditUsed = 0,
    this.creditAdded = 0,
    this.creditBalance = 0,
    this.memberEmail,
    this.memberPhone,
    this.gymAddress,
    this.gymPhone,
    this.gymEmail,
    this.logoBytes,
    this.qrPromoBytes,
    this.reference,
    this.paidCurrency,
    this.exchangeRate,
    this.paidAmount,
    this.tenderedAmount,
    this.cashierName,
  });

  /// Reçu reconstruit depuis un paiement enregistré (historique, page Reçus).
  factory ReceiptData.fromPayment({
    required GymPayment payment,
    required Member member,
    required Json gym,
    String? planName,
    DateTime? periodStart,
    DateTime? periodEnd,
    String? cashierName,
  }) => ReceiptData(
    paymentId: payment.id,
    memberName: member.fullName,
    memberNumber: member.memberNumber,
    planName: planName ?? 'Abonnement',
    amount: payment.amount,
    currency: payment.currency,
    method: payment.method,
    paidAt: payment.paidAt,
    gymName: gym['name'] as String? ?? 'SecurGYM',
    accentColor: gym['accent_color'] as String? ?? '#0F766E',
    periodStart: periodStart,
    periodEnd: periodEnd,
    receivedAmount: payment.receivedAmount,
    creditUsed: payment.creditUsed,
    creditAdded: payment.creditAmount,
    creditBalance: member.creditBalance,
    memberEmail: member.email,
    memberPhone: member.whatsapp ?? member.phone,
    gymAddress: gym['address'] as String?,
    gymPhone: gym['phone'] as String?,
    gymEmail: gym['email'] as String?,
    reference: payment.reference,
    paidCurrency: payment.paidCurrency,
    exchangeRate: payment.exchangeRate,
    paidAmount: payment.paidAmount,
    tenderedAmount: payment.tenderedAmount,
    cashierName: cashierName,
  );

  /// Devise réellement donnée (null = même devise que [currency]).
  final String? paidCurrency;
  final double? exchangeRate;
  final double? paidAmount;
  final double? tenderedAmount;
  final String? cashierName;
  bool get foreignPayment => paidCurrency != null && paidCurrency != currency;

  ReceiptData withLogo(Uint8List? logo) => ReceiptData(
    paymentId: paymentId,
    memberName: memberName,
    memberNumber: memberNumber,
    planName: planName,
    amount: amount,
    currency: currency,
    method: method,
    paidAt: paidAt,
    gymName: gymName,
    accentColor: accentColor,
    periodStart: periodStart,
    periodEnd: periodEnd,
    receivedAmount: receivedAmount,
    creditUsed: creditUsed,
    creditAdded: creditAdded,
    creditBalance: creditBalance,
    memberEmail: memberEmail,
    memberPhone: memberPhone,
    gymAddress: gymAddress,
    gymPhone: gymPhone,
    gymEmail: gymEmail,
    logoBytes: logo,
    qrPromoBytes: qrPromoBytes,
    reference: reference,
    paidCurrency: paidCurrency,
    exchangeRate: exchangeRate,
    paidAmount: paidAmount,
    tenderedAmount: tenderedAmount,
    cashierName: cashierName,
  );

  final String paymentId;
  final String memberName;
  final String memberNumber;
  final String planName;
  final double amount;
  final String currency;
  final String method;
  final DateTime paidAt;
  final String gymName;
  final String accentColor;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final double? receivedAmount;
  final double creditUsed;
  final double creditAdded;
  final double creditBalance;
  final String? memberEmail;
  final String? memberPhone;
  final String? gymAddress;
  final String? gymPhone;
  final String? gymEmail;
  final Uint8List? logoBytes;
  final Uint8List? qrPromoBytes;
  final String? reference;

  String get receiptNo =>
      paymentId.replaceAll('-', '').substring(0, 8).toUpperCase();
  double get cashDue => amount - creditUsed;
  double get received => receivedAmount ?? cashDue;
  double get changeReturned => (received - cashDue - creditAdded) < 0
      ? 0
      : received - cashDue - creditAdded;
}

/// Jenerasyon PDF resi a — pwòp, lokalize, ak mak PAYÉ.
/// [labels] = kle yo rezoud depi AppStrings (lang manm nan).
Future<Uint8List> buildReceiptPdf(ReceiptData data, Map<String, String> labels) async {
  final accent = _pdfColor(data.accentColor);
  final money = NumberFormat('#,##0.00');
  final day = DateFormat('dd/MM/yyyy');
  final dateTime = DateFormat('dd/MM/yyyy HH:mm');
  String m(double v) => '${money.format(v)} ${data.currency}';
  String pm(double v) => '${money.format(v)} ${data.paidCurrency}';
  final paidKept = data.paidAmount ?? 0;
  final tendered = data.tenderedAmount ?? paidKept;
  String l(String key) => labels[key] ?? key;

  Uint8List? promoQr = data.qrPromoBytes;
  if (promoQr == null) {
    try {
      final bytes = await rootBundle.load('assets/brand/securegymqr.png');
      promoQr = bytes.buffer.asUint8List();
    } catch (_) {}
  }

  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Bann koulè + logo + non gym
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (data.logoBytes != null)
                  pw.Container(
                    width: 46,
                    height: 46,
                    margin: const pw.EdgeInsets.only(right: 12),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Image(pw.MemoryImage(data.logoBytes!)),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        data.gymName,
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        [
                          data.gymAddress,
                          data.gymPhone,
                          data.gymEmail,
                        ].where((e) => e != null && e.isNotEmpty).join(' · '),
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 7.5,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(6),
                        ),
                      ),
                      child: pw.Text(
                        l('receipt_paid'),
                        style: pw.TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '${l('receipt')} #${data.receiptNo}',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 8.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Manm
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  data.memberName,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  [
                    '${l('member_number')} ${data.memberNumber}',
                    if (data.memberEmail != null && data.memberEmail!.isNotEmpty)
                      data.memberEmail,
                    if (data.memberPhone != null && data.memberPhone!.isNotEmpty)
                      data.memberPhone,
                  ].join(' · '),
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // Detay peman
          _line(l('receipt_plan'), data.planName),
          if (data.periodStart != null && data.periodEnd != null)
            _line(
              l('receipt_period'),
              '${day.format(data.periodStart!)} → ${day.format(data.periodEnd!)}',
            ),
          _line(l('payment_method'), l('method_${data.method}')),
          _line(l('date'), dateTime.format(data.paidAt.toLocal())),
          if (data.reference != null && data.reference!.isNotEmpty)
            _line(l('receipt_reference'), data.reference!),
          if (data.cashierName != null && data.cashierName!.isNotEmpty)
            _line(l('received_by'), data.cashierName!),
          pw.SizedBox(height: 6),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 6),
          _line(l('receipt_amount'), m(data.amount), bold: true),
          if (data.creditUsed > 0)
            _line(l('receipt_paid_by_balance'), '- ${m(data.creditUsed)}'),
          if (data.foreignPayment)
            _line(
              l('receipt_paid_in'),
              '${pm(paidKept)}${data.exchangeRate == null ? '' : '  (1 USD = ${money.format(data.exchangeRate)} HTG)'}',
              bold: true,
              accent: accent,
            ),
          _line(l('receipt_received'), data.foreignPayment ? pm(tendered) : m(data.received)),
          if (data.creditAdded > 0)
            _line(l('receipt_credited'), m(data.creditAdded), accent: accent),
          if (data.foreignPayment && data.creditAdded <= 0 && tendered - paidKept > 0.004)
            _line(l('receipt_change'), pm(tendered - paidKept))
          else if (!data.foreignPayment && data.changeReturned > 0)
            _line(l('receipt_change'), m(data.changeReturned)),
          if (data.creditAdded > 0 || data.creditBalance > 0)
            _line(l('receipt_balance'), m(data.creditBalance)),
          pw.SizedBox(height: 18),

          // Siyati
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 120,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(color: PdfColors.grey400),
                      ),
                    ),
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text(
                      l('receipt_signature'),
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: accent, width: 1.4),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  '${data.gymName.toUpperCase()} · ${l('receipt_paid')}',
                  style: pw.TextStyle(
                    color: accent,
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.Spacer(),
          pw.Center(
            child: pw.Text(
              l('receipt_thanks'),
              style: pw.TextStyle(
                fontSize: 9,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey600,
              ),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Divider(color: PdfColors.grey200, thickness: 0.5),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (promoQr != null)
                pw.Container(
                  width: 26,
                  height: 26,
                  margin: const pw.EdgeInsets.only(right: 8),
                  child: pw.Image(pw.MemoryImage(promoQr)),
                ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Géré & sécurisé avec SecurGYM · securgym.com',
                    style: pw.TextStyle(
                      fontSize: 6.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.Text(
                    'Sécurité et gestion complète de votre salle de sport',
                    style: const pw.TextStyle(
                      fontSize: 5.5,
                      color: PdfColors.grey500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return document.save();
}

pw.Widget _line(String label, String value, {bool bold = false, PdfColor? accent}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: accent ?? PdfColors.grey900,
            ),
          ),
        ],
      ),
    );

PdfColor _pdfColor(String hex) {
  final match = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  if (match == null) return PdfColor.fromHex('#0F766E');
  return PdfColor.fromHex('#${match.group(1)}');
}
