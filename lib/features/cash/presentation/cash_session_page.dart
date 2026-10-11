import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../l10n/app_strings.dart';

class CashSessionPage extends ConsumerStatefulWidget {
  const CashSessionPage({super.key});

  @override
  ConsumerState<CashSessionPage> createState() => _CashSessionPageState();
}

class _CashSessionPageState extends ConsumerState<CashSessionPage> {
  bool _loading = true;
  Map<String, dynamic>? _currentSession;
  final _floatController = TextEditingController(text: '0');
  final _countedController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isActing = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSession();
  }

  Future<void> _loadCurrentSession() async {
    setState(() => _loading = true);
    final session = ref.read(appRuntimeProvider).session;
    final staffId = session?.staffId;
    final gymId = session?.gymId;
    if (staffId == null || gymId == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final client = Supabase.instance.client;
      final res = await client
          .from('cash_sessions')
          .select()
          .eq('gym_id', gymId)
          .eq('staff_id', staffId)
          .eq('status', 'open')
          .maybeSingle();

      if (mounted) {
        setState(() {
          _currentSession = res;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSession() async {
    final session = ref.read(appRuntimeProvider).session;
    final staffId = session?.staffId;
    final gymId = session?.gymId;
    if (staffId == null || gymId == null) return;

    final floatVal = double.tryParse(_floatController.text.trim()) ?? 0;
    setState(() => _isActing = true);

    try {
      final client = Supabase.instance.client;
      final res = await client
          .from('cash_sessions')
          .insert({
            'gym_id': gymId,
            'staff_id': staffId,
            'opening_float': floatVal,
            'status': 'open',
          })
          .select()
          .single();

      if (mounted) {
        setState(() {
          _currentSession = res;
          _isActing = false;
        });
        final s = AppStrings.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.text('cash_opened_success')),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _closeSession() async {
    final s = AppStrings.of(context);
    final session = _currentSession;
    if (session == null) return;

    final counted = double.tryParse(_countedController.text.trim());
    if (counted == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.text('counted_cash')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('close_cash_session')),
        content: Text(s.text('close_session_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.text('close_cash_session')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActing = true);

    try {
      final client = Supabase.instance.client;
      final res = await client.rpc('close_cash_session', params: {
        'p_session': session['id'],
        'p_counted': counted,
        'p_notes': _notesController.text.trim(),
      });

      if (mounted) {
        final closed = Map<String, dynamic>.from(res as Map);
        final diff = (closed['difference'] as num?)?.toDouble() ?? 0;

        setState(() {
          _currentSession = null;
          _isActing = false;
        });

        _showClosingSummary(closed, diff);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showClosingSummary(Map<String, dynamic> session, double diff) {
    final s = AppStrings.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(LucideIcons.checkCheck, color: Color(0xFF059669)),
            const SizedBox(width: 10),
            Text(s.text('cash_closed_success')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.text('opening_float')}: ${session['opening_float']} HTG'),
            const SizedBox(height: 6),
            Text('${s.text('expected_cash')}: ${session['expected_cash']} HTG'),
            const SizedBox(height: 6),
            Text('${s.text('counted_cash')}: ${session['counted_cash']} HTG'),
            const Divider(height: 24),
            Row(
              children: [
                Text('${s.text('cash_difference')}: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  diff == 0
                      ? s.text('difference_exact')
                      : diff > 0
                          ? '+$diff HTG (${s.text('surplus')})'
                          : '$diff HTG (${s.text('deficit')})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: diff == 0
                        ? const Color(0xFF059669)
                        : diff > 0
                            ? Colors.blue
                            : Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.text('finish_btn')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    _countedController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('cash_management')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: _currentSession == null
                      ? _buildOpenSessionCard(s)
                      : _buildActiveSessionCard(s),
                ),
              ),
            ),
    );
  }

  Widget _buildOpenSessionCard(AppStrings s) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.wallet, color: Color(0xFF0F766E), size: 32),
                const SizedBox(width: 12),
                Text(s.text('open_cash_session'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              s.text('opening_float'),
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _floatController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '${s.text('opening_float')} (HTG)',
                prefixIcon: const Icon(LucideIcons.banknote),
                border: const OutlineInputBorder(),
                hintText: '0',
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                ),
                onPressed: _isActing ? null : _openSession,
                icon: const Icon(LucideIcons.check),
                label: Text(_isActing ? s.text('saving') : s.text('open_cash_session')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionCard(AppStrings s) {
    final sess = _currentSession!;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.checkCircle2, color: Color(0xFF059669), size: 32),
                const SizedBox(width: 12),
                Text(s.text('cash_session'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${s.text('opening_float')}:', style: const TextStyle(color: Colors.grey)),
                      Text('${sess['opening_float']} HTG', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${s.text('start_date')}:', style: const TextStyle(color: Colors.grey)),
                      Text(sess['opened_at']?.toString().substring(11, 16) ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(s.text('close_cash_session'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _countedController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '${s.text('counted_cash')} (HTG) *',
                prefixIcon: const Icon(LucideIcons.coins),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: s.text('notes_optional'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                ),
                onPressed: _isActing ? null : _closeSession,
                icon: const Icon(LucideIcons.lock),
                label: Text(_isActing ? s.text('saving') : s.text('close_cash_session')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
