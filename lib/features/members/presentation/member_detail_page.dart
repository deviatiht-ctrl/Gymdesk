import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../badges/data/badges_repository.dart';
import '../../badges/domain/badge.dart';
import '../../payments/domain/payment.dart';
import '../../plans/data/plans_repository.dart';
import '../../plans/domain/plan.dart';
import '../../subscriptions/data/subscriptions_repository.dart';
import '../../subscriptions/domain/gym_subscription.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../data/member_pin_service.dart';
import '../data/members_repository.dart';
import '../domain/member.dart';

class MemberDetailPage extends ConsumerStatefulWidget {
  const MemberDetailPage({super.key, required this.memberId});
  final String memberId;
  @override
  ConsumerState<MemberDetailPage> createState() => _MemberDetailPageState();
}

class _MemberDetailPageState extends ConsumerState<MemberDetailPage> {
  late final MembersRepository _members;
  late final PlansRepository _plans;
  late final SubscriptionsRepository _subscriptions;
  late final BadgesRepository _badges;
  late final MemberPinService _pins;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _members = MembersRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
    _badges = BadgesRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
    _pins = MemberPinService(runtime.database!);
    _plans = PlansRepository(runtime.database!, runtime.session!);
    _subscriptions = SubscriptionsRepository(
      runtime.database!,
      runtime.session!,
    );
  }

  DateTime get _now =>
      ref.read(appRuntimeProvider).sync?.clock.correctedNow ??
      DateTime.now().toUtc();

  void _error(String code) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(AppStrings.of(context).text(code))));

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await ref.read(appRuntimeProvider).sync?.synchronize();
    } on MemberFailure catch (e) {
      _error(e.code);
    } on SubscriptionFailure catch (e) {
      _error(e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive(Member member) async {
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.text('archive')),
        content: Text(s.text('archive_member_confirmation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.text('archive')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => _members.archive(member, changedAt: _now));
    if (mounted) context.go('/members');
  }

  Future<void> _resetPin(Member member) async {
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.text('reset_member_pin')),
        content: Text(s.text('reset_member_pin_hint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.text('reset')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      try {
        await _badges.resetMemberPin(member.id);
      } catch (_) {
        // Hors ligne : marquage local synchronisé via l'outbox.
        await _pins.markPinResetRequired(
          member.id,
          ref.read(appRuntimeProvider).session?.gymId ?? '',
        );
      }
    });
  }

  Future<void> _replaceBadge(Member member, BadgeItem old) async {
    final s = AppStrings.of(context);
    final available = await _badges.getAvailableBadges();
    if (!mounted) return;
    if (available.isEmpty) {
      _error('no_badges_available');
      return;
    }
    BadgeItem selected = available.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModal) => AlertDialog(
          title: Text(s.text('replace_badge')),
          content: DropdownButtonFormField<String>(
            initialValue: selected.id,
            decoration: InputDecoration(labelText: s.text('new_badge')),
            items: available
                .map(
                  (b) => DropdownMenuItem(
                    value: b.id,
                    child: Text(b.formattedNumber),
                  ),
                )
                .toList(),
            onChanged: (v) => setModal(
              () => selected = available.firstWhere((b) => b.id == v),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.text('replace_badge')),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await _run(
        () => _badges.replaceBadge(
          oldBadge: old,
          newBadge: selected,
          reason: 'Remplacement depuis la fiche membre',
        ),
      );
    }
  }

  Future<void> _renew(Member member) async {
    final s = AppStrings.of(context);
    final plans = await _plans.watch().first;
    final activePlans = plans
        .where((p) => p.active && p.deletedAt == null)
        .toList();
    if (!mounted) return;
    GymPlan? plan = activePlans.isEmpty ? null : activePlans.first;
    final paid = TextEditingController(
      text: plan?.price.toStringAsFixed(2) ?? '',
    );
    String method = 'cash';
    DateTime start = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(s.text('renew_subscription')),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (activePlans.isEmpty)
                  Text(s.text('plans_empty'))
                else ...[
                  DropdownButtonFormField<GymPlan>(
                    initialValue: plan,
                    decoration: InputDecoration(labelText: s.text('plan')),
                    items: activePlans
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(
                              '${p.name} · ${p.price.toStringAsFixed(2)} ${p.currency}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (p) => setDialog(() {
                      plan = p;
                      paid.text = p?.price.toStringAsFixed(2) ?? '';
                    }),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: start,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 730),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (date != null) setDialog(() => start = date);
                    },
                    icon: const Icon(LucideIcons.calendar),
                    label: Text(
                      '${s.text('start_date')}: ${DateFormat.yMd(Localizations.localeOf(context).toString()).format(start)}',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: paid,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: s.text('paid_amount'),
                    ),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.text('cancel')),
            ),
            FilledButton(
              onPressed: plan == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(s.text('save')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || plan == null) {
      paid.dispose();
      return;
    }
    final amount = double.tryParse(paid.text.replaceAll(',', '.')) ?? 0;
    final selected = plan!;
    paid.dispose();
    if (amount < 0 || amount > selected.price) {
      _error('invalid_record');
      return;
    }
    await _run(
      () => _members
          .renew(
            member,
            selected,
            start: start,
            changedAt: _now,
            payment: amount > 0
                ? PaymentCommand(
                    memberId: member.id,
                    amount: amount,
                    currency: selected.currency,
                    method: method,
                  )
                : null,
          )
          .then((_) {}),
    );
  }

  Future<void> _collect(Member member, GymSubscription subscription) async {
    final s = AppStrings.of(context);
    final payments = await _members.watchPayments(member.id).first;
    if (!mounted) return;
    final paid = payments
        .where((payment) => payment.subscriptionId == subscription.id)
        .fold<double>(0, (total, payment) => total + payment.amount);
    final remaining = subscription.remainingAfter(paid);
    if (remaining <= 0) return;
    final amount = TextEditingController(text: remaining.toStringAsFixed(2));
    String method = 'cash';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(s.text('collect_payment')),
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
    await _run(
      () => _members.collectPayment(
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
        changedAt: _now,
      ),
    );
  }

  Future<void> _cancelSubscription(GymSubscription subscription) async {
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.text('cancel_subscription')),
        content: Text(s.text('cancel_subscription_confirmation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.text('cancel_subscription')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => _subscriptions.cancel(subscription, changedAt: _now));
    }
  }

  Widget _row(String label, String? value) => value == null || value.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 130,
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(child: Text(value)),
            ],
          ),
        );

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final runtime = ref.watch(appRuntimeProvider);
    final role = runtime.session?.role;
    final canManage = {'owner', 'supervisor'}.contains(role);
    final locale = Localizations.localeOf(context).toString();
    return StreamBuilder<Member?>(
      stream: _members.watchMember(widget.memberId),
      builder: (context, memberSnapshot) {
        if (memberSnapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: MessagePanel(message: s.text('local_storage')),
          );
        }
        if (!memberSnapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: LoadingPanel(),
          );
        }
        final member = memberSnapshot.data;
        if (member == null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: MessagePanel(message: s.text('member_missing')),
          );
        }
        return StreamBuilder<List<GymSubscription>>(
          stream: _members.watchSubscriptions(member.id),
          builder: (context, subscriptionSnapshot) {
            final subscriptions = subscriptionSnapshot.data ?? [];
            final validity = memberValidity(
              member,
              subscriptions,
              runtime.session!.settings,
              DateTime.now().toUtc(),
              runtime.session!.timezone,
            );
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 20,
                  runSpacing: 16,
                  children: [
                    Wrap(
                      spacing: 20,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FutureBuilder<Uint8List?>(
                          future: _members.localPhoto(member.id),
                          builder: (context, localPhoto) {
                            if (localPhoto.hasData) {
                              return CircleAvatar(
                                radius: 44,
                                backgroundImage: MemoryImage(localPhoto.data!),
                              );
                            }
                            return FutureBuilder<String?>(
                              future: _members.signedPhotoUrl(member.photoUrl),
                              builder: (context, remote) => CircleAvatar(
                                radius: 44,
                                backgroundImage: remote.data == null
                                    ? null
                                    : NetworkImage(remote.data!),
                                child: remote.data == null
                                    ? Text(
                                        member.firstName.isEmpty
                                            ? '?'
                                            : member.firstName
                                                  .substring(0, 1)
                                                  .toUpperCase(),
                                        style: const TextStyle(fontSize: 28),
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member.fullName,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(
                              '${member.memberNumber} · ${s.text(member.status)}',
                            ),
                            Text(
                              '${s.text('validity')} : ${s.text('validity_${validity.reason}')}${validity.daysLeft == null ? '' : ' · ${validity.daysLeft} ${s.text('days')}'}',
                              style: TextStyle(
                                color: validity.valid
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => context.go('/members/${member.id}/edit'),
                          icon: const Icon(LucideIcons.pencil),
                          label: Text(s.text('edit')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () =>
                                    context.push('/members/${member.id}/badge'),
                          icon: const Icon(LucideIcons.idCard),
                          label: Text(s.text('member_badge')),
                        ),
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _renew(member),
                          icon: const Icon(LucideIcons.refreshCw),
                          label: Text(s.text('renew_subscription')),
                        ),
                        if (canManage)
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'pin') _resetPin(member);
                              if (value == 'suspend') {
                                _run(
                                  () => _members.changeStatus(
                                    member,
                                    'suspended',
                                    changedAt: _now,
                                  ),
                                );
                              }
                              if (value == 'activate') {
                                _run(
                                  () => _members.changeStatus(
                                    member,
                                    'active',
                                    changedAt: _now,
                                  ),
                                );
                              }
                              if (value == 'archive') _archive(member);
                            },
                            itemBuilder: (context) => [
                              if (canManage)
                                PopupMenuItem(
                                  value: 'pin',
                                  child: Text(s.text('reset_member_pin')),
                                ),
                              if (canManage)
                                PopupMenuItem(
                                  value: member.status == 'suspended'
                                      ? 'activate'
                                      : 'suspend',
                                  child: Text(
                                    s.text(
                                      member.status == 'suspended'
                                          ? 'activate'
                                          : 'suspend',
                                    ),
                                  ),
                                ),
                              if (role == 'owner')
                                PopupMenuItem(
                                  value: 'archive',
                                  child: Text(s.text('archive')),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final profile = Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.text('profile'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 18),
                            _row(s.text('phone'), member.phone),
                            _row(s.text('whatsapp'), member.whatsapp),
                            _row(s.text('email'), member.email),
                            _row(
                              s.text('birth_date'),
                              member.birthDate == null
                                  ? null
                                  : DateFormat.yMMMd(
                                      locale,
                                    ).format(member.birthDate!),
                            ),
                            _row(
                              s.text('nif'),
                              member.nif == null
                                  ? null
                                  : formatNif(member.nif!),
                            ),
                            _row(s.text('cin'), member.cin),
                            _row(s.text('address'), member.address),
                            _row(
                              s.text('emergency_name'),
                              member.emergencyName,
                            ),
                            _row(
                              s.text('emergency_phone'),
                              member.emergencyPhone,
                            ),
                            _row(s.text('guardian_name'), member.guardianName),
                            _row(s.text('notes'), member.notes),
                          ],
                        ),
                      ),
                    );
                    final subscriptionsCard = Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.text('subscriptions'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            if (subscriptions.isEmpty)
                              Text(s.text('subscriptions_empty')),
                            for (final subscription in subscriptions.take(8))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${DateFormat.yMd(locale).format(subscription.startDate)} → ${DateFormat.yMd(locale).format(subscription.endDate)} · ${subscription.price.toStringAsFixed(2)}',
                                ),
                                subtitle: Text(
                                  '${s.text(subscription.status)}${subscription.imported ? ' · ${s.text('imported_period')}' : ''}',
                                ),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    if (subscription.status == 'pending')
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _collect(
                                                member,
                                                subscription,
                                              ),
                                        child: Text(s.text('collect_payment')),
                                      ),
                                    if (canManage &&
                                        subscription.status != 'cancelled')
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _cancelSubscription(
                                                subscription,
                                              ),
                                        child: Text(
                                          s.text('cancel_subscription'),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                    return wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: profile),
                              const SizedBox(width: 20),
                              Expanded(child: subscriptionsCard),
                            ],
                          )
                        : Column(
                            children: [
                              profile,
                              const SizedBox(height: 20),
                              subscriptionsCard,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.text('payments'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<List<GymPayment>>(
                          stream: _members.watchPayments(member.id),
                          builder: (context, snapshot) {
                            final payments = snapshot.data ?? [];
                            if (payments.isEmpty) {
                              return Text(s.text('payments_empty'));
                            }
                            return Column(
                              children: [
                                for (final payment in payments.take(10))
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      '${payment.amount.toStringAsFixed(2)} ${payment.currency} · ${s.text('method_${payment.method}')}',
                                    ),
                                    subtitle: Text(
                                      '${DateFormat.yMMMd(locale).add_Hm().format(payment.paidAt.toLocal())}${payment.reference == null ? '' : ' · ${payment.reference}'}',
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.text('badge_section'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(s.text('badge_section_hint')),
                        const SizedBox(height: 16),
                        FutureBuilder<BadgeItem?>(
                          future: _badges.badgeForMember(
                            member.id,
                            badgeId: member.row['badge_id'] as String?,
                          ),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const LoadingPanel();
                            }
                            final badge = snap.data;
                            if (badge == null) {
                              return Text(s.text('member_no_badge'));
                            }
                            return Wrap(
                              spacing: 16,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Chip(
                                  avatar: const Icon(
                                    LucideIcons.idCard,
                                    size: 16,
                                  ),
                                  label: Text(
                                    '${badge.formattedNumber} · ${s.text('badge_status_${badge.status}')}',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => context.push(
                                          '/members/${member.id}/badge',
                                        ),
                                  icon: const Icon(LucideIcons.printer),
                                  label: Text(s.text('print_badge')),
                                ),
                                if (canManage && badge.isBound)
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _replaceBadge(member, badge),
                                    icon: const Icon(LucideIcons.repeat),
                                    label: Text(s.text('replace_badge')),
                                  ),
                                if (canManage && !badge.isBlocked)
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(
                                            () => _badges.blockBadge(
                                              badge,
                                              reason: 'Perte ou vol',
                                            ),
                                          ),
                                    icon: const Icon(LucideIcons.ban),
                                    label: Text(s.text('block_badge')),
                                  ),
                                if (role == 'owner' && badge.isBound)
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(
                                            () => _badges.releaseBadge(
                                              badge,
                                              reason: 'Libération du badge',
                                            ),
                                          ),
                                    icon: const Icon(LucideIcons.lockOpen),
                                    label: Text(s.text('release_badge')),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
