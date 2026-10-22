import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../members/data/members_repository.dart';
import '../../members/domain/member.dart';
import '../../plans/data/plans_repository.dart';
import '../../plans/domain/plan.dart';
import '../../subscriptions/data/subscriptions_repository.dart';
import '../../subscriptions/domain/gym_subscription.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import 'package:uuid/uuid.dart';

import '../data/payments_repository.dart';
import '../data/receipt_pdf.dart';
import '../data/receipt_service.dart';
import '../domain/payment.dart';
import '../domain/currency.dart';
import 'collect_payment_dialog.dart';
import 'payment_detail_sheet.dart';
import 'receipt_sheet.dart';

class PaymentsPage extends ConsumerStatefulWidget {
  const PaymentsPage({super.key});
  @override
  ConsumerState<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends ConsumerState<PaymentsPage> {
  late final PaymentsRepository _payments;
  late final SubscriptionsRepository _subscriptions;
  late final PlansRepository _plans;
  late final MembersRepository _members;
  String _method = 'all';
  String _period = 'month';
  DateTimeRange? _range;
  final _search = TextEditingController();
  bool _busy = false;
  late final Stream<Map<String, Member>> _memberMap;
  late final Stream<Map<String, String>> _staffNames;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _payments = PaymentsRepository(runtime.database!);
    _subscriptions = SubscriptionsRepository(
      runtime.database!,
      runtime.session!,
    );
    _plans = PlansRepository(runtime.database!, runtime.session!);
    _members = MembersRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
    _memberMap = _watchMembers().asBroadcastStream();
    _staffNames = runtime.database!
        .watchRecords(SyncEntity.staff, limit: 500)
        .map(
          (rows) => {
            for (final row in rows)
              row.id: (jsonDecode(row.payload) as Map)['full_name'] as String? ?? '',
          },
        )
        .asBroadcastStream();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Début/fin (heure locale) de la période choisie.
  (DateTime?, DateTime?) get _bounds {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      'today' => (today, today.add(const Duration(days: 1))),
      'yesterday' => (
        today.subtract(const Duration(days: 1)),
        today,
      ),
      'week' => (today.subtract(Duration(days: today.weekday - 1)), today.add(const Duration(days: 1))),
      'month' => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
      'year' => (DateTime(now.year), DateTime(now.year + 1)),
      'custom' when _range != null => (_range!.start, _range!.end.add(const Duration(days: 1))),
      _ => (null, null),
    };
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() {
        _range = picked;
        _period = 'custom';
      });
    }
  }

  Future<void> _pickSingleDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _range?.start ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      helpText: 'Filtrer les paiements pour une date précise',
    );
    if (picked != null && mounted) {
      final d = DateTime(picked.year, picked.month, picked.day);
      setState(() {
        _range = DateTimeRange(start: d, end: d);
        _period = 'custom';
      });
    }
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentStart = _range?.start ?? _bounds.$1 ?? today;
    final currentEnd = _range?.end ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      helpText: 'Date de début (Du)',
    );
    if (picked != null && mounted) {
      final d = DateTime(picked.year, picked.month, picked.day);
      setState(() {
        _range = DateTimeRange(
          start: d,
          end: currentEnd.isBefore(d) ? d : currentEnd,
        );
        _period = 'custom';
      });
    }
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentStart = _range?.start ?? _bounds.$1 ?? today;
    final currentEnd = _range?.end ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentEnd,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      helpText: 'Date de fin (Au)',
    );
    if (picked != null && mounted) {
      final d = DateTime(picked.year, picked.month, picked.day);
      setState(() {
        _range = DateTimeRange(
          start: currentStart.isAfter(d) ? d : currentStart,
          end: d,
        );
        _period = 'custom';
      });
    }
  }

  Stream<Map<String, Member>> _watchMembers() => ref
      .read(appRuntimeProvider)
      .database!
      .watchRecords(SyncEntity.members, limit: 50000)
      .map(
        (rows) => {
          for (final row in rows)
            row.id: Member(
              Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
            ),
        },
      );

  Future<void> _collect(Member member, GymSubscription subscription) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final remaining = subscription.remainingAfter(
      await _payments.paidForSubscription(subscription.id),
    );
    if (!mounted || remaining <= 0) return;
    final result = await showCollectPaymentDialog(
      context,
      title: '${s.text('collect_payment')} · ${member.fullName}',
      due: remaining,
      balance: member.creditBalance,
      currency: ref.read(appRuntimeProvider).session?.gym?['currency'] as String? ?? 'HTG',
      rate: gymExchangeRate(ref.read(appRuntimeProvider).session?.settings ?? const {}),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final command = result.command(
        id: const Uuid().v4(),
        memberId: member.id,
        subscriptionId: subscription.id,
        currency:
            ref.read(appRuntimeProvider).session?.gym?['currency']
                as String? ??
            'HTG',
      );
      await _members.collectPayment(subscription, command, changedAt: _now());
      await ref.read(appRuntimeProvider).sync?.synchronize();
      if (mounted) await _openReceipt(member, subscription, command);
    } on MemberFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text(e.code))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  DateTime _now() =>
      ref.read(appRuntimeProvider).sync?.clock.correctedNow ??
      DateTime.now().toUtc();

  Future<(GymSubscription?, GymPlan?)> _context(GymPayment payment) async {
    GymSubscription? subscription;
    for (final sub in await _subscriptions.watch(limit: 50000).first) {
      if (sub.id == payment.subscriptionId) subscription = sub;
    }
    GymPlan? plan;
    for (final p in await _plans.watch().first) {
      if (p.id == subscription?.planId) plan = p;
    }
    return (subscription, plan);
  }

  /// Re-ouvri resi a pou yon peman nan istorik la (re-telechaje, renvoye).
  Future<void> _receiptForPayment(Member member, GymPayment payment, {String? cashier}) async {
    final gym = ref.read(appRuntimeProvider).session?.gym ?? const <String, dynamic>{};
    final (subscription, plan) = await _context(payment);
    if (!mounted) return;
    await showReceiptSheet(
      context,
      ref,
      ReceiptData.fromPayment(
        payment: payment,
        member: member,
        gym: gym,
        planName: plan?.name,
        periodStart: subscription?.startDate,
        periodEnd: subscription?.endDate,
        cashierName: cashier,
      ),
    );
  }

  Future<void> _detail(GymPayment payment, Member? member, String? cashier) async {
    final (subscription, plan) = await _context(payment);
    if (!mounted) return;
    await showPaymentDetail(
      context,
      payment: payment,
      member: member,
      planName: plan?.name,
      periodStart: subscription?.startDate,
      periodEnd: subscription?.endDate,
      cashierName: cashier,
      onReceipt: member == null ? null : () => _receiptForPayment(member, payment, cashier: cashier),
    );
  }

  /// Louvri dyalòg resi a apre peman an (download / print / email / WhatsApp).
  Future<void> _openReceipt(
    Member member,
    GymSubscription subscription,
    PaymentCommand command,
  ) async {
    final s = AppStrings.of(context);
    final runtime = ref.read(appRuntimeProvider);
    final gym = runtime.session?.gym ?? const <String, dynamic>{};
    final plans = await _plans.watch().first;
    GymPlan? plan;
    for (final p in plans) {
      if (p.id == subscription.planId) plan = p;
    }
    if (!mounted) return;
    final data = ReceiptData(
      paymentId: command.id ?? '',
      memberName: member.fullName,
      memberNumber: member.memberNumber,
      planName: plan?.name ?? s.text('plan'),
      amount: command.amount,
      currency: command.currency,
      method: command.method,
      paidAt: _now(),
      gymName: gym['name'] as String? ?? 'GymDesk',
      accentColor: gym['accent_color'] as String? ?? '#0F766E',
      periodStart: subscription.startDate,
      periodEnd: subscription.endDate,
      receivedAmount: command.effectiveReceived,
      creditUsed: command.creditUsed,
      creditAdded: command.creditAdded,
      creditBalance:
          member.creditBalance + command.creditAdded - command.creditUsed,
      memberEmail: member.email,
      memberPhone: member.whatsapp ?? member.phone,
      gymAddress: gym['address'] as String?,
      gymPhone: gym['phone'] as String?,
      gymEmail: gym['email'] as String?,
      registrationFee: command.registrationFee,
      planFee: command.planFee ?? command.amount,
      paymentReason: command.paymentReason,
    );
    // Voye resi a otomatik pa email (silansye si offline / san email).
    final gymId = runtime.session?.gymId;
    if (gymId != null) {
      unawaited(
        ReceiptService(runtime.client, gymId)
            .autoEnqueue(data, gym['logo_url'] as String?),
      );
    }
    await showReceiptSheet(context, ref, data);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final locale = Localizations.localeOf(context).toString();
    final (from, to) = _bounds;
    return StreamBuilder<Map<String, Member>>(
      stream: _memberMap,
      builder: (context, memberSnapshot) {
        final members = memberSnapshot.data ?? const <String, Member>{};
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 20,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(s.text('payments'), style: Theme.of(context).textTheme.headlineMedium),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final method in ['all', 'cash', 'moncash', 'natcash', 'bank', 'other'])
                        ChoiceChip(
                          label: Text(s.text(method == 'all' ? 'member_filter_all' : 'method_$method')),
                          selected: _method == method,
                          onSelected: (_) => setState(() => _method = method),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final period in ['today', 'yesterday', 'week', 'month', 'year', 'all'])
                    ChoiceChip(
                      label: Text(
                        period == 'yesterday' ? 'Hier' : s.text('period_$period'),
                      ),
                      selected: _period == period,
                      onSelected: (_) => setState(() => _period = period),
                    ),
                  OutlinedButton.icon(
                    onPressed: _pickSingleDate,
                    icon: const Icon(LucideIcons.calendar, size: 15),
                    label: const Text('Date précise'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickStartDate,
                    icon: const Icon(LucideIcons.calendarRange, size: 15),
                    label: Text(
                      _range != null && _period == 'custom'
                          ? 'Du : ${DateFormat('dd/MM/yyyy').format(_range!.start)}'
                          : 'Du...',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickEndDate,
                    icon: const Icon(LucideIcons.calendarCheck, size: 15),
                    label: Text(
                      _range != null && _period == 'custom'
                          ? 'Au : ${DateFormat('dd/MM/yyyy').format(_range!.end)}'
                          : 'Au...',
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(LucideIcons.calendarRange, size: 16),
                    label: Text(
                      _period == 'custom' && _range != null
                          ? '${DateFormat.yMd(locale).format(_range!.start)} → ${DateFormat.yMd(locale).format(_range!.end)}'
                          : s.text('period_custom'),
                    ),
                    onPressed: _pickRange,
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(LucideIcons.search, size: 18),
                        hintText: s.text('search_payments'),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: StreamBuilder<Map<String, String>>(
                stream: _staffNames,
                builder: (context, staffSnapshot) {
                  final staff = staffSnapshot.data ?? const <String, String>{};
                  return StreamBuilder<List<GymSubscription>>(
                    stream: _subscriptions.watch(status: 'pending', limit: 5000),
                    builder: (context, subscriptionSnapshot) {
                      return StreamBuilder<List<GymPlan>>(
                        stream: _plans.watch(),
                        builder: (context, planSnapshot) {
                          final plans = {
                            for (final plan in planSnapshot.data ?? const <GymPlan>[]) plan.id: plan,
                          };
                          return StreamBuilder<List<GymPayment>>(
                            stream: _payments.watch(method: _method, limit: 50000, from: from, to: to),
                            builder: (context, paymentSnapshot) {
                              if (subscriptionSnapshot.hasError || paymentSnapshot.hasError || memberSnapshot.hasError) {
                                return SingleChildScrollView(
                                  padding: const EdgeInsets.all(24),
                                  child: MessagePanel(message: s.text('local_storage')),
                                );
                              }
                              if (!subscriptionSnapshot.hasData || !paymentSnapshot.hasData) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 24),
                                  child: LoadingPanel(),
                                );
                              }
                              final query = _search.text.trim().toLowerCase();
                              bool matches(Member? m) =>
                                  query.isEmpty ||
                                  (m != null &&
                                      '${m.fullName} ${m.memberNumber} ${m.phone ?? ''} ${m.whatsapp ?? ''}'
                                          .toLowerCase()
                                          .contains(query));
                              final pending = subscriptionSnapshot.data!.where((sub) => matches(members[sub.memberId])).toList();
                              final payments = paymentSnapshot.data!.where((p) => matches(members[p.memberId])).toList();
                              final billed = <String, double>{};
                              for (final p in payments) {
                                billed[p.currency] = (billed[p.currency] ?? 0) + p.amount;
                              }
                              final collected = collectedByCurrency(payments.map((p) => p.row));
                              final byDay = <String, List<GymPayment>>{};
                              for (final p in payments) {
                                byDay.putIfAbsent(ymd(p.paidAt.toLocal()), () => []).add(p);
                              }
                              return ListView(
                                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                                children: [
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Wrap(
                                        spacing: 32,
                                        runSpacing: 12,
                                        children: [
                                          _Stat(
                                            label: '${s.text('payments_total')} · ${payments.length} ${s.text('payments_count')}',
                                            value: billed.isEmpty
                                                ? '0'
                                                : billed.entries.map((e) => money(e.value, e.key)).join('  +  '),
                                          ),
                                          for (final entry in collected.entries)
                                            _Stat(
                                              label: '${s.text('collected_by_currency')} (${entry.key})',
                                              value: money(entry.value, entry.key),
                                              highlight: true,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (pending.isNotEmpty) ...[
                                    const SizedBox(height: 20),
                                    Text(s.text('pending_subscriptions'), style: Theme.of(context).textTheme.titleLarge),
                                    const SizedBox(height: 8),
                                    Card(
                                      child: Column(
                                        children: [
                                          for (final subscription in pending)
                                            Builder(
                                              builder: (context) {
                                                final member = members[subscription.memberId];
                                                final plan = subscription.planId == null ? null : plans[subscription.planId];
                                                return ListTile(
                                                  title: Text(member?.fullName ?? subscription.memberId),
                                                  subtitle: Text(
                                                    '${plan?.name ?? s.text('plan')} · ${subscription.price.toStringAsFixed(2)} · ${DateFormat.yMd(locale).format(subscription.endDate)}',
                                                  ),
                                                  trailing: member == null
                                                      ? null
                                                      : TextButton(
                                                          onPressed: _busy ? null : () => _collect(member, subscription),
                                                          child: Text(s.text('collect_payment')),
                                                        ),
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  Text(s.text('payment_history'), style: Theme.of(context).textTheme.titleLarge),
                                  if (payments.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: MessagePanel(message: s.text('payments_empty')),
                                    ),
                                  for (final day in byDay.entries) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              DateFormat.yMMMMEEEEd(locale == 'ht' ? 'fr' : locale)
                                                  .format(DateTime.parse(day.key)),
                                              style: Theme.of(context).textTheme.titleSmall,
                                            ),
                                          ),
                                          Text(
                                            collectedByCurrency(day.value.map((p) => p.row))
                                                .entries
                                                .map((e) => money(e.value, e.key))
                                                .join(' · '),
                                            style: Theme.of(context).textTheme.titleSmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Card(
                                      child: Column(
                                        children: [
                                          for (final payment in day.value)
                                            Builder(
                                              builder: (context) {
                                                final member = members[payment.memberId];
                                                final cashier = payment.receivedBy == null ? null : staff[payment.receivedBy];
                                                final foreign = payment.paidCurrency != payment.currency;
                                                return ListTile(
                                                  onTap: () => _detail(payment, member, cashier),
                                                  leading: const Icon(LucideIcons.banknote),
                                                  title: Text(
                                                    '${member?.fullName ?? payment.memberId} · ${money(payment.amount, payment.currency)}'
                                                    '${foreign ? '  (${money(payment.paidAmount, payment.paidCurrency)})' : ''}',
                                                  ),
                                                  subtitle: Text(
                                                    '${s.text('method_${payment.method}')} · ${DateFormat.Hm(locale).format(payment.paidAt.toLocal())}'
                                                    '${cashier == null || cashier.isEmpty ? '' : ' · $cashier'}'
                                                    '${payment.reference == null ? '' : ' · ${payment.reference}'}',
                                                  ),
                                                  trailing: member == null
                                                      ? const Icon(LucideIcons.chevronRight, size: 18)
                                                      : IconButton(
                                                          tooltip: s.text('view_receipt'),
                                                          icon: const Icon(LucideIcons.receipt, size: 18),
                                                          onPressed: () => _receiptForPayment(member, payment, cashier: cashier),
                                                        ),
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: highlight ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
    ],
  );
}
