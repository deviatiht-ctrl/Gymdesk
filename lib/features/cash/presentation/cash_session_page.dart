import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../l10n/app_strings.dart';

class CashSessionPage extends ConsumerStatefulWidget {
  const CashSessionPage({super.key});

  @override
  ConsumerState<CashSessionPage> createState() => _CashSessionPageState();
}

class _CashSessionPageState extends ConsumerState<CashSessionPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final bool _canSupervise;

  bool _loading = true;
  String? _loadError;
  Map<String, dynamic>? _currentSession;
  List<Map<String, dynamic>> _sessionPayments = [];

  bool _loadingSupervision = false;
  String? _supervisionError;
  List<Map<String, dynamic>> _openSupervisedSessions = [];
  List<Map<String, dynamic>> _recentSupervisedSessions = [];

  List<Map<String, dynamic>> _closedSessions = [];
  bool _loadingHistory = false;
  String _historyStaffFilter = 'all';

  final _floatController = TextEditingController(text: '0');
  final _countedController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isActing = false;

  String get _currency =>
      (ref.read(appRuntimeProvider).session?.gym?['currency'] as String?) ??
      'HTG';

  double get _openingFloat =>
      (_currentSession?['opening_float'] as num?)?.toDouble() ?? 0.0;

  double get _cashPaymentsTotal {
    var total = 0.0;
    for (final p in _sessionPayments) {
      if ((p['method'] as String?)?.toLowerCase() == 'cash') {
        total += (p['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return total;
  }

  double get _electronicPaymentsTotal {
    var total = 0.0;
    for (final p in _sessionPayments) {
      if ((p['method'] as String?)?.toLowerCase() != 'cash') {
        total += (p['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return total;
  }

  double get _totalCollected => _cashPaymentsTotal + _electronicPaymentsTotal;

  double get _expectedCashTotal => _openingFloat + _cashPaymentsTotal;

  @override
  void initState() {
    super.initState();
    final session = ref.read(appRuntimeProvider).session;
    _canSupervise = session?.canManageGym == true;
    _tabController = TabController(length: _canSupervise ? 3 : 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_canSupervise && _tabController.index == 1) {
        _loadSupervision();
      } else if ((!_canSupervise && _tabController.index == 1) ||
          (_canSupervise && _tabController.index == 2)) {
        if (_closedSessions.isEmpty) _loadHistory();
      }
    });
    _countedController.addListener(() => setState(() {}));
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _floatController.dispose();
    _countedController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadCurrentSession(),
      if (_canSupervise) _loadSupervision(),
      _loadHistory(),
    ]);
  }

  Future<void> _loadCurrentSession() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final session = ref.read(appRuntimeProvider).session;
    final staffId = session?.staffId;
    final gymId = session?.gymId;
    if (staffId == null || gymId == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('cash_sessions')
          .select()
          .eq('gym_id', gymId)
          .eq('staff_id', staffId)
          .eq('status', 'open')
          .order('opened_at', ascending: false)
          .limit(1);

      final openRows = List<Map<String, dynamic>>.from(rows);
      final Map<String, dynamic>? res = openRows.isEmpty ? null : openRows.first;

      var payments = <Map<String, dynamic>>[];
      if (res != null) {
        final openedAt = res['opened_at'] as String?;
        if (openedAt != null) {
          final pRes = await client
              .from('payments')
              .select(
                'id, amount, currency, method, reference, paid_at, payment_reason, member_id',
              )
              .eq('gym_id', gymId)
              .eq('received_by', staffId)
              .gte('paid_at', openedAt)
              .isFilter('voided_at', null)
              .isFilter('deleted_at', null)
              .order('paid_at', ascending: false);
          payments = List<Map<String, dynamic>>.from(pRes);
        }
      }

      if (mounted) {
        setState(() {
          _currentSession = res;
          _sessionPayments = payments;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.toString();
        });
      }
    }
  }

  Future<void> _loadSupervision() async {
    if (!_canSupervise) return;
    final session = ref.read(appRuntimeProvider).session;
    final gymId = session?.gymId;
    final myStaffId = session?.staffId;
    if (gymId == null) return;

    setState(() {
      _loadingSupervision = true;
      _supervisionError = null;
    });

    final client = Supabase.instance.client;
    try {
      List<Map<String, dynamic>> allRows;
      try {
        final rpcRes = await client.rpc('list_gym_cash_sessions');
        allRows = List<Map<String, dynamic>>.from(
          (rpcRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      } on PostgrestException catch (rpcErr) {
        // Repli si la fonction RPC list_gym_cash_sessions n'est pas encore déployée
        if (rpcErr.code != '42883' &&
            rpcErr.code != 'PGRST202' &&
            !rpcErr.message.contains('list_gym_cash_sessions')) {
          rethrow;
        }
        final rawSessions = await client
            .from('cash_sessions')
            .select('*, staff:staff_id(full_name, role, permissions)')
            .eq('gym_id', gymId)
            .order('opened_at', ascending: false)
            .limit(80);
        allRows = <Map<String, dynamic>>[];
        for (final raw in List<Map<String, dynamic>>.from(rawSessions)) {
          final staffMap = raw['staff'] is Map
              ? Map<String, dynamic>.from(raw['staff'] as Map)
              : const <String, dynamic>{};
          final perms = staffMap['permissions'] is Map
              ? Map<String, dynamic>.from(staffMap['permissions'] as Map)
              : const <String, dynamic>{};
          var cashCollected = 0.0;
          var electronicCollected = 0.0;
          var payCount = 0;
          if (raw['status'] == 'open' && raw['opened_at'] != null) {
            final pRows = await client
                .from('payments')
                .select('amount, method')
                .eq('gym_id', gymId)
                .eq('received_by', raw['staff_id'])
                .gte('paid_at', raw['opened_at'])
                .isFilter('voided_at', null)
                .isFilter('deleted_at', null);
            for (final p in List<Map<String, dynamic>>.from(pRows)) {
              payCount++;
              final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
              if ((p['method'] as String?)?.toLowerCase() == 'cash') {
                cashCollected += amt;
              } else {
                electronicCollected += amt;
              }
            }
          }
          final openingFloat = (raw['opening_float'] as num?)?.toDouble() ?? 0.0;
          allRows.add({
            ...raw,
            'staff_name': staffMap['full_name'] ?? 'Personnel',
            'staff_role': staffMap['role'] ?? 'reception',
            'staff_job_title': perms['job_title'] ?? staffMap['role'] ?? 'reception',
            'is_mine': raw['staff_id'] == myStaffId,
            'cash_collected': cashCollected,
            'electronic_collected': electronicCollected,
            'payments_count': payCount,
            'expected_cash': raw['status'] == 'open'
                ? openingFloat + cashCollected
                : (raw['expected_cash'] ?? openingFloat),
          });
        }
      }

      final openList = allRows.where((r) => r['status'] == 'open').toList();
      final recentList = allRows.where((r) => r['status'] != 'open').toList();

      if (mounted) {
        setState(() {
          _openSupervisedSessions = openList;
          _recentSupervisedSessions = recentList;
          _loadingSupervision = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingSupervision = false;
          _supervisionError = e.toString();
        });
      }
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    final session = ref.read(appRuntimeProvider).session;
    final gymId = session?.gymId;
    final staffId = session?.staffId;
    if (gymId == null) {
      setState(() => _loadingHistory = false);
      return;
    }

    try {
      final client = Supabase.instance.client;
      var query = client
          .from('cash_sessions')
          .select('*, staff:staff_id(full_name, role, permissions)')
          .eq('gym_id', gymId)
          .eq('status', 'closed');
      if (!_canSupervise && staffId != null) {
        query = query.eq('staff_id', staffId);
      }
      final res = await query.order('closed_at', ascending: false).limit(80);

      if (mounted) {
        setState(() {
          _closedSessions = List<Map<String, dynamic>>.from(res);
          _loadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _openSession() async {
    final session = ref.read(appRuntimeProvider).session;
    final staffId = session?.staffId;
    final gymId = session?.gymId;
    if (staffId == null || gymId == null) return;

    final floatVal = double.tryParse(_floatController.text.trim().replaceAll(',', '.')) ?? 0.0;
    if (floatVal < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le fond de caisse initial doit être positif ou égal à 0.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _isActing = true);

    try {
      final client = Supabase.instance.client;
      Map<String, dynamic> opened;
      try {
        final rpcRes = await client.rpc(
          'open_cash_session',
          params: {'p_opening_float': floatVal},
        );
        opened = Map<String, dynamic>.from(rpcRes as Map);
      } on PostgrestException catch (rpcErr) {
        if (rpcErr.code != '42883' &&
            rpcErr.code != 'PGRST202' &&
            !rpcErr.message.contains('open_cash_session')) {
          rethrow;
        }
        final res = await client
            .from('cash_sessions')
            .insert({
              'gym_id': gymId,
              'staff_id': staffId,
              'opening_float': floatVal,
              'expected_cash': floatVal,
              'status': 'open',
            })
            .select()
            .single();
        opened = Map<String, dynamic>.from(res);
      }

      if (mounted) {
        setState(() {
          _currentSession = opened;
          _sessionPayments = [];
          _isActing = false;
        });
        await _loadAll();
        if (!mounted) return;
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
          SnackBar(content: Text('Erreur ouverture caisse : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _executeCloseSession({
    required Map<String, dynamic> targetSession,
    required double counted,
    required String notes,
  }) async {
    final client = Supabase.instance.client;
    try {
      final res = await client.rpc('close_cash_session', params: {
        'p_session': targetSession['id'],
        'p_counted': counted,
        'p_notes': notes,
      });
      return Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (rpcErr) {
      if (rpcErr.code != '42883' &&
          rpcErr.code != 'PGRST202' &&
          !rpcErr.message.contains('close_cash_session')) {
        rethrow;
      }
      final gymId = ref.read(appRuntimeProvider).session?.gymId ?? targetSession['gym_id'];
      final staffId = targetSession['staff_id'];
      final openedAt = targetSession['opened_at'];
      final openingFloat = (targetSession['opening_float'] as num?)?.toDouble() ?? 0.0;
      var cashTotal = 0.0;
      if (openedAt != null && staffId != null) {
        final pRows = await client
            .from('payments')
            .select('amount, method')
            .eq('gym_id', gymId)
            .eq('received_by', staffId)
            .gte('paid_at', openedAt)
            .isFilter('voided_at', null)
            .isFilter('deleted_at', null);
        for (final p in List<Map<String, dynamic>>.from(pRows)) {
          if ((p['method'] as String?)?.toLowerCase() == 'cash') {
            cashTotal += (p['amount'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }
      final expected = openingFloat + cashTotal;
      final diff = counted - expected;
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final updated = await client
          .from('cash_sessions')
          .update({
            'closed_at': nowIso,
            'status': 'closed',
            'expected_cash': expected,
            'counted_cash': counted,
            'difference': diff,
            'notes': notes.isEmpty ? null : notes,
            'updated_at': nowIso,
          })
          .eq('id', targetSession['id'])
          .select()
          .single();
      return Map<String, dynamic>.from(updated);
    }
  }

  Future<void> _closeSession() async {
    final s = AppStrings.of(context);
    final session = _currentSession;
    if (session == null) return;

    final counted = double.tryParse(_countedController.text.trim().replaceAll(',', '.'));
    if (counted == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.text('counted_cash')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final diff = counted - _expectedCashTotal;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('close_cash_session')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.text('close_session_confirm')),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Cash attendu :'),
                      Text(
                        '${_expectedCashTotal.toStringAsFixed(2)} $_currency',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Cash compté :'),
                      Text(
                        '${counted.toStringAsFixed(2)} $_currency',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Écart :'),
                      Text(
                        diff == 0
                            ? 'Équilibré (0.00 $_currency)'
                            : diff > 0
                            ? '+${diff.toStringAsFixed(2)} $_currency (Surplus)'
                            : '${diff.toStringAsFixed(2)} $_currency (Déficit)',
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
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.text('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.text('close_cash_session')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActing = true);

    try {
      final closed = await _executeCloseSession(
        targetSession: session,
        counted: counted,
        notes: _notesController.text.trim(),
      );

      if (mounted) {
        final finalDiff = (closed['difference'] as num?)?.toDouble() ?? 0.0;

        setState(() {
          _currentSession = null;
          _sessionPayments = [];
          _countedController.clear();
          _notesController.clear();
          _isActing = false;
        });

        _showClosingSummary(closed, finalDiff);
        await _loadAll();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _closeSupervisedSession(Map<String, dynamic> sess) async {
    final s = AppStrings.of(context);
    final expected = (sess['expected_cash'] as num?)?.toDouble() ?? 0.0;
    final staffName = (sess['staff_name'] as String?) ?? 'Personnel';
    final countedCtrl = TextEditingController(text: expected.toStringAsFixed(2));
    final notesCtrl = TextEditingController(
      text: 'Clôture par supervision (${ref.read(appRuntimeProvider).session?.staff['full_name'] ?? 'Propriétaire'})',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(LucideIcons.shieldCheck, color: Color(0xFF0F766E)),
            const SizedBox(width: 10),
            Expanded(child: Text('Clôturer la caisse de $staffName')),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Espèces attendues dans cette caisse :'),
                    Text(
                      '${expected.toStringAsFixed(2)} $_currency',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: countedCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '${s.text('counted_cash')} ($_currency) *',
                  prefixIcon: const Icon(LucideIcons.coins),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: s.text('notes_optional'),
                  prefixIcon: const Icon(LucideIcons.fileText),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.text('cancel')),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(LucideIcons.lock, size: 16),
            label: Text(s.text('close_cash_session')),
          ),
        ],
      ),
    );

    final counted = double.tryParse(countedCtrl.text.trim().replaceAll(',', '.'));
    final notes = notesCtrl.text.trim();
    countedCtrl.dispose();
    notesCtrl.dispose();

    if (ok != true || counted == null) return;

    setState(() => _isActing = true);
    try {
      final closed = await _executeCloseSession(
        targetSession: sess,
        counted: counted,
        notes: notes,
      );
      if (mounted) {
        setState(() => _isActing = false);
        final diff = (closed['difference'] as num?)?.toDouble() ?? 0.0;
        _showClosingSummary(closed, diff);
        await _loadAll();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur clôture : $e'), backgroundColor: Colors.red),
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
            Text('${s.text('opening_float')}: ${session['opening_float']} $_currency'),
            const SizedBox(height: 6),
            Text('${s.text('expected_cash')}: ${session['expected_cash']} $_currency'),
            const SizedBox(height: 6),
            Text('${s.text('counted_cash')}: ${session['counted_cash']} $_currency'),
            const Divider(height: 24),
            Row(
              children: [
                Text(
                  '${s.text('cash_difference')}: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  diff == 0
                      ? s.text('difference_exact')
                      : diff > 0
                      ? '+${diff.toStringAsFixed(2)} $_currency (${s.text('surplus')})'
                      : '${diff.toStringAsFixed(2)} $_currency (${s.text('deficit')})',
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

  void _showSessionReportDialog(Map<String, dynamic> session) {
    final s = AppStrings.of(context);
    final openedAt = DateTime.tryParse(session['opened_at'] ?? '')?.toLocal();
    final closedAt = DateTime.tryParse(session['closed_at'] ?? '')?.toLocal();
    final staffName = session['staff']?['full_name'] ?? session['staff_name'] ?? 'Caissier';
    final floatVal = (session['opening_float'] as num?)?.toDouble() ?? 0.0;
    final expected = (session['expected_cash'] as num?)?.toDouble() ?? 0.0;
    final counted = (session['counted_cash'] as num?)?.toDouble() ?? 0.0;
    final diff = (session['difference'] as num?)?.toDouble() ?? 0.0;
    final notes = session['notes'] as String?;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(LucideIcons.receiptText, color: Color(0xFF0F766E)),
            SizedBox(width: 10),
            Text('Rapport de Clôture de Caisse'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(LucideIcons.userCheck, size: 20),
                  ),
                  title: Text(
                    staffName.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Ouvert: ${openedAt != null ? DateFormat.yMMMd().add_Hm().format(openedAt) : '-'}\n'
                    'Fermé: ${closedAt != null ? DateFormat.yMMMd().add_Hm().format(closedAt) : '-'}',
                  ),
                ),
                const Divider(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Fond de caisse initial :'),
                          Text(
                            '${floatVal.toStringAsFixed(2)} $_currency',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Espèces théoriques attendues :'),
                          Text(
                            '${expected.toStringAsFixed(2)} $_currency',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Espèces réelles comptées :'),
                          Text(
                            '${counted.toStringAsFixed(2)} $_currency',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const Divider(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Écart de caisse :',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            diff == 0
                                ? 'Équilibré (0.00 $_currency)'
                                : diff > 0
                                ? '+${diff.toStringAsFixed(2)} $_currency (Surplus)'
                                : '${diff.toStringAsFixed(2)} $_currency (Déficit)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
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
                ),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Notes :',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(notes, style: const TextStyle(fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.text('close')),
          ),
        ],
      ),
    );
  }

  String _roleBadgeLabel(String? role, String? jobTitle) {
    if (role == 'owner') return 'Propriétaire';
    if (role == 'supervisor' || role == 'manager') return 'Superviseur';
    return switch (jobTitle) {
      'secretaire' => 'Secrétaire',
      'secretaire_caissiere' => 'Secrétaire & Caissière',
      'caissier' => 'Caissier(ère)',
      _ => 'Réception / Caisse',
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('cash_management')),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            onPressed: _loadAll,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(LucideIcons.wallet, size: 18), text: 'Ma Caisse'),
            if (_canSupervise)
              Tab(
                icon: const Icon(LucideIcons.shieldCheck, size: 18),
                text: 'Supervision (${_openSupervisedSessions.length})',
              ),
            const Tab(icon: Icon(LucideIcons.fileSpreadsheet, size: 18), text: 'Historique & Rapports'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildActiveSessionTab(s),
                if (_canSupervise) _buildSupervisionTab(s),
                _buildHistoryTab(s),
              ],
            ),
    );
  }

  Widget _buildActiveSessionTab(AppStrings s) {
    final otherOpen = _openSupervisedSessions
        .where((r) => r['is_mine'] != true)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loadError != null) ...[
                Card(
                  color: Colors.red.shade50,
                  child: ListTile(
                    leading: const Icon(LucideIcons.circleAlert, color: Colors.red),
                    title: const Text('Impossible de charger votre session de caisse'),
                    subtitle: Text(_loadError!, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: FilledButton(
                      onPressed: _loadCurrentSession,
                      child: const Text('Réessayer'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_canSupervise && otherOpen.isNotEmpty) ...[
                Card(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: const Color(0xFF0F766E).withValues(alpha: 0.25)),
                  ),
                  child: ListTile(
                    leading: const Icon(LucideIcons.eye, color: Color(0xFF0F766E)),
                    title: Text(
                      '${otherOpen.length} autre(s) caisse(s) actuellement ouverte(s) par votre personnel',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      otherOpen
                          .map((e) => '${e['staff_name']} (${((e['expected_cash'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} $_currency)')
                          .join(' · '),
                    ),
                    trailing: TextButton(
                      onPressed: () => _tabController.animateTo(1),
                      child: const Text('Superviser →'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _currentSession == null
                  ? _buildOpenSessionCard(s)
                  : _buildActiveSessionDashboard(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpenSessionCard(AppStrings s) {
    final session = ref.read(appRuntimeProvider).session;
    final staffLabel = session?.isOwner == true
        ? 'Compte Propriétaire : ${session?.staff['full_name'] ?? ''}'
        : 'Opérateur : ${session?.staff['full_name'] ?? ''}';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    LucideIcons.wallet,
                    color: Color(0xFF0F766E),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.text('open_cash_session'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        staffLabel,
                        style: const TextStyle(
                          color: Color(0xFF0F766E),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Démarrez votre session pour enregistrer et suivre les paiements en temps réel',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 36),
            const Text(
              'Fond de caisse initial (Espèces physiques présentes dans le tiroir) :',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _floatController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '${s.text('opening_float')} ($_currency)',
                prefixIcon: const Icon(LucideIcons.banknote),
                hintText: '0.00',
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isActing ? null : _openSession,
                icon: const Icon(LucideIcons.checkCheck),
                label: Text(
                  _isActing ? s.text('saving') : s.text('open_cash_session'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionDashboard(AppStrings s) {
    final sess = _currentSession!;
    final openedAt = DateTime.tryParse(sess['opened_at'] ?? '')?.toLocal();
    final countedVal = double.tryParse(_countedController.text.trim().replaceAll(',', '.')) ?? 0.0;
    final hasCounted = _countedController.text.trim().isNotEmpty;
    final liveDiff = countedVal - _expectedCashTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF059669).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(LucideIcons.circleDot, color: Color(0xFF059669), size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Ma session de caisse OUVERTE',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF059669),
                    ),
                  ),
                ],
              ),
              Text(
                'Ouvert à : ${openedAt != null ? DateFormat.Hm().format(openedAt) : '-'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Live Financial Stats connected to Paiements
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildStatCard(
              title: 'Fond initial',
              amount: '${_openingFloat.toStringAsFixed(2)} $_currency',
              icon: LucideIcons.coins,
              color: Colors.blueGrey,
            ),
            _buildStatCard(
              title: 'Espèces encaissées',
              amount: '+${_cashPaymentsTotal.toStringAsFixed(2)} $_currency',
              icon: LucideIcons.banknote,
              color: const Color(0xFF059669),
            ),
            _buildStatCard(
              title: 'MonCash & Autres',
              amount: '${_electronicPaymentsTotal.toStringAsFixed(2)} $_currency',
              icon: LucideIcons.smartphone,
              color: const Color(0xFF8B5CF6),
            ),
            _buildStatCard(
              title: 'Cash théorique attendu',
              amount: '${_expectedCashTotal.toStringAsFixed(2)} $_currency',
              icon: LucideIcons.shieldCheck,
              color: const Color(0xFF0F766E),
              highlight: true,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // List of payments received in this session
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.receipt, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Paiements reçus durant cette session (${_sessionPayments.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Total : ${_totalCollected.toStringAsFixed(2)} $_currency',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Divider(height: 24),
                if (_sessionPayments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Aucun paiement enregistré pour le moment dans cette session.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _sessionPayments.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final p = _sessionPayments[idx];
                      final pTime = DateTime.tryParse(p['paid_at'] ?? '')?.toLocal();
                      final method = (p['method'] as String?)?.toLowerCase() ?? 'cash';
                      final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
                      final reason = p['payment_reason'] ?? 'Abonnement';

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: method == 'cash'
                              ? const Color(0xFF059669).withValues(alpha: 0.15)
                              : const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                          child: Icon(
                            method == 'cash' ? LucideIcons.banknote : LucideIcons.creditCard,
                            size: 16,
                            color: method == 'cash' ? const Color(0xFF059669) : const Color(0xFF8B5CF6),
                          ),
                        ),
                        title: Text(
                          '$reason · ${amount.toStringAsFixed(2)} ${p['currency'] ?? _currency}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${pTime != null ? DateFormat.Hm().format(pTime) : ''} · Mode : ${method.toUpperCase()}${p['reference'] != null ? ' (${p['reference']})' : ''}',
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: method == 'cash' ? const Color(0xFFDCFCE7) : const Color(0xFFEDE9FE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            method.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: method == 'cash' ? const Color(0xFF15803D) : const Color(0xFF6D28D9),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Clôture Section
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.lock, color: Color(0xFFDC2626), size: 24),
                    const SizedBox(width: 10),
                    Text(
                      s.text('close_cash_session'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Comptez physiquement les billets et pièces dans le tiroir avant de clôturer.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _countedController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '${s.text('counted_cash')} ($_currency) *',
                    prefixIcon: const Icon(LucideIcons.coins),
                    hintText: 'Entrez le montant compté',
                  ),
                ),
                if (hasCounted) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (liveDiff == 0
                              ? const Color(0xFF059669)
                              : liveDiff > 0
                              ? Colors.blue
                              : Colors.red)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: liveDiff == 0
                            ? const Color(0xFF059669)
                            : liveDiff > 0
                            ? Colors.blue
                            : Colors.red,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          liveDiff == 0
                              ? LucideIcons.check
                              : liveDiff > 0
                              ? LucideIcons.trendingUp
                              : LucideIcons.trendingDown,
                          color: liveDiff == 0
                              ? const Color(0xFF059669)
                              : liveDiff > 0
                              ? Colors.blue
                              : Colors.red,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            liveDiff == 0
                                ? 'Caisse parfaitement équilibrée !'
                                : liveDiff > 0
                                ? 'Surplus détecté : +${liveDiff.toStringAsFixed(2)} $_currency'
                                : 'Déficit détecté : ${liveDiff.toStringAsFixed(2)} $_currency',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: liveDiff == 0
                                  ? const Color(0xFF059669)
                                  : liveDiff > 0
                                  ? Colors.blue
                                  : Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  decoration: InputDecoration(
                    labelText: s.text('notes_optional'),
                    hintText: 'Commentaires ou justification d\'écart éventuel',
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isActing ? null : _closeSession,
                    icon: const Icon(LucideIcons.lock),
                    label: Text(
                      _isActing ? s.text('saving') : s.text('close_cash_session'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSupervisionTab(AppStrings s) {
    if (_loadingSupervision) {
      return const Center(child: CircularProgressIndicator());
    }

    var totalExpectedOpen = 0.0;
    var totalCashOpen = 0.0;
    var totalElectronicOpen = 0.0;
    for (final sess in _openSupervisedSessions) {
      totalExpectedOpen += (sess['expected_cash'] as num?)?.toDouble() ?? 0.0;
      totalCashOpen += (sess['cash_collected'] as num?)?.toDouble() ?? 0.0;
      totalElectronicOpen += (sess['electronic_collected'] as num?)?.toDouble() ?? 0.0;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_supervisionError != null) ...[
                Card(
                  color: Colors.red.shade50,
                  child: ListTile(
                    leading: const Icon(LucideIcons.circleAlert, color: Colors.red),
                    title: const Text('Erreur de chargement Supervision'),
                    subtitle: Text(_supervisionError!),
                    trailing: FilledButton(
                      onPressed: _loadSupervision,
                      child: const Text('Réessayer'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildStatCard(
                    title: 'Caisses ouvertes maintenant',
                    amount: '${_openSupervisedSessions.length}',
                    icon: LucideIcons.users,
                    color: _openSupervisedSessions.isEmpty
                        ? Colors.blueGrey
                        : const Color(0xFF059669),
                    highlight: _openSupervisedSessions.isNotEmpty,
                  ),
                  _buildStatCard(
                    title: 'Espèces attendues (total)',
                    amount: '${totalExpectedOpen.toStringAsFixed(2)} $_currency',
                    icon: LucideIcons.wallet,
                    color: const Color(0xFF0F766E),
                  ),
                  _buildStatCard(
                    title: 'Encaissements cash',
                    amount: '+${totalCashOpen.toStringAsFixed(2)} $_currency',
                    icon: LucideIcons.banknote,
                    color: const Color(0xFF059669),
                  ),
                  _buildStatCard(
                    title: 'Électronique (MonCash/Carte)',
                    amount: '${totalElectronicOpen.toStringAsFixed(2)} $_currency',
                    icon: LucideIcons.smartphone,
                    color: const Color(0xFF8B5CF6),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Qui a une caisse ouverte en ce moment',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loadSupervision,
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: const Text('Actualiser'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_openSupervisedSessions.isEmpty)
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(
                      child: Text(
                        'Aucune caisse n\'est ouverte pour le moment dans la salle.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                )
              else
                ..._openSupervisedSessions.map((sess) {
                  final staffName = (sess['staff_name'] as String?) ?? 'Personnel';
                  final isMine = sess['is_mine'] == true;
                  final openedAt = DateTime.tryParse(sess['opened_at']?.toString() ?? '')?.toLocal();
                  final openingFloat = (sess['opening_float'] as num?)?.toDouble() ?? 0.0;
                  final cash = (sess['cash_collected'] as num?)?.toDouble() ?? 0.0;
                  final elec = (sess['electronic_collected'] as num?)?.toDouble() ?? 0.0;
                  final expected = (sess['expected_cash'] as num?)?.toDouble() ?? 0.0;
                  final count = (sess['payments_count'] as num?)?.toInt() ?? 0;
                  final roleLabel = _roleBadgeLabel(
                    sess['staff_role']?.toString(),
                    sess['staff_job_title']?.toString(),
                  );

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: const Color(0xFF059669).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: const Color(0xFF059669).withValues(alpha: 0.15),
                                child: const Icon(
                                  LucideIcons.userCheck,
                                  color: Color(0xFF059669),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          staffName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            roleLabel,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF0F766E),
                                            ),
                                          ),
                                        ),
                                        if (isMine)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: const Text(
                                              'Ma caisse',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.blue,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Ouverte le ${openedAt != null ? DateFormat.yMMMd().add_Hm().format(openedAt) : '-'} · $count paiement(s)',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _isActing ? null : () => _closeSupervisedSession(sess),
                                icon: const Icon(LucideIcons.lock, size: 16),
                                label: const Text('Clôturer'),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Wrap(
                            spacing: 20,
                            runSpacing: 8,
                            children: [
                              Text('Fond initial : ${openingFloat.toStringAsFixed(2)} $_currency'),
                              Text(
                                'Espèces : +${cash.toStringAsFixed(2)} $_currency',
                                style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Électronique : ${elec.toStringAsFixed(2)} $_currency',
                                style: const TextStyle(color: Color(0xFF6D28D9)),
                              ),
                              Text(
                                'Attendu dans le tiroir : ${expected.toStringAsFixed(2)} $_currency',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              if (_recentSupervisedSessions.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'Activité récente (caisses clôturées)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ..._recentSupervisedSessions.take(8).map((sess) {
                  final closedAt = DateTime.tryParse(sess['closed_at']?.toString() ?? '')?.toLocal();
                  final diff = (sess['difference'] as num?)?.toDouble() ?? 0.0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: (diff == 0 ? const Color(0xFF059669) : Colors.orange).withValues(alpha: 0.15),
                      child: Icon(
                        diff == 0 ? LucideIcons.check : LucideIcons.circleAlert,
                        size: 16,
                        color: diff == 0 ? const Color(0xFF059669) : Colors.orange.shade800,
                      ),
                    ),
                    title: Text('${sess['staff_name'] ?? 'Personnel'} · ${((sess['counted_cash'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} $_currency'),
                    subtitle: Text(
                      'Fermée ${closedAt != null ? DateFormat.yMMMd().add_Hm().format(closedAt) : '-'} · Écart: ${diff == 0 ? '0.00' : diff.toStringAsFixed(2)} $_currency',
                    ),
                    trailing: TextButton(
                      onPressed: () => _showSessionReportDialog(sess),
                      child: const Text('Rapport'),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String amount,
    required IconData icon,
    required Color color,
    bool highlight = false,
  }) {
    return Container(
      width: 205,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight ? color.withValues(alpha: 0.12) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? color : Theme.of(context).dividerColor,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            amount,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: highlight ? color : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(AppStrings s) {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    final myStaffId = ref.read(appRuntimeProvider).session?.staffId;
    final visible = _historyStaffFilter == 'mine' && myStaffId != null
        ? _closedSessions.where((e) => e['staff_id'] == myStaffId).toList()
        : _closedSessions;

    if (_closedSessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.fileSpreadsheet, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Aucune session de caisse clôturée pour l\'instant.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              onPressed: _loadHistory,
              label: const Text('Actualiser'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_canSupervise)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                FilterChip(
                  label: Text('Toutes (${_closedSessions.length})'),
                  selected: _historyStaffFilter == 'all',
                  onSelected: (_) => setState(() => _historyStaffFilter = 'all'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Mes caisses'),
                  selected: _historyStaffFilter == 'mine',
                  onSelected: (_) => setState(() => _historyStaffFilter = 'mine'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, idx) {
              final sess = visible[idx];
              final openedAt = DateTime.tryParse(sess['opened_at'] ?? '')?.toLocal();
              final closedAt = DateTime.tryParse(sess['closed_at'] ?? '')?.toLocal();
              final staffMap = sess['staff'] is Map
                  ? Map<String, dynamic>.from(sess['staff'] as Map)
                  : const <String, dynamic>{};
              final staffName = staffMap['full_name'] ?? 'Caissier';
              final expected = (sess['expected_cash'] as num?)?.toDouble() ?? 0.0;
              final counted = (sess['counted_cash'] as num?)?.toDouble() ?? 0.0;
              final diff = (sess['difference'] as num?)?.toDouble() ?? 0.0;

              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: diff == 0
                            ? const Color(0xFF059669).withValues(alpha: 0.15)
                            : diff > 0
                            ? Colors.blue.withValues(alpha: 0.15)
                            : Colors.red.withValues(alpha: 0.15),
                        child: Icon(
                          diff == 0
                              ? LucideIcons.check
                              : diff > 0
                              ? LucideIcons.trendingUp
                              : LucideIcons.trendingDown,
                          color: diff == 0
                              ? const Color(0xFF059669)
                              : diff > 0
                              ? Colors.blue
                              : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Session de $staffName',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Clôturée le : ${closedAt != null ? DateFormat.yMMMd().add_Hm().format(closedAt) : (openedAt != null ? DateFormat.yMMMd().add_Hm().format(openedAt) : '-')}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              children: [
                                Text(
                                  'Attendu: ${expected.toStringAsFixed(2)} $_currency',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Compté: ${counted.toStringAsFixed(2)} $_currency',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Écart: ${diff == 0 ? "0.00" : (diff > 0 ? "+${diff.toStringAsFixed(2)}" : diff.toStringAsFixed(2))} $_currency',
                                  style: TextStyle(
                                    fontSize: 12,
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
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(LucideIcons.fileText, size: 16),
                        onPressed: () => _showSessionReportDialog(sess),
                        label: const Text('Rapport'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
