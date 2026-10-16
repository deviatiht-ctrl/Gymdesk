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
import 'package:uuid/uuid.dart';

import '../data/payments_repository.dart';
import '../data/receipt_pdf.dart';
import '../data/receipt_service.dart';
import '../domain/payment.dart';
import 'collect_payment_dialog.dart';
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
    final result = await showCollectPaymentDialog(
      context,
      title: '${s.text('collect_payment')} · ${member.fullName}',
      due: remaining,
      balance: member.creditBalance,
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

  /// Re-ouvri resi a pou yon peman nan istorik la (re-telechaje, renvoye).
  Future<void> _receiptForPayment(Member member, GymPayment payment) async {
    final s = AppStrings.of(context);
    final runtime = ref.read(appRuntimeProvider);
    final gym = runtime.session?.gym ?? const <String, dynamic>{};
    GymSubscription? subscription;
    for (final sub in await _subscriptions.watch(limit: 50000).first) {
      if (sub.id == payment.subscriptionId) subscription = sub;
    }
    GymPlan? plan;
    for (final p in await _plans.watch().first) {
      if (p.id == subscription?.planId) plan = p;
    }
    if (!mounted) return;
    await showReceiptSheet(
      context,
      ref,
      ReceiptData(
        paymentId: payment.id,
        memberName: member.fullName,
        memberNumber: member.memberNumber,
        planName: plan?.name ?? s.text('plan'),
        amount: payment.amount,
        currency: payment.currency,
        method: payment.method,
        paidAt: payment.paidAt,
        gymName: gym['name'] as String? ?? 'GymDesk',
        accentColor: gym['accent_color'] as String? ?? '#0F766E',
        periodStart: subscription?.startDate,
        periodEnd: subscription?.endDate,
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
      ),
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
                                    '${s.text('payments_total')}: ${total.toStringAsFixed(2)} ${ref.read(appRuntimeProvider).session?.gym?['currency'] as String? ?? 'USD'}',
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
                                            trailing: member == null
                                                ? null
                                                : IconButton(
                                                    tooltip: s.text(
                                                      'view_receipt',
                                                    ),
                                                    icon: const Icon(
                                                      LucideIcons.receipt,
                                                      size: 18,
                                                    ),
                                                    onPressed: () =>
                                                        _receiptForPayment(
                                                          member,
                                                          payment,
                                                        ),
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
