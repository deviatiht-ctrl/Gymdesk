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
import '../data/payments_repository.dart';
import '../domain/payment.dart';

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
  bool _busy = false;

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
  }

  Stream<Map<String, Member>> get _memberMap => ref
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
    final amount = TextEditingController(text: remaining.toStringAsFixed(2));
    String method = 'cash';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('${s.text('collect_payment')} · ${member.fullName}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: s.text('amount')),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: InputDecoration(
                    labelText: s.text('payment_method'),
                  ),
                  items: ['cash', 'moncash', 'natcash', 'bank', 'other']
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(s.text('method_$m')),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => method = v ?? 'cash',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.text('save')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      amount.dispose();
      return;
    }
    final value = double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
    amount.dispose();
    setState(() => _busy = true);
    try {
      await _members.collectPayment(
        subscription,
        PaymentCommand(
          memberId: member.id,
          subscriptionId: subscription.id,
          amount: value,
          currency:
              ref.read(appRuntimeProvider).session?.gym?['currency']
                  as String? ??
              'HTG',
          method: method,
        ),
        changedAt:
            ref.read(appRuntimeProvider).sync?.clock.correctedNow ??
            DateTime.now().toUtc(),
      );
      await ref.read(appRuntimeProvider).sync?.synchronize();
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

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final locale = Localizations.localeOf(context).toString();
    return StreamBuilder<Map<String, Member>>(
      stream: _memberMap,
      builder: (context, memberSnapshot) {
        final members = memberSnapshot.data ?? const <String, Member>{};
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 20,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    s.text('payments'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final method in [
                        'all',
                        'cash',
                        'moncash',
                        'natcash',
                        'bank',
                        'other',
                      ])
                        ChoiceChip(
                          label: Text(
                            s.text(
                              method == 'all'
                                  ? 'member_filter_all'
                                  : 'method_$method',
                            ),
                          ),
                          selected: _method == method,
                          onSelected: (_) => setState(() => _method = method),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: StreamBuilder<List<GymSubscription>>(
                stream: _subscriptions.watch(status: 'pending', limit: 5000),
                builder: (context, subscriptionSnapshot) {
                  return StreamBuilder<List<GymPlan>>(
                    stream: _plans.watch(),
                    builder: (context, planSnapshot) {
                      final plans = {
                        for (final plan
                            in planSnapshot.data ?? const <GymPlan>[])
                          plan.id: plan,
                      };
                      return StreamBuilder<List<GymPayment>>(
                        stream: _payments.watch(method: _method, limit: 5000),
                        builder: (context, paymentSnapshot) {
                          if (subscriptionSnapshot.hasError ||
                              paymentSnapshot.hasError ||
                              memberSnapshot.hasError) {
                            return SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: MessagePanel(
                                message: s.text('local_storage'),
                              ),
                            );
                          }
                          if (!subscriptionSnapshot.hasData ||
                              !paymentSnapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24),
                              child: LoadingPanel(),
                            );
                          }
                          final pending = subscriptionSnapshot.data!;
                          final payments = paymentSnapshot.data!;
                          final total = payments.fold<double>(
                            0,
                            (sum, payment) => sum + payment.amount,
                          );
                          if (pending.isEmpty && payments.isEmpty) {
                            return SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: MessagePanel(
                                message: s.text('payments_empty'),
                              ),
                            );
                          }
                          return ListView(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            children: [
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    '${s.text('payments_total')}: ${total.toStringAsFixed(2)} ${ref.read(appRuntimeProvider).session?.gym?['currency'] as String? ?? 'HTG'}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ),
                              ),
                              if (pending.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                Text(
                                  s.text('pending_subscriptions'),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Card(
                                  child: Column(
                                    children: [
                                      for (final subscription in pending)
                                        Builder(
                                          builder: (context) {
                                            final member =
                                                members[subscription.memberId];
                                            final plan =
                                                subscription.planId == null
                                                ? null
                                                : plans[subscription.planId];
                                            return ListTile(
                                              title: Text(
                                                member?.fullName ??
                                                    subscription.memberId,
                                              ),
                                              subtitle: Text(
                                                '${plan?.name ?? s.text('plan')} · ${subscription.price.toStringAsFixed(2)} · ${DateFormat.yMd(locale).format(subscription.endDate)}',
                                              ),
                                              trailing: member == null
                                                  ? null
                                                  : TextButton(
                                                      onPressed: _busy
                                                          ? null
                                                          : () => _collect(
                                                              member,
                                                              subscription,
                                                            ),
                                                      child: Text(
                                                        s.text(
                                                          'collect_payment',
                                                        ),
                                                      ),
                                                    ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              Text(
                                s.text('payment_history'),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Card(
                                child: Column(
                                  children: [
                                    for (final payment in payments)
                                      Builder(
                                        builder: (context) {
                                          final member =
                                              members[payment.memberId];
                                          return ListTile(
                                            leading: const Icon(
                                              LucideIcons.banknote,
                                            ),
                                            title: Text(
                                              '${payment.amount.toStringAsFixed(2)} ${payment.currency} · ${member?.fullName ?? payment.memberId}',
                                            ),
                                            subtitle: Text(
                                              '${s.text('method_${payment.method}')} · ${DateFormat.yMMMd(locale).add_Hm().format(payment.paidAt.toLocal())}${payment.reference == null ? '' : ' · ${payment.reference}'}',
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ],
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
