import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../members/domain/member.dart';
import '../../plans/domain/plan.dart';
import '../../subscriptions/domain/gym_subscription.dart';
import '../data/payments_repository.dart';
import '../data/receipt_pdf.dart';
import '../domain/currency.dart';
import '../domain/payment.dart';
import 'payment_detail_sheet.dart';
import 'receipt_sheet.dart';

/// Tous les reçus (y compris anciens membres) : recherche par nom, numéro ou
/// téléphone, puis télécharger / imprimer / renvoyer. Lecture seule pour tous
/// les rôles — aucune action de modification ou suppression ici.
class ReceiptsPage extends ConsumerStatefulWidget {
  const ReceiptsPage({super.key});
  @override
  ConsumerState<ReceiptsPage> createState() => _ReceiptsPageState();
}

class _ReceiptsPageState extends ConsumerState<ReceiptsPage> {
  final _search = TextEditingController();
  String _period = 'month';
  DateTimeRange? _range;

  (DateTime?, DateTime?) get _bounds {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      'today' => (today, today.add(const Duration(days: 1))),
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
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (picked != null) {
      setState(() {
        _period = 'custom';
        _range = picked;
      });
    }
  }

  late final Stream<List<GymPayment>> _payments;
  late final Stream<Map<String, Json>> _members;
  late final Stream<Map<String, Json>> _subscriptions;
  late final Stream<Map<String, Json>> _plans;
  late final Stream<Map<String, Json>> _staff;

  @override
  void initState() {
    super.initState();
    final db = ref.read(appRuntimeProvider).database!;
    Stream<Map<String, Json>> rows(SyncEntity entity) => db
        .watchRecords(entity, limit: 50000)
        .map((list) => {for (final r in list) r.id: Map<String, dynamic>.from(jsonDecode(r.payload) as Map)})
        .asBroadcastStream();
    _payments = PaymentsRepository(db).watch(limit: 50000).asBroadcastStream();
    _members = rows(SyncEntity.members);
    _subscriptions = rows(SyncEntity.subscriptions);
    _plans = rows(SyncEntity.plans);
    _staff = rows(SyncEntity.staff);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ({String? plan, DateTime? start, DateTime? end}) _context(
    GymPayment payment,
    Map<String, Json> subscriptions,
    Map<String, Json> plans,
  ) {
    final subRow = subscriptions[payment.subscriptionId];
    final sub = subRow == null ? null : GymSubscription(subRow);
    final planRow = plans[sub?.planId];
    return (plan: planRow == null ? null : GymPlan(planRow).name, start: sub?.startDate, end: sub?.endDate);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final locale = Localizations.localeOf(context).toString();
    final gym = ref.read(appRuntimeProvider).session?.gym ?? const <String, dynamic>{};
    return StreamBuilder<Map<String, Json>>(
      stream: _members,
      builder: (context, memberSnap) => StreamBuilder<Map<String, Json>>(
        stream: _subscriptions,
        builder: (context, subSnap) => StreamBuilder<Map<String, Json>>(
          stream: _plans,
          builder: (context, planSnap) => StreamBuilder<Map<String, Json>>(
            stream: _staff,
            builder: (context, staffSnap) => StreamBuilder<List<GymPayment>>(
              stream: _payments,
              builder: (context, paySnap) {
                if (!paySnap.hasData || !memberSnap.hasData) {
                  return const Padding(padding: EdgeInsets.all(24), child: LoadingPanel());
                }
                final members = memberSnap.data!;
                final subs = subSnap.data ?? const <String, Json>{};
                final plans = planSnap.data ?? const <String, Json>{};
                final staff = staffSnap.data ?? const <String, Json>{};
                final query = _search.text.trim().toLowerCase();
                final digits = query.replaceAll(RegExp(r'\D'), '');
                final bounds = _bounds;
                final start = bounds.$1;
                final end = bounds.$2;
                final list = paySnap.data!.where((p) {
                  if (start != null && p.paidAt.toLocal().isBefore(start)) return false;
                  if (end != null && !p.paidAt.toLocal().isBefore(end)) return false;
                  if (query.isEmpty) return true;
                  final row = members[p.memberId];
                  if (row == null) return false;
                  final m = Member(row);
                  final text = '${m.fullName} ${m.memberNumber} ${p.id.replaceAll('-', '').substring(0, 8)}'.toLowerCase();
                  final phones = '${m.phone ?? ''}${m.whatsapp ?? ''}'.replaceAll(RegExp(r'\D'), '');
                  return text.contains(query) || (digits.length >= 4 && phones.contains(digits));
                }).take(300).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.text('receipts'), style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 4),
                          Text(s.text('receipts_hint'), style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _search,
                            autofocus: false,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(LucideIcons.search),
                              hintText: s.text('search_payments'),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ChoiceChip(
                                label: Text(s.text('period_today')),
                                selected: _period == 'today',
                                onSelected: (_) => setState(() => _period = 'today'),
                              ),
                              ChoiceChip(
                                label: Text(s.text('period_week')),
                                selected: _period == 'week',
                                onSelected: (_) => setState(() => _period = 'week'),
                              ),
                              ChoiceChip(
                                label: Text(s.text('period_month')),
                                selected: _period == 'month',
                                onSelected: (_) => setState(() => _period = 'month'),
                              ),
                              ChoiceChip(
                                label: Text(s.text('period_year')),
                                selected: _period == 'year',
                                onSelected: (_) => setState(() => _period = 'year'),
                              ),
                              ChoiceChip(
                                label: Text(s.text('period_all')),
                                selected: _period == 'all',
                                onSelected: (_) => setState(() => _period = 'all'),
                              ),
                              ActionChip(
                                avatar: const Icon(LucideIcons.calendarDays, size: 16),
                                label: Text(_period == 'custom' && _range != null
                                    ? ' - '
                                    : s.text('period_custom')),
                                onPressed: _pickRange,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: MessagePanel(message: s.text('payments_empty')),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                              itemCount: list.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final payment = list[index];
                                final row = members[payment.memberId];
                                final member = row == null ? null : Member(row);
                                final cashier = staff[payment.receivedBy]?['full_name'] as String?;
                                final ctx = _context(payment, subs, plans);
                                void openReceipt() => showReceiptSheet(
                                  context,
                                  ref,
                                  ReceiptData.fromPayment(
                                    payment: payment,
                                    member: member!,
                                    gym: gym,
                                    planName: ctx.plan,
                                    periodStart: ctx.start,
                                    periodEnd: ctx.end,
                                    cashierName: cashier,
                                  ),
                                );
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                  leading: CircleAvatar(child: Icon(LucideIcons.receipt, size: 18)),
                                  title: Text(
                                    '${member?.fullName ?? payment.memberId} · ${money(payment.amount, payment.currency)}',
                                  ),
                                  subtitle: Text(
                                    '#${payment.id.replaceAll('-', '').substring(0, 8).toUpperCase()}'
                                    ' · ${member?.memberNumber ?? ''}'
                                    ' · ${ctx.plan ?? ''}'
                                    ' · ${DateFormat.yMMMd(locale).add_Hm().format(payment.paidAt.toLocal())}',
                                  ),
                                  onTap: () => showPaymentDetail(
                                    context,
                                    payment: payment,
                                    member: member,
                                    planName: ctx.plan,
                                    periodStart: ctx.start,
                                    periodEnd: ctx.end,
                                    cashierName: cashier,
                                    onReceipt: member == null ? null : openReceipt,
                                  ),
                                  trailing: member == null
                                      ? null
                                      : FilledButton.tonalIcon(
                                          onPressed: openReceipt,
                                          icon: const Icon(LucideIcons.fileDown, size: 16),
                                          label: Text(s.text('view_receipt')),
                                        ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
