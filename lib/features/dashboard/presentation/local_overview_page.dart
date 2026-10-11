import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../app/runtime.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../payments/domain/payment.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../data/dashboard_repository.dart';

class LocalOverviewPage extends ConsumerWidget {
  const LocalOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(appRuntimeProvider);
    final s = AppStrings.of(context);

    return ListenableBuilder(
      listenable: runtime,
      builder: (context, _) {
        final db = runtime.database;
        final engine = runtime.sync;

        if (runtime.session?.isPlatformAdmin == true) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: MessagePanel(message: s.text('platform_hint')),
          );
        }
        if (db == null || engine == null || runtime.session == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: LoadingPanel(),
          );
        }
        if (!engine.state.value.initialized) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                s.text('initial_download'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Text(s.text('initial_hint')),
              const SizedBox(height: 24),
              const LoadingPanel(rows: 3),
              LinearProgressIndicator(value: engine.state.value.progress),
              const SizedBox(height: 24),
              if (engine.state.value.errorCode != null)
                Text(s.text(engine.state.value.errorCode!)),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () => context.go('/sync'),
                  child: Text(s.text('sync')),
                ),
              ),
            ],
          );
        }

        final repository = DashboardRepository(db, runtime.session!);
        final gym = runtime.session!.gym ?? const <String, dynamic>{};
        final isTrial = gym['status'] == 'trial';
        final trialEnds = DateTime.tryParse(gym['trial_ends_at'] as String? ?? '');
        final trialDaysLeft = trialEnds == null
            ? 0
            : trialEnds.difference(DateTime.now().toUtc()).inDays.clamp(0, 7);

        final contractConfig = gym['settings'] as Map? ?? {};
        final maxMembers = (contractConfig['max_members'] as num?)?.toInt() ?? 1000;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (isTrial)
              Card(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                child: ListTile(
                  leading: Icon(
                    LucideIcons.hourglass,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    s.text('trial_banner').replaceAll('{n}', '$trialDaysLeft'),
                  ),
                  subtitle: Text(s.text('trial_banner_hint')),
                  trailing: runtime.session!.isOwner
                      ? FilledButton(
                          onPressed: () => context.go('/paywall'),
                          child: Text(s.text('subscribe_now')),
                        )
                      : null,
                ),
              ),
            if (isTrial) const SizedBox(height: 16),

            // Tit & Akèy
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      runtime.session?.name ?? 'GymDesk',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tablo Bò & Jesyon Finansyè an Tan Reyèl',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                ),
                FilledButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => context.go('/members/new'),
                  icon: const Icon(LucideIcons.userPlus, size: 18),
                  label: const Text('Enskri Nouvo Manm'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Metrik Dashboard
            StreamBuilder<DashboardMetrics>(
              stream: repository.watch(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return MessagePanel(message: s.text('local_storage'));
                }
                if (!snapshot.hasData) return const LoadingPanel(rows: 2);
                final metrics = snapshot.data!;
                final currency = runtime.session?.gym?['currency'] as String? ?? 'HTG';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Bannière Kota Manm Aktif
                    _buildQuotaBanner(context, metrics.activeMembers, maxMembers),
                    const SizedBox(height: 16),

                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 1050
                            ? 4
                            : constraints.maxWidth >= 680
                                ? 3
                                : 2;
                        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;

                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _metric(
                              context,
                              width,
                              LucideIcons.users,
                              s.text('active_members'),
                              metrics.activeMembers.toString(),
                              subtitle: 'Klike pou wè tout manm aktif',
                              color: const Color(0xFF047857),
                              onTap: () => context.go('/members?filter=valid'),
                            ),
                            _metric(
                              context,
                              width,
                              LucideIcons.userX,
                              s.text('suspended_members'),
                              metrics.suspendedMembers.toString(),
                              subtitle: 'Klike pou wè manm sispann',
                              color: const Color(0xFFB45309),
                              onTap: () => context.go('/members?filter=suspended'),
                            ),
                            _metric(
                              context,
                              width,
                              LucideIcons.calendarClock,
                              s.text('expiring_soon'),
                              metrics.expiringMembers.toString(),
                              subtitle: 'Klike pou wè abònman k ap fini',
                              color: const Color(0xFFDC2626),
                              onTap: () => context.go('/members?filter=expiring'),
                            ),
                            _metric(
                              context,
                              width,
                              LucideIcons.scanLine,
                              s.text('entries_today'),
                              metrics.entriesToday.toString(),
                              subtitle: 'Antre jodi a pa anprent',
                              color: const Color(0xFF0369A1),
                              onTap: () => context.go('/scan'),
                            ),
                            _metric(
                              context,
                              width,
                              LucideIcons.circleAlert,
                              s.text('denied_today'),
                              metrics.deniedToday.toString(),
                              subtitle: 'Aksè refize jodi a',
                              color: const Color(0xFF991B1B),
                              onTap: () => context.go('/scan'),
                            ),
                            _metric(
                              context,
                              width,
                              LucideIcons.banknote,
                              s.text('payments_today'),
                              metrics.paymentsToday.toString(),
                              subtitle: 'Klike pou wè lis peman jodi a',
                              color: const Color(0xFF4338CA),
                              onTap: () => context.go('/payments'),
                            ),
                            _metric(
                              context,
                              width,
                              LucideIcons.badgeDollarSign,
                              s.text('revenue_today'),
                              '${metrics.revenueToday.toStringAsFixed(2)} $currency',
                              subtitle: 'Klike pou wè detay (Seans, Mensuel...)',
                              color: const Color(0xFF0F766E),
                              onTap: () => _showRevenueBreakdown(context, runtime, currency),
                            ),
                            _metric(
                              context,
                              width,
                              LucideIcons.clock,
                              s.text('pending_subscriptions'),
                              metrics.pendingSubscriptions.toString(),
                              subtitle: 'Renouvèlman an atann apwobasyon',
                              color: const Color(0xFFD97706),
                              onTap: () => context.go('/subscriptions/renewals'),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 32),
            Text(
              s.text('quick_actions'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.go('/scan'),
                  icon: const Icon(LucideIcons.scanLine),
                  label: const Text('Aktivite Pòt & Anprent'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/payments'),
                  icon: const Icon(LucideIcons.banknote),
                  label: Text(s.text('payments')),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/campaigns'),
                  icon: const Icon(LucideIcons.mail),
                  label: const Text('Email & Kanpay'),
                ),
                if ({'owner', 'supervisor'}.contains(runtime.session?.role))
                  OutlinedButton.icon(
                    onPressed: () => context.go('/reports'),
                    icon: const Icon(LucideIcons.chartColumn),
                    label: Text(s.text('reports')),
                  ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/cash'),
                  icon: const Icon(LucideIcons.wallet),
                  label: const Text('Klòti Kès Kesyè'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            ListenableBuilder(
              listenable: engine.state,
              builder: (context, _) {
                final state = engine.state.value;
                return Card(
                  child: ListTile(
                    leading: const Icon(LucideIcons.refreshCw),
                    title: Text(s.text('sync')),
                    subtitle: Text(
                      '${s.text(state.phase == SyncPhase.offline ? 'offline' : state.phase == SyncPhase.running ? 'running' : 'online')} · ${state.pending} ${s.text('pending')} · ${state.failed} ${s.text('failed')}',
                    ),
                    trailing: TextButton(
                      onPressed: () => context.go('/sync'),
                      child: Text(s.text('sync_now')),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuotaBanner(BuildContext context, int active, int max) {
    final s = AppStrings.of(context);
    final pct = max > 0 ? (active / max).clamp(0.0, 1.0) : 0.0;
    final slotsLeft = max > 0 ? (max - active).clamp(0, max) : 9999;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.teal.shade200),
      ),
      color: const Color(0xFFF0FDF4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.shieldCheck, color: Color(0xFF047857), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      s.text('active_quota'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF065F46)),
                    ),
                  ],
                ),
                Text(
                  '$active / $max ${s.text('active_members_label')}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF047857)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: pct >= 0.95 ? Colors.red : const Color(0xFF059669),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ℹ️ ${s.text('active_quota_description')} ($slotsLeft ${s.text('available_slots')}).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    double width,
    IconData icon,
    String label,
    String value, {
    String? subtitle,
    Color? color,
    VoidCallback? onTap,
  }) =>
      SizedBox(
        width: width,
        child: Card(
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(icon, size: 24, color: color ?? Theme.of(context).colorScheme.primary),
                      if (onTap != null)
                        const Icon(LucideIcons.arrowUpRight, size: 16, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );

  Future<void> _showRevenueBreakdown(
    BuildContext context,
    AppRuntime runtime,
    String currency,
  ) async {
    final db = runtime.database;
    if (db == null) return;
    final s = AppStrings.of(context);

    final today = gymDate(DateTime.now().toUtc(), runtime.session!.timezone);
    final rows = await db.watchRecords(SyncEntity.payments, limit: 10000).first;
    final payments = rows
        .map((r) => GymPayment(Map<String, dynamic>.from(jsonDecode(r.payload) as Map)))
        .where((p) => p.deletedAt == null && gymDate(p.paidAt, runtime.session!.timezone) == today)
        .toList();

    // Kalkil pa metòd
    final byMethod = <String, double>{};
    for (final p in payments) {
      byMethod[p.method] = (byMethod[p.method] ?? 0) + p.amount;
    }

    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(s.text('today_revenue_details'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(LucideIcons.x)),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              Text(s.text('payment_by_method_label'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (byMethod.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(s.text('no_payments_today')),
                )
              else
                ...byMethod.entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w500)),
                          Text(
                            '${e.value.toStringAsFixed(2)} $currency',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                          ),
                        ],
                      ),
                    )),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.go('/payments');
                  },
                  icon: const Icon(LucideIcons.externalLink, size: 16),
                  label: Text(s.text('open_all_payments')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
