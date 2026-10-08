import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
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
        final trialEnds = DateTime.tryParse(
          gym['trial_ends_at'] as String? ?? '',
        );
        final trialDaysLeft = trialEnds == null
            ? 0
            : trialEnds.difference(DateTime.now().toUtc()).inDays.clamp(0, 7);
        final newGym = gym['onboarding_done'] != true;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (isTrial)
              Card(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.06),
                child: ListTile(
                  leading: Icon(
                    LucideIcons.hourglass,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    s
                        .text('trial_banner')
                        .replaceAll('{n}', '$trialDaysLeft'),
                  ),
                  subtitle: Text(s.text('trial_banner_hint')),
                  trailing:
                      runtime.session!.isOwner
                          ? FilledButton(
                              onPressed: () => context.go('/paywall'),
                              child: Text(s.text('subscribe_now')),
                            )
                          : null,
                ),
              ),
            if (isTrial) const SizedBox(height: 16),
            Text(
              s.text('home'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(s.text('local_data_hint')),
            const SizedBox(height: 24),
            StreamBuilder<DashboardMetrics>(
              stream: repository.watch(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return MessagePanel(message: s.text('local_storage'));
                }
                if (!snapshot.hasData) return const LoadingPanel(rows: 2);
                final metrics = snapshot.data!;
                final currency =
                    runtime.session?.gym?['currency'] as String? ?? 'HTG';
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1050
                        ? 4
                        : constraints.maxWidth >= 680
                        ? 3
                        : 2;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 12) / columns;
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
                        ),
                        _metric(
                          context,
                          width,
                          LucideIcons.userX,
                          s.text('suspended_members'),
                          metrics.suspendedMembers.toString(),
                        ),
                        _metric(
                          context,
                          width,
                          LucideIcons.calendarClock,
                          s.text('expiring_soon'),
                          metrics.expiringMembers.toString(),
                        ),
                        _metric(
                          context,
                          width,
                          LucideIcons.scanLine,
                          s.text('entries_today'),
                          metrics.entriesToday.toString(),
                        ),
                        _metric(
                          context,
                          width,
                          LucideIcons.circleAlert,
                          s.text('denied_today'),
                          metrics.deniedToday.toString(),
                        ),
                        _metric(
                          context,
                          width,
                          LucideIcons.banknote,
                          s.text('payments_today'),
                          metrics.paymentsToday.toString(),
                        ),
                        _metric(
                          context,
                          width,
                          LucideIcons.badgeDollarSign,
                          s.text('revenue_today'),
                          '${metrics.revenueToday.toStringAsFixed(2)} $currency',
                        ),
                        _metric(
                          context,
                          width,
                          LucideIcons.clock,
                          s.text('pending_subscriptions'),
                          metrics.pendingSubscriptions.toString(),
                        ),
                        _metric(
                          context,
                          width,
                          LucideIcons.wallet,
                          s.text('pending_amount'),
                          '${metrics.pendingAmount.toStringAsFixed(2)} $currency',
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            if (newGym) ...[
              const SizedBox(height: 24),
              _Checklist(s: s, theme: Theme.of(context)),
            ],
            const SizedBox(height: 32),
            Text(
              s.text('quick_actions'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/scan'),
                  icon: const Icon(LucideIcons.scanLine),
                  label: Text(s.text('scan')),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/members/new'),
                  icon: const Icon(LucideIcons.userPlus),
                  label: Text(s.text('new_member')),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/payments'),
                  icon: const Icon(LucideIcons.banknote),
                  label: Text(s.text('payments')),
                ),
                if ({'owner', 'supervisor'}.contains(runtime.session?.role))
                  OutlinedButton.icon(
                    onPressed: () => context.go('/reports'),
                    icon: const Icon(LucideIcons.chartColumn),
                    label: Text(s.text('reports')),
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
                      '${s.text(state.phase == SyncPhase.offline
                          ? 'offline'
                          : state.phase == SyncPhase.running
                          ? 'running'
                          : 'online')} · ${state.pending} ${s.text('pending')} · ${state.failed} ${s.text('failed')}',
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

  Widget _metric(
    BuildContext context,
    double width,
    IconData icon,
    String label,
    String value,
  ) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Checklist de démarrage pour une salle fraîchement inscrite.
class _Checklist extends StatelessWidget {
  const _Checklist({required this.s, required this.theme});
  final AppStrings s;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.text('getting_started'), style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          _item(
            context,
            LucideIcons.palette,
            'checklist_branding',
            '/settings/branding',
          ),
          _item(
            context,
            LucideIcons.creditCard,
            'checklist_print_badges',
            '/badges',
          ),
          _item(
            context,
            LucideIcons.idCard,
            'checklist_activate',
            '/activate',
          ),
          _item(
            context,
            LucideIcons.users,
            'checklist_staff',
            '/settings/staff',
          ),
        ],
      ),
    ),
  );

  Widget _item(
    BuildContext context,
    IconData icon,
    String key,
    String path,
  ) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, size: 20, color: theme.colorScheme.primary),
    title: Text(s.text(key)),
    trailing: const Icon(LucideIcons.chevronRight, size: 18),
    onTap: () => context.go(path),
  );
}
