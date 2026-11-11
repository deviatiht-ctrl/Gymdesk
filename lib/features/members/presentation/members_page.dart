import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../core/widgets/person_avatar.dart';
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
  final _scrollController = ScrollController();
  Timer? _debounce;
  String _searchQuery = '';
  String _filter = 'all';
  bool _showStats = true;
  int _displayLimit = 60;
  int _lastFilteredCount = 0;

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
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300) {
      if (_displayLimit < _lastFilteredCount) {
        setState(() {
          _displayLimit += 60;
        });
      }
    }
  }

  Map<String, int> _counts(List<MemberListEntry> all) {
    var active = 0;
    var expiring = 0;
    var expired = 0;
    var pending = 0;
    var noFp = 0;
    var suspended = 0;
    for (final e in all) {
      final v = e.validity;
      if (v.valid) {
        active++;
        if ((v.daysLeft ?? 99) <= 7) expiring++;
      } else {
        switch (v.reason) {
          case 'expired':
            expired++;
            break;
          case 'pending_payment':
            pending++;
            break;
          default:
            break;
        }
      }
      if (e.member.status == 'suspended') suspended++;
      if (!e.member.fingerprintRegistered) noFp++;
    }
    return {
      'all': all.length,
      'valid': active,
      'expiring': expiring,
      'expired': expired,
      'pending': pending,
      'pending_fingerprint': noFp,
      'suspended': suspended,
    };
  }

  List<MemberListEntry> _filterEntries(List<MemberListEntry> all) {
    final q = _searchQuery.trim().toLowerCase();
    return all.where((e) {
      if (q.isNotEmpty) {
        final haystack =
            '${e.member.firstName} ${e.member.lastName} ${e.member.memberNumber} ${e.member.phone ?? ''} ${e.member.nif ?? ''}'
                .toLowerCase();
        if (!haystack.contains(q)) return false;
      }
      return switch (_filter) {
        'active' || 'suspended' || 'archived' => e.member.status == _filter,
        'valid' => e.validity.valid,
        'expiring' => e.validity.valid && (e.validity.daysLeft ?? 0) <= 7,
        'expired' => e.validity.reason == 'expired',
        'pending' => e.validity.reason == 'pending_payment',
        'pending_fingerprint' => !e.member.fingerprintRegistered,
        'none' => e.validity.reason == 'no_subscription',
        _ => true,
      };
    }).toList();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final hPad = screenWidth < 600 ? 14.0 : 24.0;

    return StreamBuilder<List<MemberListEntry>>(
      stream: _all,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: EdgeInsets.all(hPad),
            child: MessagePanel(message: s.text('local_storage')),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: LoadingPanel(),
          );
        }

        final allEntries = snapshot.data!;
        final counts = _counts(allEntries);
        final filtered = _filterEntries(allEntries);
        _lastFilteredCount = filtered.length;
        final visibleItems = filtered.take(_displayLimit).toList();

        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 12),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    Text(
                      s.text('members'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _showStats = !_showStats),
                          icon: Icon(_showStats ? LucideIcons.chevronUp : LucideIcons.chartColumn, size: 18),
                          label: Text(s.text(_showStats ? 'hide_stats' : 'show_stats')),
                        ),
                        FilledButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onPressed: () {
                            FingerprintTransferDialog.show(
                              context,
                              entries: allEntries,
                              onDone: () => setState(() {}),
                            );
                          },
                          icon: const Icon(LucideIcons.fingerprint, size: 18),
                          label: Text(s.text('fp_transfer_sync')),
                        ),
                        if (ref.watch(appRuntimeProvider).session?.canAddMembers ?? true)
                          FilledButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            onPressed: () => context.go('/members/new'),
                            icon: const Icon(LucideIcons.userPlus, size: 18),
                            label: Text(s.text('enroll_new_member')),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 250),
                child: _showStats && allEntries.isNotEmpty
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 14),
                        child: MembersStatsPanel(entries: allEntries),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(LucideIcons.search),
                    labelText: s.text('search_members'),
                    isDense: screenWidth < 600,
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(LucideIcons.x),
                            onPressed: () {
                              _search.clear();
                              setState(() {
                                _searchQuery = '';
                                _displayLimit = 60;
                              });
                            },
                          ),
                  ),
                  onChanged: (text) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 150), () {
                      if (mounted && _searchQuery != text) {
                        setState(() {
                          _searchQuery = text;
                          _displayLimit = 60;
                        });
                      }
                    });
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 12),
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
                        'pending_fingerprint',
                        'suspended',
                      ])
                        ChoiceChip(
                          label: Text(
                            '${s.text('member_filter_$filter')}'
                            '${counts[filter] == null ? '' : ' · ${counts[filter]}'}',
                          ),
                          selected: _filter == filter,
                          onSelected: (_) => setState(() {
                            _filter = filter;
                            _displayLimit = 60;
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(hPad),
                  child: MessagePanel(
                    message: s.text('members_empty'),
                    action: s.text('enroll_new_member'),
                    onAction: () => context.go('/members/new'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 16),
                sliver: SliverList.separated(
                  itemCount: visibleItems.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = visibleItems[index];
                    final member = entry.member;
                    final subscription = entry.subscription;
                    final color = _validityColor(
                      entry.validity,
                      Theme.of(context).colorScheme,
                    );
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      onTap: () => context.go('/members/${member.id}'),
                      leading: PersonAvatar(
                        size: 42,
                        personId: member.id,
                        photoUrl: member.photoUrl,
                        name: member.fullName,
                        db: _repository.db,
                        client: _repository.client,
                        backgroundColor: color.withAlpha(24),
                        borderColor: color.withAlpha(110),
                        borderWidth: 1.5,
                        fallbackColor: color,
                      ),
                      title: Text(
                        member.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                            fontSize: screenWidth < 600 ? 11.5 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (filtered.length > _displayLimit)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 32),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _displayLimit += 60),
                      child: Text(
                        '${s.text('show_more')} (${visibleItems.length} / ${filtered.length})',
                      ),
                    ),
                  ),
                ),
              )
            else
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }
}
