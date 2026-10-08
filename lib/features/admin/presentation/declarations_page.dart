import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../l10n/app_strings.dart';

/// Console super admin : revue des déclarations de paiement des salles
/// et statistiques des essais en cours.
class DeclarationsPage extends ConsumerStatefulWidget {
  const DeclarationsPage({super.key});
  @override
  ConsumerState<DeclarationsPage> createState() => _DeclarationsPageState();
}

class _DeclarationsPageState extends ConsumerState<DeclarationsPage> {
  List<Map<String, dynamic>> _declarations = const [];
  Map<String, int> _gymStats = const {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final decl = await client
          .from('payment_declarations')
          .select('*, gyms(name, code, status)')
          .order('created_at', ascending: false)
          .limit(200);
      final gyms = await client.from('gyms').select('status');
      final stats = <String, int>{};
      for (final g in gyms as List) {
        final status = (g as Map)['status'] as String? ?? 'unknown';
        stats[status] = (stats[status] ?? 0) + 1;
      }
      if (mounted) {
        setState(() {
          _declarations = List<Map<String, dynamic>>.from(decl);
          _gymStats = stats;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'network';
          _loading = false;
        });
      }
    }
  }

  Future<void> _review(Map<String, dynamic> decl, bool approve) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc(
        'review_payment_declaration',
        params: {'p_declaration': decl['id'], 'p_approve': approve},
      );
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'review_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              s.text('declarations_title'),
              style: theme.textTheme.headlineMedium,
            ),
            IconButton(
              onPressed: _busy ? null : _load,
              icon: const Icon(LucideIcons.refreshCw),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final entry in _gymStats.entries)
              Chip(
                avatar: Icon(
                  entry.key == 'trial'
                      ? LucideIcons.hourglass
                      : entry.key == 'active'
                      ? LucideIcons.circleCheck
                      : LucideIcons.circleX,
                  size: 16,
                ),
                label: Text('${s.text('gym_status_${entry.key}')} : ${entry.value}'),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              s.text(_error!),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (_declarations.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(s.text('no_declarations'))),
          )
        else
          for (final d in _declarations) _declarationCard(d, s, theme),
      ],
    );
  }

  Widget _declarationCard(
    Map<String, dynamic> d,
    AppStrings s,
    ThemeData theme,
  ) {
    final gym = d['gyms'] as Map? ?? const {};
    final pending = d['status'] == 'pending';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              d['status'] == 'approved'
                  ? LucideIcons.circleCheck
                  : d['status'] == 'rejected'
                  ? LucideIcons.circleX
                  : LucideIcons.clock,
              color: d['status'] == 'approved'
                  ? Colors.green
                  : d['status'] == 'rejected'
                  ? theme.colorScheme.error
                  : Colors.orange,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${gym['name'] ?? '?'} (${gym['code'] ?? '-'})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${d['amount']} ${d['currency']} · ${s.text('pay_${d['method']}')} · ${d['reference'] ?? ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if ('${d['note'] ?? ''}'.isNotEmpty)
                    Text(
                      '${d['note']}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
            if (pending)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : () => _review(d, false),
                    child: Text(s.text('reject')),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : () => _review(d, true),
                    child: Text(s.text('approve')),
                  ),
                ],
              )
            else
              Text(
                s.text('declaration_${d['status']}'),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
