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
    final pdf = await buildReceiptPdf(
      ReceiptData(
        paymentId: widget.data.paymentId,
        memberName: widget.data.memberName,
        memberNumber: widget.data.memberNumber,
        planName: widget.data.planName,
        amount: widget.data.amount,
        currency: widget.data.currency,
        method: widget.data.method,
        paidAt: widget.data.paidAt,
        gymName: widget.data.gymName,
        accentColor: widget.data.accentColor,
        periodStart: widget.data.periodStart,
        periodEnd: widget.data.periodEnd,
        receivedAmount: widget.data.receivedAmount,
        creditUsed: widget.data.creditUsed,
        creditAdded: widget.data.creditAdded,
        creditBalance: widget.data.creditBalance,
        memberEmail: widget.data.memberEmail,
        memberPhone: widget.data.memberPhone,
        gymAddress: widget.data.gymAddress,
        gymPhone: widget.data.gymPhone,
        gymEmail: widget.data.gymEmail,
        logoBytes: logo,
        reference: widget.data.reference,
      ),
      _labels,
    );
    if (mounted) setState(() => _pdf = pdf);
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
      final result = await service.enqueueEmail(widget.data.paymentId, path);
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
      final message = '${widget.data.gymName} — '
          '${s.text('receipt')} #${widget.data.receiptNo} · '
          '${widget.data.amount.toStringAsFixed(2)} ${widget.data.currency}\n'
          '$url';
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
