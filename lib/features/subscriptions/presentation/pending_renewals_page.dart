import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../members/domain/member.dart';
import '../data/subscriptions_repository.dart';
import '../domain/gym_subscription.dart';

class PendingRenewalsPage extends ConsumerStatefulWidget {
  const PendingRenewalsPage({super.key});

  @override
  ConsumerState<PendingRenewalsPage> createState() => _PendingRenewalsPageState();
}

class _PendingRenewalsPageState extends ConsumerState<PendingRenewalsPage> {
  late final SubscriptionsRepository _repository;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = SubscriptionsRepository(runtime.database!, runtime.session!);
  }

  void _toast(String code) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text(code))),
      );
    }
  }

  Future<void> _validate(GymSubscription subscription) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final now = DateTime.now().toUtc();
      await _repository.validateRenewal(subscription, changedAt: now);
      unawaited(
        ref.read(appRuntimeProvider).sync?.synchronize().catchError((e) {
          debugPrint('Sync error on renewal validation: $e');
        }),
      );
      _toast('renewal_validated_success');
    } catch (_) {
      _toast('renewal_validation_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(GymSubscription subscription) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.text('reject_renewal')),
        content: TextField(
          controller: reasonController,
          decoration: InputDecoration(labelText: s.text('reason')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.text('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.text('reject')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _busy = true);
      try {
        final now = DateTime.now().toUtc();
        await _repository.rejectRenewal(
          subscription,
          changedAt: now,
          reason: reasonController.text.trim(),
        );
        unawaited(
          ref.read(appRuntimeProvider).sync?.synchronize().catchError((e) {
            debugPrint('Sync error on renewal rejection: $e');
          }),
        );
        _toast('renewal_rejected');
      } catch (_) {
        _toast('error');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('pending_renewals_title')),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<GymSubscription>>(
          stream: _repository.watch(status: 'pending'),
          builder: (context, snapshot) {
            if (snapshot.hasError) return MessagePanel(message: s.text('local_storage'));
            if (!snapshot.hasData) return const LoadingPanel();

            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return Center(
                child: MessagePanel(
                  message: s.text('no_pending_renewals'),
                  icon: LucideIcons.circleCheck,
                ),
              );
            }

            final db = ref.read(appRuntimeProvider).database!;
            return ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final sub = items[index];
                return FutureBuilder<Member?>(
                  future: db.record(SyncEntity.members, sub.memberId).then((r) =>
                      r == null ? null : Member(jsonDecode(r.payload) as Map<String, dynamic>)),
                  builder: (context, memberSnap) {
                    final member = memberSnap.data;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              child: Text(member?.firstName.isNotEmpty == true
                                  ? member!.firstName[0].toUpperCase()
                                  : '?'),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member?.fullName ?? s.text('unknown_member'),
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '${s.text('period')}: ${sub.startDate.toIso8601String().substring(0, 10)} → ${sub.endDate.toIso8601String().substring(0, 10)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  Text(
                                    '${s.text('amount')}: ${sub.price}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                                  ),
                                ],
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : () => _reject(sub),
                                  icon: const Icon(LucideIcons.x, size: 16),
                                  label: Text(s.text('reject')),
                                ),
                                FilledButton.icon(
                                  onPressed: _busy ? null : () => _validate(sub),
                                  icon: const Icon(LucideIcons.check, size: 16),
                                  label: Text(s.text('validate')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
