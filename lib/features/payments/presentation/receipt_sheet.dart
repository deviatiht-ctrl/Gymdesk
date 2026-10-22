import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../l10n/app_strings.dart';
import '../data/receipt_pdf.dart';
import '../data/receipt_service.dart';

/// Dyalòg resi apre peman: telechaje / enprime / email / WhatsApp.
/// PDF la jenere yon fwa epi upload la fèt sèlman si itilizatè a
/// chwazi email oswa WhatsApp (bezwen entènèt).
Future<void> showReceiptSheet(
  BuildContext context,
  WidgetRef ref,
  ReceiptData data,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _ReceiptDialog(data: data),
  );
}

class _ReceiptDialog extends ConsumerStatefulWidget {
  const _ReceiptDialog({required this.data});
  final ReceiptData data;

  @override
  ConsumerState<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends ConsumerState<_ReceiptDialog> {
  Uint8List? _pdf;
  String? _error;
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_build());
  }

  Future<void> _build() async {
    final runtime = ref.read(appRuntimeProvider);
    final service = ReceiptService(runtime.client, runtime.session!.gymId!);
    final logo = await service.logoBytes(
      runtime.session!.gym?['logo_url'] as String?,
    );
    final pdf = await buildReceiptPdf(widget.data.withLogo(logo), _labels);
    if (mounted) setState(() => _pdf = pdf);
    // Resi a voye OTOMATIK pa email lè manm nan gen yon adrès —
    // pa bezwen klike anyen. RPC la idempotent: pa gen doublon.
    final email = widget.data.memberEmail ?? '';
    if (email.contains('@') && mounted) {
      unawaited(_sendEmail());
    }
  }

  Map<String, String> get _labels {
    final s = AppStrings.of(context);
    return {
      'receipt': s.text('receipt'),
      'receipt_paid': s.text('receipt_paid'),
      'receipt_plan': s.text('receipt_plan'),
      'receipt_period': s.text('receipt_period'),
      'receipt_amount': s.text('receipt_amount'),
      'receipt_received': s.text('receipt_received'),
      'receipt_credited': s.text('receipt_credited'),
      'receipt_paid_by_balance': s.text('receipt_paid_by_balance'),
      'receipt_change': s.text('receipt_change'),
      'receipt_paid_in': s.text('receipt_paid_in'),
      'received_by': s.text('received_by'),
      'receipt_balance': s.text('receipt_balance'),
      'receipt_reference': s.text('receipt_reference'),
      'receipt_signature': s.text('receipt_signature'),
      'receipt_thanks': s.text('receipt_thanks'),
      'member_number': s.text('member_number'),
      'payment_method': s.text('payment_method'),
      'date': s.text('date'),
      'method_cash': s.text('method_cash'),
      'method_moncash': s.text('method_moncash'),
      'method_natcash': s.text('method_natcash'),
      'method_bank': s.text('method_bank'),
      'method_card': s.text('method_card'),
      'method_cheque': s.text('method_cheque'),
      'method_other': s.text('method_other'),
      'method_credit': s.text('method_credit'),
      'registration_fee': s.text('registration_fee'),
      'reg_fee_included': s.text('reg_fee_included'),
      'reg_fee_waived': s.text('reg_fee_waived'),
    };
  }

  /// Upload PDF la sou sèvè a + retounen chemen an. Null si offline.
  Future<String?> _upload() async {
    final pdf = _pdf;
    if (pdf == null) return null;
    try {
      final runtime = ref.read(appRuntimeProvider);
      return await ReceiptService(
        runtime.client,
        runtime.session!.gymId!,
      ).upload(widget.data.paymentId, pdf);
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendEmail() async {
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _status = null;
      _error = null;
    });
    try {
      final runtime = ref.read(appRuntimeProvider);
      final service = ReceiptService(runtime.client, runtime.session!.gymId!);
      final path = await _upload();
      if (path == null) throw const FormatException('offline');
      final result = await service.enqueueEmailWithRetry(widget.data.paymentId, path);
      if (!mounted) return;
      setState(
        () => _status = switch (result) {
          'queued' || 'already_queued' => s.text('receipt_email_queued'),
          _ => s.text('receipt_no_email'),
        },
      );
    } catch (_) {
      if (mounted) setState(() => _error = s.text('receipt_send_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendWhatsapp() async {
    final s = AppStrings.of(context);
    final phone = (widget.data.memberPhone ?? '').replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) {
      setState(() => _error = s.text('receipt_no_phone'));
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
      _error = null;
    });
    try {
      final runtime = ref.read(appRuntimeProvider);
      final service = ReceiptService(runtime.client, runtime.session!.gymId!);
      final path = await _upload();
      if (path == null) throw const FormatException('offline');
      final url = await service.signedUrl(path);
      final d = widget.data;
      final day = DateFormat('dd/MM/yyyy');
      final message = [
        '*${d.gymName}*',
        '${s.text('receipt')} *#${d.receiptNo}* - ${s.text('receipt_paid')}',
        '',
        '${d.memberName} (${d.memberNumber})',
        '${s.text('receipt_plan')}: *${d.planName}*',
        if (d.periodStart != null && d.periodEnd != null)
          '${s.text('receipt_period')}: ${day.format(d.periodStart!)} -> ${day.format(d.periodEnd!)}',
        if (d.registrationFee > 0)
          '${s.text('registration_fee')}: ${d.registrationFee.toStringAsFixed(2)} ${d.currency} + ${d.planName}: ${(d.planFee > 0 ? d.planFee : d.amount - d.registrationFee).toStringAsFixed(2)} ${d.currency}',
        '${s.text('receipt_amount')}: *${d.amount.toStringAsFixed(2)} ${d.currency}*',
        if (d.foreignPayment && d.paidAmount != null)
          '${s.text('receipt_paid_in')}: ${d.paidAmount!.toStringAsFixed(2)} ${d.paidCurrency}',
        '',
        '${s.text('receipt_download')} (PDF):',
        url,
      ].join('\n');
      final ok = await launchUrl(
        Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}'),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) setState(() => _error = s.text('receipt_send_failed'));
    } catch (_) {
      if (mounted) setState(() => _error = s.text('receipt_send_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final d = widget.data;
    final money = NumberFormat('#,##0.00');
    return AlertDialog(
      title: Row(
        children: [
          Icon(LucideIcons.receipt, color: Theme.of(context).primaryColor),
          const SizedBox(width: 10),
          Expanded(child: Text('${s.text('receipt')} #${d.receiptNo}')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              d.memberName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${d.planName} · ${money.format(d.amount)} ${d.currency}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (d.registrationFee > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${s.text('registration_fee')}: ${money.format(d.registrationFee)} ${d.currency}  +  ${d.planName}: ${money.format(d.planFee > 0 ? d.planFee : (d.amount - d.registrationFee).clamp(0, double.infinity))} ${d.currency}',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF0F766E), fontWeight: FontWeight.w600),
              ),
            ],
            if (d.creditAdded > 0 || d.creditUsed > 0 || d.creditBalance > 0) ...[
              const SizedBox(height: 8),
              if (d.creditUsed > 0)
                Text(
                  '${s.text('receipt_paid_by_balance')}: -${money.format(d.creditUsed)} ${d.currency}',
                ),
              if (d.creditAdded > 0)
                Text(
                  '${s.text('receipt_credited')}: ${money.format(d.creditAdded)} ${d.currency}',
                ),
              if (d.creditBalance > 0)
                Text(
                  '${s.text('receipt_balance')}: ${money.format(d.creditBalance)} ${d.currency}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
            ],
            const SizedBox(height: 16),
            if (_pdf == null && _error == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(LucideIcons.download, size: 18),
                    label: Text(s.text('receipt_download')),
                    onPressed: _pdf == null
                        ? null
                        : () => Printing.sharePdf(
                            bytes: _pdf!,
                            filename: 'recu_${d.receiptNo}.pdf',
                          ),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(LucideIcons.printer, size: 18),
                    label: Text(s.text('receipt_print')),
                    onPressed: _pdf == null
                        ? null
                        : () => Printing.layoutPdf(
                            onLayout: (_) async => _pdf!,
                          ),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(LucideIcons.mail, size: 18),
                    label: Text(s.text('receipt_send_email')),
                    onPressed: _busy || _pdf == null ? null : _sendEmail,
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(LucideIcons.messageCircle, size: 18),
                    label: Text(s.text('receipt_send_whatsapp')),
                    onPressed: _busy || _pdf == null ? null : _sendWhatsapp,
                  ),
                ],
              ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _status!,
                    style: const TextStyle(color: Colors.green),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.text('close')),
        ),
      ],
    );
  }
}
