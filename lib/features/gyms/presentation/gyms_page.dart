import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../data/gyms_repository.dart';
import '../domain/gym.dart';

class GymsPage extends ConsumerStatefulWidget {
  const GymsPage({super.key});
  @override
  ConsumerState<GymsPage> createState() => _GymsPageState();
}

class _GymsPageState extends ConsumerState<GymsPage> {
  late final GymsRepository _repository;
  late Future<GymPage> _result;
  int _page = 0;
  bool _archived = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repository = GymsRepository(ref.read(appRuntimeProvider).client);
    _result = _repository.load();
  }

  void _reload() => setState(
    () => _result = _repository.load(page: _page, archived: _archived),
  );

  Future<void> _create() async {
    final created = await context.push<bool>('/gyms/new');
    if (created == true && mounted) {
      _page = 0;
      _archived = false;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('gym_created'))),
      );
    }
  }

  Future<void> _action(Gym gym, String action) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final confirmation = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${s.text(action)} · ${gym.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.text('${action}_confirmation')),
              if (action == 'archive') ...[
                const SizedBox(height: 16),
                Text(gym.code),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmation,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: s.text('confirm_code'),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.text('cancel')),
            ),
            FilledButton(
              onPressed: action == 'archive' && confirmation.text != gym.code
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(s.text(action)),
            ),
          ],
        ),
      ),
    );
    final typed = confirmation.text;
    confirmation.dispose();
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (action == 'reset_owner') {
        await _repository.resetOwnerPassword(gym);
      } else {
        await _repository.changeStatus(
          gym,
          action,
          confirmation: action == 'archive' ? typed : null,
        );
      }
      await HapticFeedback.lightImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.text(action == 'reset_owner' ? 'reset_sent' : 'gym_updated'),
          ),
        ),
      );
      _reload();
    } on PlatformFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text(e.code))));
        if (e.code == 'conflict') _reload();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 24,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    s.text('gyms'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(LucideIcons.plus),
                    label: Text(s.text('new_gym')),
                  ),
                  IconButton(
                    tooltip: s.text('retry'),
                    onPressed: _busy ? null : _reload,
                    icon: const Icon(LucideIcons.refreshCw),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(s.text('platform_online')),
              const SizedBox(height: 12),
              FilterChip(
                label: Text(s.text('archived_gyms')),
                selected: _archived,
                onSelected: _busy
                    ? null
                    : (value) {
                        _archived = value;
                        _page = 0;
                        _reload();
                      },
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: FutureBuilder<GymPage>(
            future: _result,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: LoadingPanel(),
                );
              }
              if (snapshot.hasError) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: MessagePanel(
                    message: s.text(
                      snapshot.error is PlatformFailure
                          ? (snapshot.error as PlatformFailure).code
                          : 'error',
                    ),
                    action: s.text('retry'),
                    onAction: _reload,
                  ),
                );
              }
              final data = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  Wrap(
                    spacing: 40,
                    runSpacing: 20,
                    children: [
                      _stat(s.text('gyms_total'), data.statistics.gyms),
                      _stat(s.text('active_gyms'), data.statistics.activeGyms),
                      _stat(s.text('members'), data.statistics.members),
                      _stat(
                        s.text('entries_today'),
                        data.statistics.entriesToday,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  if (data.gyms.isEmpty)
                    MessagePanel(
                      message: s.text('gyms_empty'),
                      action: s.text('new_gym'),
                      onAction: _create,
                    ),
                  for (final gym in data.gyms)
                    _gymRow(gym, s, data.overviews[gym.id]),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: s.text('previous'),
                        onPressed: _busy || _page == 0
                            ? null
                            : () {
                                _page--;
                                _reload();
                              },
                        icon: const Icon(LucideIcons.chevronLeft),
                      ),
                      Text('${_page + 1}'),
                      IconButton(
                        tooltip: s.text('next'),
                        onPressed: _busy || !data.hasNext
                            ? null
                            : () {
                                _page++;
                                _reload();
                              },
                        icon: const Icon(LucideIcons.chevronRight),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, int value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 4),
      Text(value.toString(), style: Theme.of(context).textTheme.headlineMedium),
    ],
  );

  Widget _gymRow(Gym gym, AppStrings s, GymOverview? overview) {
    final status = gym.archived ? 'archived' : gym.status;
    final color = status == 'active'
        ? const Color(0xff37634d)
        : const Color(0xff855f32);
    final expires = overview?.expiresAt;
    final expiresLabel = expires != null && expires.length >= 10
        ? expires.substring(0, 10)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(gym.name, style: Theme.of(context).textTheme.titleLarge),
              Text(gym.code),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(s.text(status), style: TextStyle(color: color)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${gym.timezone} · ${gym.currency}'),
          if (overview != null) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(LucideIcons.tag, size: 14),
                  label: Text(
                    overview.offerName != null
                        ? '${overview.offerName} · ${overview.offerPrice?.toStringAsFixed(0) ?? ''} ${overview.offerCurrency ?? ''} ${s.text(overview.billingPeriod == 'annual' ? 'per_year' : 'per_month')}'
                        : s.text('no_contract'),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  avatar: const Icon(LucideIcons.users, size: 14),
                  label: Text('${overview.members} ${s.text('members')}'),
                  visualDensity: VisualDensity.compact,
                ),
                if (expiresLabel != null)
                  Chip(
                    avatar: const Icon(LucideIcons.calendarClock, size: 14),
                    label: Text(
                      '${s.text('contract_expires')} : $expiresLabel',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          if (gym.address?.isNotEmpty ?? false) Text(gym.address!),
          if (gym.phone?.isNotEmpty ?? false) Text(gym.phone!),
          if (!gym.archived) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _action(
                          gym,
                          gym.status == 'active' ? 'suspend' : 'reactivate',
                        ),
                  child: Text(
                    s.text(gym.status == 'active' ? 'suspend' : 'reactivate'),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _action(gym, 'reset_owner'),
                  child: Text(s.text('reset_owner')),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _action(gym, 'archive'),
                  child: Text(s.text('archive')),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
