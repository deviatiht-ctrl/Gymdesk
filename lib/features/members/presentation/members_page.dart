import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../data/members_repository.dart';

class MembersPage extends ConsumerStatefulWidget {
  const MembersPage({super.key});
  @override
  ConsumerState<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends ConsumerState<MembersPage> {
  late final MembersRepository _repository;
  final _search = TextEditingController();
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = MembersRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Color _validityColor(MemberValidity validity, ColorScheme colors) =>
      switch (validity.reason) {
        'pending_payment' => Colors.orange,
        'no_subscription' || 'expired' || 'suspended' => colors.error,
        _ => validity.valid ? colors.primary : colors.error,
      };

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final locale = Localizations.localeOf(context).toString();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 20,
            runSpacing: 14,
            children: [
              Text(
                s.text('members'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.go('/members/new'),
                    icon: const Icon(LucideIcons.userPlus),
                    label: Text(s.text('member_without_badge')),
                  ),
                  FilledButton.icon(
                    onPressed: () => context.go('/activate'),
                    icon: const Icon(LucideIcons.idCard),
                    label: Text(s.text('activate_card')),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(LucideIcons.search),
              labelText: s.text('search_members'),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(LucideIcons.x),
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in [
                  'all',
                  'valid',
                  'expiring',
                  'expired',
                  'pending',
                  'none',
                  'suspended',
                ])
                  ChoiceChip(
                    label: Text(s.text('member_filter_$filter')),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<MemberListEntry>>(
            stream: _repository.watch(query: _search.text, filter: _filter),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: MessagePanel(message: s.text('local_storage')),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: LoadingPanel(),
                );
              }
              if (snapshot.data!.isEmpty) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: MessagePanel(
                    message: s.text('members_empty'),
                    action: s.text('activate_card'),
                    onAction: () => context.go('/activate'),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = snapshot.data![index];
                  final member = entry.member;
                  final subscription = entry.subscription;
                  final color = _validityColor(
                    entry.validity,
                    Theme.of(context).colorScheme,
                  );
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    onTap: () => context.go('/members/${member.id}'),
                    leading: CircleAvatar(
                      child: Text(
                        member.firstName.isEmpty
                            ? '?'
                            : member.firstName.substring(0, 1).toUpperCase(),
                      ),
                    ),
                    title: Text(
                      member.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${member.memberNumber}${member.phone == null ? '' : ' · ${member.phone}'}\n${subscription == null ? s.text('no_subscription') : '${subscription.startDate.toLocal().toString().substring(0, 10)} → ${DateFormat.yMd(locale).format(subscription.endDate)} · ${s.text(subscription.status)}'}',
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withAlpha(24),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: color),
                      ),
                      child: Text(
                        s.text('validity_${entry.validity.reason}'),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
