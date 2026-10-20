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
import 'fingerprint_transfer_dialog.dart';
import 'members_stats_panel.dart';

class MembersPage extends ConsumerStatefulWidget {
  const MembersPage({super.key});
  @override
  ConsumerState<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends ConsumerState<MembersPage> {
  late final MembersRepository _repository;
  late final Stream<List<MemberListEntry>> _all;
  final _search = TextEditingController();
  String _filter = 'all';
  bool _showStats = true;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = MembersRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
    _all = _repository.watch().asBroadcastStream();
  }

  Map<String, int> _counts(List<MemberListEntry> all) {
    final st = MembersStats.from(all, DateTime.now());
    return {
      'all': st.total,
      'valid': st.active,
      'expiring': st.expiring,
      'expired': st.expired,
      'pending': st.pending,
      'pending_fingerprint': st.noFingerprint,
      'suspended': all.where((e) => e.member.status == 'suspended').length,
    };
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
              OutlinedButton.icon(
                onPressed: () => setState(() => _showStats = !_showStats),
                icon: Icon(_showStats ? LucideIcons.chevronUp : LucideIcons.chartColumn, size: 18),
                label: Text(s.text(_showStats ? 'hide_stats' : 'show_stats')),
              ),
              StreamBuilder<List<MemberListEntry>>(
                stream: _all,
                builder: (context, snapshot) {
                  final entries = snapshot.data ?? const <MemberListEntry>[];
                  return FilledButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: () {
                      FingerprintTransferDialog.show(
                        context,
                        entries: entries,
                        onDone: () {
                          setState(() {});
                        },
                      );
                    },
                    icon: const Icon(LucideIcons.fingerprint, size: 18),
                    label: Text(s.text('fp_transfer_sync')),
                  );
                },
              ),
              if (ref.watch(appRuntimeProvider).session?.canAddMembers ?? true)
                FilledButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: () => context.go('/members/new'),
                  icon: const Icon(LucideIcons.userPlus, size: 18),
                  label: Text(s.text('enroll_new_member')),
                ),
            ],
          ),
        ),
        StreamBuilder<List<MemberListEntry>>(
          stream: _all,
          builder: (context, snapshot) => AnimatedSize(
            duration: const Duration(milliseconds: 250),
            child: _showStats && snapshot.hasData && MediaQuery.sizeOf(context).height >= 700
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: MembersStatsPanel(entries: snapshot.data!),
                  )
                : const SizedBox(width: double.infinity),
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
            child: StreamBuilder<List<MemberListEntry>>(
              stream: _all,
              builder: (context, snapshot) {
                final counts = snapshot.hasData ? _counts(snapshot.data!) : const <String, int>{};
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in [
                      'all',
                      'valid',
                      'expiring',
                      'expired',
                      'pending',
                      'pending_fingerprint',
                      'suspended',
                    ])
                      ChoiceChip(
                        label: Text(
                          '${s.text('member_filter_$filter')}'
                          '${counts[filter] == null ? '' : ' · ${counts[filter]}'}',
                        ),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                  ],
                );
              },
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
                    action: s.text('enroll_new_member'),
                    onAction: () => context.go('/members/new'),
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
                      '${member.memberNumber}${member.phone == null ? '' : ' · ${member.phone}'}\n${subscription == null ? s.text('no_subscription') : '${DateFormat.yMd(locale).format(subscription.startDate)} → ${DateFormat.yMd(locale).format(subscription.endDate)} · ${s.text(subscription.status)}${entry.validity.daysLeft != null && entry.validity.valid ? ' · ${s.text('days_left_n').replaceAll('{n}', '${entry.validity.daysLeft}')}' : ''}'}',
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
