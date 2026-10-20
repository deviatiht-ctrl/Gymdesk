import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_strings.dart';
import '../../members/domain/member.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../domain/currency.dart';
import '../domain/payment.dart';

/// Fiche complète d'un paiement (clic dans la liste Paiements / Reçus).
Future<void> showPaymentDetail(
  BuildContext context, {
  required GymPayment payment,
  Member? member,
  String? planName,
  DateTime? periodStart,
  DateTime? periodEnd,
  String? cashierName,
  VoidCallback? onReceipt,
}) {
  final s = AppStrings.of(context);
  final locale = Localizations.localeOf(context).toString();
  final foreign = payment.paidCurrency != payment.currency;
  final rows = <(IconData, String, String)>[
    (LucideIcons.user, s.text('member'), member == null ? payment.memberId : '${member.fullName} · ${member.memberNumber}'),
    if (member?.phone != null) (LucideIcons.phone, s.text('phone'), member!.phone!),
    (LucideIcons.calendarClock, s.text('date'), DateFormat.yMMMMd(locale).add_Hm().format(payment.paidAt.toLocal())),
    (LucideIcons.tag, s.text('plan'), planName ?? '—'),
    if (periodStart != null && periodEnd != null)
      (LucideIcons.calendarRange, s.text('subscription_period'), '${ymd(periodStart)} → ${ymd(periodEnd)}'),
    (LucideIcons.badgeDollarSign, s.text('amount'), money(payment.amount, payment.currency)),
    (LucideIcons.coins, s.text('paid_in_currency'), payment.paidCurrency),
    if (foreign && payment.exchangeRate != null)
      (LucideIcons.arrowLeftRight, s.text('exchange_rate'), '1 USD = ${payment.exchangeRate!.toStringAsFixed(2)} HTG'),
    (LucideIcons.wallet, s.text('collected_by_currency'), money(payment.paidAmount, payment.paidCurrency)),
    (LucideIcons.banknote, s.text('amount_received'), money(payment.tenderedAmount, payment.paidCurrency)),
    if (payment.changeInPaidCurrency > 0.004 && payment.creditAmount <= 0)
      (LucideIcons.undo2, s.text('change_due'), money(payment.changeInPaidCurrency, payment.paidCurrency)),
    if (payment.creditUsed > 0) (LucideIcons.piggyBank, s.text('use_balance'), money(payment.creditUsed, payment.currency)),
    if (payment.creditAmount > 0) (LucideIcons.piggyBank, s.text('keep_change_as_credit'), money(payment.creditAmount, payment.currency)),
    (LucideIcons.creditCard, s.text('payment_method'), s.text('method_${payment.method}')),
    if (payment.reference != null) (LucideIcons.hash, s.text('reference_receipt'), payment.reference!),
    if (cashierName != null) (LucideIcons.userCheck, s.text('received_by'), cashierName),
    if (payment.notes != null) (LucideIcons.stickyNote, s.text('notes'), payment.notes!),
    (LucideIcons.receipt, s.text('receipt_number'), payment.id.replaceAll('-', '').substring(0, 8).toUpperCase()),
  ];
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              money(payment.paidAmount, payment.paidCurrency),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (foreign)
              Text('= ${money(payment.cashDue + payment.creditAmount, payment.currency)}',
                  style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final (icon, label, value) in rows)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, size: 18),
                title: Text(label, style: Theme.of(context).textTheme.labelMedium),
                subtitle: Text(value, style: Theme.of(context).textTheme.bodyLarge),
              ),
            if (onReceipt != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onReceipt();
                },
                icon: const Icon(LucideIcons.receipt, size: 18),
                label: Text(s.text('view_receipt')),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
