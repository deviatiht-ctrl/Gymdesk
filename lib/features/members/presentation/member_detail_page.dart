import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../badges/data/badges_repository.dart';
import 'package:uuid/uuid.dart';

import '../../payments/data/receipt_pdf.dart';
import '../../payments/domain/payment.dart';
import '../../payments/presentation/collect_payment_dialog.dart';
import '../../payments/presentation/receipt_sheet.dart';
import '../../plans/data/plans_repository.dart';
import '../../plans/domain/plan.dart';
import '../../subscriptions/data/subscriptions_repository.dart';
import '../../subscriptions/domain/gym_subscription.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../data/member_pin_service.dart';
import '../data/members_repository.dart';
import '../domain/member.dart';
import 'fingerprint_enrollment_dialog.dart';
import '../../../core/sync/sync_models.dart';

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

  Future<void> _removeFingerprint(Member member) async {
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retire Anprent'),
        content: Text('Èske w vle efase anprent anrejistre pou ${member.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.text('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.text('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      final runtime = ref.read(appRuntimeProvider);
      try {
        await runtime.client.rpc('remove_member_fingerprint', params: {'p_member': member.id});
      } catch (_) {
        try {
          await runtime.client.from('members').update({
            'fingerprint_template': null,
            'fingerprint_registered': false,
            'updated_at': _now.toIso8601String(),
          }).eq('id', member.id);
        } catch (_) {}
      }
      final updatedRow = {
        ...member.row,
        'fingerprint_template': null,
        'fingerprint_registered': false,
        'updated_at': _now.toIso8601String(),
      };
      await runtime.database?.save(
        SyncEntity.members,
        updatedRow,
        changedAt: _now,
      );
      unawaited(runtime.sync?.synchronize());
    });
  }

  Future<void> _syncMemberDoor(Member member) async {
    if (member.fingerprintTemplate == null || member.fingerprintTemplate!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manb sa a pa gen anprent anrejistre.')),
      );
      return;
    }
    final fstw = ref.read(fstwAccessControlServiceProvider);
    final ok = await fstw.sendUserFingerprint(
      member.id,
      member.fingerprintTemplate!,
      member.fullName,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ok ? const Color(0xff1f6f4a) : Colors.red,
        content: Text(ok
            ? '✅ Anprent senkronize sou Pòt FSTW F30 !'
            : '❌ Pòt la pa reponn. Kòmand anrejistre nan file d\'attente.'),
      ),
    );
  }

  Future<void> _createTempPin(Member member) async {
    final fstw = ref.read(fstwAccessControlServiceProvider);
    final code = '${100000 + (member.id.hashCode.abs() % 900000)}';
    final exp = DateTime.now().add(const Duration(hours: 24));
    await fstw.setTemporaryPin(member.id, code, exp);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kòd PIN Tanporè'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Kòd PIN pou antre nan pòt FSTW F30 jodi a :'),
            const SizedBox(height: 12),
            SelectableText(
              code,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4),
            ),
            const SizedBox(height: 8),
            const Text('Valab pandan 24 èdtan.', style: TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fèmen'),
          ),
        ],
      ),
    );
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
    final received = TextEditingController();
    String method = 'cash';
    var keepCredit = false;
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
                    onChanged: (_) => setDialog(() {}),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: received,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: s.text('amount_received'),
                      hintText: paid.text,
                    ),
                    onChanged: (_) => setDialog(() {}),
                  ),
                  Builder(
                    builder: (context) {
                      final due =
                          double.tryParse(paid.text.replaceAll(',', '.')) ?? 0;
                      final got = double.tryParse(
                        received.text.replaceAll(',', '.'),
                      );
                      final rest = (got ?? due) - due;
                      if (rest <= 0.004) return const SizedBox.shrink();
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.text('keep_change_as_credit')),
                        subtitle: Text('+${rest.toStringAsFixed(2)}'),
                        value: keepCredit,
                        onChanged: (v) =>
                            setDialog(() => keepCredit = v == true),
                      );
                    },
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
      received.dispose();
      return;
    }
    final amount = double.tryParse(paid.text.replaceAll(',', '.')) ?? 0;
    final got = double.tryParse(received.text.replaceAll(',', '.')) ?? amount;
    final selected = plan!;
    paid.dispose();
    received.dispose();
    if (amount < 0 || amount > selected.price) {
      _error('invalid_record');
      return;
    }
    final command = amount > 0
        ? PaymentCommand(
            id: const Uuid().v4(),
            memberId: member.id,
            amount: amount,
            currency: selected.currency,
            method: method,
            receivedAmount: got,
            keepChangeAsCredit: keepCredit,
          )
        : null;
    GymSubscription? created;
    await _run(() async {
      created = await _members.renew(
        member,
        selected,
        start: start,
        changedAt: _now,
        payment: command,
      );
    });
    if (mounted && command != null) {
      await _openReceipt(member, created, command);
    }
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
    final result = await showCollectPaymentDialog(
      context,
      title: '${s.text('collect_payment')} · ${member.fullName}',
      due: remaining,
      balance: member.creditBalance,
    );
    if (result == null || !mounted) return;
    final command = result.command(
      id: const Uuid().v4(),
      memberId: member.id,
      subscriptionId: subscription.id,
      currency:
          ref.read(appRuntimeProvider).session?.gym?['currency']
              as String? ??
          'HTG',
    );
    await _run(
      () => _members
          .collectPayment(subscription, command, changedAt: _now)
          .then((_) {}),
    );
    if (mounted) {
      await _openReceipt(member, subscription, command);
    }
  }

  /// Louvri dyalòg resi a apre yon peman (download / print / email / WhatsApp).
  Future<void> _openReceipt(
    Member member,
    GymSubscription? subscription,
    PaymentCommand command,
  ) async {
    final s = AppStrings.of(context);
    final gym =
        ref.read(appRuntimeProvider).session?.gym ?? const <String, dynamic>{};
    GymPlan? plan;
    for (final p in await _plans.watch().first) {
      if (p.id == subscription?.planId) plan = p;
    }
    if (!mounted) return;
    await showReceiptSheet(
      context,
      ref,
      ReceiptData(
        paymentId: command.id ?? '',
        memberName: member.fullName,
        memberNumber: member.memberNumber,
        planName: plan?.name ?? s.text('plan'),
        amount: command.amount,
        currency: command.currency,
        method: command.method,
        paidAt: _now,
        gymName: gym['name'] as String? ?? 'GymDesk',
        accentColor: gym['accent_color'] as String? ?? '#0F766E',
        periodStart: subscription?.startDate,
        periodEnd: subscription?.endDate,
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
      ),
    );
  }

  /// Re-ouvri resi a pou yon peman nan istorik manm nan.
  Future<void> _receiptForPayment(Member member, GymPayment payment) async {
    final s = AppStrings.of(context);
    final gym =
        ref.read(appRuntimeProvider).session?.gym ?? const <String, dynamic>{};
    GymSubscription? subscription;
    for (final sub in await _subscriptions.watchForMember(member.id).first) {
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
                              : () => FingerprintEnrollmentDialog.show(
                                  context,
                                  member: member,
                                  onSaved: () => setState(() {}),
                                ),
                          icon: const Icon(LucideIcons.fingerprint),
                          label: Text(member.fingerprintRegistered ? 'Mete Ajou Anprent' : 'Enskri Anprent'),
                        ),
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _renew(member),
                          icon: const Icon(LucideIcons.refreshCw),
                          label: Text(s.text('renew_subscription')),
                        ),
                        if (canManage)
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'sync_door') _syncMemberDoor(member);
                              if (value == 'temp_pin') _createTempPin(member);
                              if (value == 'pin') _resetPin(member);
                              if (value == 'fingerprint') {
                                FingerprintEnrollmentDialog.show(
                                  context,
                                  member: member,
                                  onSaved: () => setState(() {}),
                                );
                              }
                              if (value == 'remove_fingerprint') {
                                _removeFingerprint(member);
                              }
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
                                const PopupMenuItem(
                                  value: 'sync_door',
                                  child: Text('🚪 Senkronize ak Pòt FSTW F30'),
                                ),
                              if (canManage)
                                const PopupMenuItem(
                                  value: 'temp_pin',
                                  child: Text('🔑 Jenere PIN Tanporè (1 Jou)'),
                                ),
                              if (canManage)
                                PopupMenuItem(
                                  value: 'fingerprint',
                                  child: Text(s.text('enroll_fingerprint')),
                                ),
                              if (canManage && member.fingerprintRegistered)
                                const PopupMenuItem(
                                  value: 'remove_fingerprint',
                                  child: Text('Retire anprent'),
                                ),
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
                                    trailing: IconButton(
                                      tooltip: s.text('view_receipt'),
                                      icon: const Icon(
                                        LucideIcons.receipt,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          _receiptForPayment(member, payment),
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
                        Row(
                          children: [
                            const Icon(LucideIcons.fingerprint, color: Color(0xFF0F766E), size: 28),
                            const SizedBox(width: 10),
                            Text(
                              'Aksè Byometrik & Anprent',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sistèm anprent dijital pou ouvèti pòt la ak sekirite sal la.',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 14,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(
                              avatar: Icon(
                                member.fingerprintRegistered ? LucideIcons.circleCheck : LucideIcons.alertTriangle,
                                size: 16,
                                color: member.fingerprintRegistered ? const Color(0xFF047857) : const Color(0xFFB45309),
                              ),
                              backgroundColor: member.fingerprintRegistered ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                              label: Text(
                                member.fingerprintRegistered ? 'Anprent Enskri' : 'Pa gen Anprent (Aksè Bloke)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: member.fingerprintRegistered ? const Color(0xFF065F46) : const Color(0xFF92400E),
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => FingerprintEnrollmentDialog.show(
                                        context,
                                        member: member,
                                        onSaved: () => setState(() {}),
                                      ),
                              icon: const Icon(LucideIcons.fingerprint, size: 18),
                              label: Text(member.fingerprintRegistered ? 'Mete Ajou Anprent' : 'Enskri Anprent Kounye a'),
                            ),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final wa = member.whatsapp ?? member.phone ?? '';
                                      if (wa.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Manm sa a pa gen nimewo telefòn oswa WhatsApp.')),
                                        );
                                        return;
                                      }
                                      final activeSub = subscriptions.where((s) => s.status == 'active').firstOrNull;
                                      final msg = Uri.encodeComponent(
                                        'Bonjou ${member.fullName}! Dosye ou nan gym lan aktif.\n'
                                        'Abonman ou valid jiska: ${activeSub != null ? ymd(activeSub.endDate) : 'N/A'}.\n'
                                        'Ou ka pase dwèt ou sou lektè a pou antre!',
                                      );
                                      final url = 'https://wa.me/${wa.replaceAll('+', '').replaceAll(' ', '')}?text=$msg';
                                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                    },
                              icon: const Icon(LucideIcons.messageCircle, size: 16),
                              label: const Text('Voye sou WhatsApp'),
                            ),
                            if (canManage && member.fingerprintRegistered)
                              OutlinedButton.icon(
                                onPressed: _busy ? null : () => _syncMemberDoor(member),
                                icon: const Icon(LucideIcons.refreshCw, size: 16),
                                label: const Text('Senkronize sou Pòt'),
                              ),
                            if (canManage && member.fingerprintRegistered)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                onPressed: _busy ? null : () => _removeFingerprint(member),
                                icon: const Icon(LucideIcons.trash2, size: 16),
                                label: const Text('Retire Anprent'),
                              ),
                          ],
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
                        Row(
                          children: [
                            const Icon(LucideIcons.fingerprint, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              s.text('fingerprint'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: member.fingerprintRegistered
                                    ? const Color(0xff1f6f4a).withValues(alpha: 0.15)
                                    : Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    member.fingerprintRegistered
                                        ? LucideIcons.circleCheck
                                        : LucideIcons.circleAlert,
                                    size: 14,
                                    color: member.fingerprintRegistered
                                        ? const Color(0xff1f6f4a)
                                        : Colors.orange,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    member.fingerprintRegistered
                                        ? s.text('fingerprint_registered')
                                        : s.text('fingerprint_not_registered'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: member.fingerprintRegistered
                                          ? const Color(0xff1f6f4a)
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          member.fingerprintRegistered
                              ? s.text('fingerprint_registered_desc')
                              : s.text('fingerprint_empty_desc'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => FingerprintEnrollmentDialog.show(
                                        context,
                                        member: member,
                                        onSaved: () => setState(() {}),
                                      ),
                              icon: const Icon(LucideIcons.fingerprint, size: 16),
                              label: Text(s.text('enroll_fingerprint')),
                            ),
                            if (member.fingerprintRegistered)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(context).colorScheme.error,
                                ),
                                onPressed: _busy ? null : () => _removeFingerprint(member),
                                icon: const Icon(LucideIcons.trash2, size: 16),
                                label: Text(s.text('remove_fingerprint')),
                              ),
                          ],
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
