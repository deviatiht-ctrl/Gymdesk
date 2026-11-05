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
  bool _loading = true;
  Map<String, dynamic>? _currentSession;
  List<Map<String, dynamic>> _sessionPayments = [];
  List<Map<String, dynamic>> _closedSessions = [];
  bool _loadingHistory = false;

  final _floatController = TextEditingController(text: '0');
  final _countedController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isActing = false;

  double get _openingFloat =>
      (_currentSession?['opening_float'] as num?)?.toDouble() ?? 0.0;

  double get _cashPaymentsTotal {
    double total = 0.0;
    for (final p in _sessionPayments) {
      if ((p['method'] as String?)?.toLowerCase() == 'cash') {
        total += (p['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return total;
  }

  double get _electronicPaymentsTotal {
    double total = 0.0;
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
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _closedSessions.isEmpty) {
        _loadHistory();
      }
    });
    _countedController.addListener(() => setState(() {}));
    _loadCurrentSession();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _floatController.dispose();
    _countedController.dispose();
    _notesController.dispose();
    super.dispose();
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

      List<Map<String, dynamic>> payments = [];
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
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    final session = ref.read(appRuntimeProvider).session;
    final gymId = session?.gymId;
    if (gymId == null) {
      setState(() => _loadingHistory = false);
      return;
    }

    try {
      final client = Supabase.instance.client;
      final res = await client
          .from('cash_sessions')
          .select('*, staff:staff_id(full_name)')
          .eq('gym_id', gymId)
          .eq('status', 'closed')
          .order('closed_at', ascending: false)
          .limit(60);

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
          _sessionPayments = [];
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
                        '${_expectedCashTotal.toStringAsFixed(2)} HTG',
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
                        '${counted.toStringAsFixed(2)} HTG',
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
                            ? 'Équilibré (0.00 HTG)'
                            : diff > 0
                            ? '+${diff.toStringAsFixed(2)} HTG (Surplus)'
                            : '${diff.toStringAsFixed(2)} HTG (Déficit)',
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
      final client = Supabase.instance.client;
      final res = await client.rpc('close_cash_session', params: {
        'p_session': session['id'],
        'p_counted': counted,
        'p_notes': _notesController.text.trim(),
      });

      if (mounted) {
        final closed = Map<String, dynamic>.from(res as Map);
        final finalDiff = (closed['difference'] as num?)?.toDouble() ?? 0;

        setState(() {
          _currentSession = null;
          _sessionPayments = [];
          _isActing = false;
        });

        _showClosingSummary(closed, finalDiff);
        _loadHistory();
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
                Text(
                  '${s.text('cash_difference')}: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
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

  void _showSessionReportDialog(Map<String, dynamic> session) {
    final s = AppStrings.of(context);
    final openedAt = DateTime.tryParse(session['opened_at'] ?? '')?.toLocal();
    final closedAt = DateTime.tryParse(session['closed_at'] ?? '')?.toLocal();
    final staffName = session['staff']?['full_name'] ?? 'Caissier';
    final float = (session['opening_float'] as num?)?.toDouble() ?? 0;
    final expected = (session['expected_cash'] as num?)?.toDouble() ?? 0;
    final counted = (session['counted_cash'] as num?)?.toDouble() ?? 0;
    final diff = (session['difference'] as num?)?.toDouble() ?? 0;
    final notes = session['notes'] as String?;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(LucideIcons.receiptText, color: Color(0xFF0F766E)),
            const SizedBox(width: 10),
            const Text('Rapport de Clôture de Caisse'),
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
                    staffName,
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
                            '${float.toStringAsFixed(2)} HTG',
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
                            '${expected.toStringAsFixed(2)} HTG',
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
                            '${counted.toStringAsFixed(2)} HTG',
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
                                ? 'Équilibré (0.00 HTG)'
                                : diff > 0
                                ? '+${diff.toStringAsFixed(2)} HTG (Surplus)'
                                : '${diff.toStringAsFixed(2)} HTG (Déficit)',
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
                  Text(
                    'Notes :',
                    style: const TextStyle(fontWeight: FontWeight.bold),
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
            onPressed: () {
              _loadCurrentSession();
              _loadHistory();
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(LucideIcons.wallet, size: 18), text: 'Session en cours'),
            Tab(icon: Icon(LucideIcons.fileSpreadsheet, size: 18), text: 'Historique & Rapports'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildActiveSessionTab(s),
                _buildHistoryTab(s),
              ],
            ),
    );
  }

  Widget _buildActiveSessionTab(AppStrings s) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _currentSession == null
              ? _buildOpenSessionCard(s)
              : _buildActiveSessionDashboard(s),
        ),
      ),
    );
  }

  Widget _buildOpenSessionCard(AppStrings s) {
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
                    color: const Color(0xFF0F766E).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    LucideIcons.wallet,
                    color: Color(0xFF0F766E),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
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
                    const Text(
                      'Démarrez votre session pour enregistrer et suivre les paiements',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
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
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '${s.text('opening_float')} (HTG)',
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
    final countedVal = double.tryParse(_countedController.text.trim()) ?? 0.0;
    final hasCounted = _countedController.text.trim().isNotEmpty;
    final liveDiff = countedVal - _expectedCashTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF059669).withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF059669).withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.circleDot, color: Color(0xFF059669), size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Session de caisse OUVERTE',
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
              amount: '${_openingFloat.toStringAsFixed(2)} HTG',
              icon: LucideIcons.coins,
              color: Colors.blueGrey,
            ),
            _buildStatCard(
              title: 'Espèces encaissées',
              amount: '+${_cashPaymentsTotal.toStringAsFixed(2)} HTG',
              icon: LucideIcons.banknote,
              color: const Color(0xFF059669),
            ),
            _buildStatCard(
              title: 'MonCash & Autres',
              amount: '${_electronicPaymentsTotal.toStringAsFixed(2)} HTG',
              icon: LucideIcons.smartphone,
              color: const Color(0xFF8B5CF6),
            ),
            _buildStatCard(
              title: 'Cash théorique attendu',
              amount: '${_expectedCashTotal.toStringAsFixed(2)} HTG',
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
                      'Total : ${_totalCollected.toStringAsFixed(2)} HTG',
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
                      final amount = (p['amount'] as num?)?.toDouble() ?? 0;
                      final reason = p['payment_reason'] ?? 'Abonnement';

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: method == 'cash'
                              ? const Color(0xFF059669).withOpacity(0.15)
                              : const Color(0xFF8B5CF6).withOpacity(0.15),
                          child: Icon(
                            method == 'cash' ? LucideIcons.banknote : LucideIcons.creditCard,
                            size: 16,
                            color: method == 'cash' ? const Color(0xFF059669) : const Color(0xFF8B5CF6),
                          ),
                        ),
                        title: Text(
                          '$reason · ${amount.toStringAsFixed(2)} ${p['currency'] ?? 'HTG'}',
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
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '${s.text('counted_cash')} (HTG) *',
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
                          .withOpacity(0.1),
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
                                ? 'Surplus détecté : +${liveDiff.toStringAsFixed(2)} HTG'
                                : 'Déficit détecté : ${liveDiff.toStringAsFixed(2)} HTG',
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

  Widget _buildStatCard({
    required String title,
    required String amount,
    required IconData icon,
    required Color color,
    bool highlight = false,
  }) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight ? color.withOpacity(0.12) : Theme.of(context).cardColor,
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

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _closedSessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, idx) {
        final sess = _closedSessions[idx];
        final openedAt = DateTime.tryParse(sess['opened_at'] ?? '')?.toLocal();
        final closedAt = DateTime.tryParse(sess['closed_at'] ?? '')?.toLocal();
        final staffName = sess['staff']?['full_name'] ?? 'Caissier';
        final expected = (sess['expected_cash'] as num?)?.toDouble() ?? 0;
        final counted = (sess['counted_cash'] as num?)?.toDouble() ?? 0;
        final diff = (sess['difference'] as num?)?.toDouble() ?? 0;

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: diff == 0
                      ? const Color(0xFF059669).withOpacity(0.15)
                      : diff > 0
                      ? Colors.blue.withOpacity(0.15)
                      : Colors.red.withOpacity(0.15),
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
                            'Attendu: ${expected.toStringAsFixed(2)} HTG',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'Compté: ${counted.toStringAsFixed(2)} HTG',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Écart: ${diff == 0 ? "0.00" : (diff > 0 ? "+$diff" : "$diff")} HTG',
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
    );
  }
}
