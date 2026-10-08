import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'reports_repository.dart';

Future<Uint8List> buildReportPdf(
  ReportSnapshot snapshot, {
  required String gymName,
  required String currency,
  required Map<String, String> labels,
}) async {
  final document = pw.Document();
  final date = DateFormat('yyyy-MM-dd HH:mm');
  final day = DateFormat('yyyy-MM-dd');
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Text(
          gymName,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${day.format(snapshot.start)} → ${day.format(snapshot.end)}',
          style: const pw.TextStyle(color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 18),
        pw.Row(
          children: [
            _metric(labels['payments']!, snapshot.payments.length.toString()),
            _metric(
              labels['revenue']!,
              '${snapshot.revenue.toStringAsFixed(2)} $currency',
            ),
            _metric(labels['entries']!, snapshot.granted.toString()),
            _metric(labels['denied']!, snapshot.denied.toString()),
          ],
        ),
        pw.SizedBox(height: 22),
        _section(
          labels['payments']!,
          [
            labels['date']!,
            labels['member']!,
            labels['amount']!,
            labels['method']!,
            labels['staff']!,
          ],
          snapshot.payments
              .take(80)
              .map(
                (payment) => [
                  date.format(payment.paidAt.toLocal()),
                  snapshot.memberName(payment.memberId),
                  '${payment.amount.toStringAsFixed(2)} ${payment.currency}',
                  payment.method,
                  snapshot.staffName(payment.receivedBy),
                ],
              )
              .toList(),
        ),
        _section(
          labels['attendance']!,
          [
            labels['date']!,
            labels['member']!,
            labels['result']!,
            labels['entry']!,
          ],
          snapshot.attendance
              .take(80)
              .map(
                (entry) => [
                  date.format(entry.scannedAt.toLocal()),
                  snapshot.memberName(entry.memberId),
                  entry.result,
                  entry.entryNumberToday?.toString() ?? '',
                ],
              )
              .toList(),
        ),
        _section(
          labels['expiring']!,
          [labels['member']!, labels['end']!, labels['amount']!],
          snapshot.expiring
              .take(80)
              .map(
                (subscription) => [
                  snapshot.memberName(subscription.memberId),
                  day.format(subscription.endDate),
                  subscription.price.toStringAsFixed(2),
                ],
              )
              .toList(),
        ),
        if (snapshot.audit.isNotEmpty)
          _section(
            labels['audit']!,
            [
              labels['date']!,
              labels['staff']!,
              labels['action']!,
              labels['entity']!,
            ],
            snapshot.audit
                .take(80)
                .map(
                  (entry) => [
                    date.format(entry.createdAt.toLocal()),
                    snapshot.staffName(entry.actorId),
                    entry.action,
                    entry.entity,
                  ],
                )
                .toList(),
          ),
      ],
    ),
  );
  return document.save();
}

pw.Widget _metric(String label, String value) => pw.Expanded(
  child: pw.Container(
    padding: const pw.EdgeInsets.all(10),
    margin: const pw.EdgeInsets.only(right: 6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ),
  ),
);

pw.Widget _section(
  String title,
  List<String> headers,
  List<List<String>> rows,
) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.SizedBox(height: 18),
    pw.Text(
      title,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 6),
    pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
      columnWidths: {
        for (var i = 0; i < headers.length; i++) i: const pw.FlexColumnWidth(),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: headers.map((value) => _cell(value, bold: true)).toList(),
        ),
        if (rows.isEmpty)
          pw.TableRow(
            children: [
              _cell('-'),
              ...List.generate(headers.length - 1, (_) => _cell('')),
            ],
          ),
        ...rows.map((row) => pw.TableRow(children: row.map(_cell).toList())),
      ],
    ),
  ],
);

pw.Widget _cell(String value, {bool bold = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
  child: pw.Text(
    value,
    maxLines: 2,
    style: pw.TextStyle(
      fontSize: 7.5,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  ),
);
