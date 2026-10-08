import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../l10n/app_strings.dart';
import '../../auth/presentation/login_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(appRuntimeProvider);
    final s = AppStrings.of(context);
    final session = runtime.session;
    final platform = session?.isPlatformAdmin == true;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          s.text('settings'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: const LanguagePicker(),
        ),
        const SizedBox(height: 32),
        Text(
          s.text('more_pages'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if ({'owner', 'supervisor'}.contains(session?.role)) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.creditCard),
            title: Text(s.text('badges')),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.push('/badges'),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.clipboardCheck),
            title: Text(s.text('pending_renewals_title')),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.push('/subscriptions/renewals'),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.chartColumn),
            title: Text(s.text('reports')),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.push('/reports'),
          ),
          const Divider(height: 1),
        ],
        if (platform) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.tag),
            title: Text(s.text('offers_catalog')),
            subtitle: Text(s.text('offers_catalog_hint')),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.push('/admin/offers'),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.clipboardCheck),
            title: Text(s.text('declarations_title')),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.push('/admin/declarations'),
          ),
          const Divider(height: 1),
        ] else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.badgeDollarSign),
            title: Text(s.text('plans')),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.push('/plans'),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.banknote),
            title: Text(s.text('payments')),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.push('/payments'),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.refreshCw),
            title: Text(s.text('sync')),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.push('/sync'),
          ),
        ],
        if (session?.role == 'owner') ...[
          const SizedBox(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.palette),
            title: Text(s.text('gym_settings')),
            subtitle: Text(
              '${s.text('name')} · ${s.text('logo')} · ${s.text('operational_settings')}',
            ),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.push('/settings/branding'),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.users),
            title: Text(s.text('staff')),
            subtitle: Text(s.text('staff_hint')),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.push('/settings/staff'),
          ),
        ],
        if ({'owner', 'supervisor'}.contains(session?.role)) ...[
          const SizedBox(height: 32),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.idCard),
            title: Text(s.text('badge_templates')),
            subtitle: Text(s.text('badge_templates_hint')),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.push('/settings/badges'),
          ),
        ],
        const SizedBox(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(LucideIcons.lockKeyhole),
          title: Text(s.text('pin')),
          subtitle: Text(s.text('pin_security')),
          trailing: const Icon(LucideIcons.chevronRight),
          onTap: () => context.push('/settings/pin'),
        ),
        const SizedBox(height: 32),
        Text(s.text('account'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(session?.staff['full_name'] as String? ?? ''),
        Text('${s.text('role')}: ${s.text(session?.role ?? 'error')}'),
        const SizedBox(height: 24),
        Text(s.text('offline_policy')),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(s.text('sign_out')),
                  content: Text(s.text('logout_confirmation')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(s.text('cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(s.text('sign_out')),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await runtime.signOut();
            },
            child: Text(s.text('sign_out')),
          ),
        ),
        const SizedBox(height: 48),
        const Text('Designed by Cvisual'),
      ],
    );
  }
}
