import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/sync/sync_models.dart';
import '../../../l10n/app_strings.dart';
import '../../members/domain/member.dart';

/// Paywall affiché à tous les rôles quand la salle est suspendue
/// (essai expiré ou paiement non validé). L'export des données reste
/// disponible ; l'accès se débloque dès que le serveur valide.
class PaywallPage extends ConsumerStatefulWidget {
  const PaywallPage({super.key});
  @override
  ConsumerState<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends ConsumerState<PaywallPage> {
  Map<String, dynamic> _instructions = const {};
  bool _busy = false;
  bool _declared = false;
  String? _error;
  Timer? _poll;
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  String _method = 'moncash';

  @override
  void initState() {
    super.initState();
    _load();
    // Le statut redevient accessible au prochain contact réseau :
    // on rafraîchit la session régulièrement sans réinstaller l'app.
    _poll = Timer.periodic(
      const Duration(seconds: 60),
      (_) => ref.read(appRuntimeProvider).refresh(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('platform_settings')
          .select('value')
          .eq('key', 'payment_instructions')
          .maybeSingle();
      if (mounted && rows != null) {
        setState(
          () => _instructions = Map<String, dynamic>.from(
            rows['value'] as Map? ?? {},
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _declarePayment() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0;
    if (amount <= 0 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.from('payment_declarations').insert({
        'gym_id': ref.read(appRuntimeProvider).session?.gymId,
        'method': _method,
        'reference': _reference.text.trim(),
        'amount': amount,
        'currency': 'USD',
      });
      if (mounted) setState(() => _declared = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'declaration_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = AppStrings.of(context);
    try {
      final db = ref.read(appRuntimeProvider).database;
      if (db == null) throw StateError('no_db');
      final memberRows = await db
          .watchRecords(SyncEntity.members, limit: 50000)
          .first;
      final members = memberRows
          .map(
            (r) => Member(
              Map<String, dynamic>.from(jsonDecode(r.payload) as Map),
            ),
          )
          .toList();
      final gym = ref.read(appRuntimeProvider).session?.name ?? 'GymDesk';
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '$gym — ${s.text('export_members')}',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: [
                  s.text('member_number'),
                  s.text('full_name'),
                  s.text('phone'),
                  s.text('status'),
                ],
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerStyle: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
                data: members
                    .map(
                      (m) => [
                        m.memberNumber,
                        m.fullName,
                        m.phone,
                        m.status,
                      ],
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      );
      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'gymdesk-export.pdf',
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'export_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final runtime = ref.watch(appRuntimeProvider);
    final gym = runtime.session?.gym ?? const {};
    final isOwner = runtime.session?.isOwner == true;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  LucideIcons.lock,
                  size: 56,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  s.text('paywall_title'),
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '${gym['name'] ?? ''} · ${s.text('paywall_suspended')}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.text('payment_instructions'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        for (final key in [
                          'moncash',
                          'natcash',
                          'bank',
                          'contact_phone',
                          'whatsapp',
                          'email',
                        ])
                          if ('${_instructions[key] ?? ''}'.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 3,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      s.text('pay_$key'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: SelectableText(
                                      '${_instructions[key]}',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (isOwner && !_declared)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.text('i_paid'),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _method,
                            decoration: InputDecoration(
                              labelText: s.text('payment_method'),
                            ),
                            items:
                                ['moncash', 'natcash', 'bank', 'cash', 'other']
                                    .map(
                                      (m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(s.text('pay_$m')),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (v) =>
                                setState(() => _method = v ?? 'moncash'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _amount,
                            decoration: InputDecoration(
                              labelText: s.text('amount'),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _reference,
                            decoration: InputDecoration(
                              labelText: s.text('payment_reference'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _busy ? null : _declarePayment,
                            icon: const Icon(LucideIcons.send),
                            label: Text(s.text('send_declaration')),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_declared)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.clock,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(s.text('declaration_pending'))),
                        ],
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      s.text(_error!),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _export,
                      icon: const Icon(LucideIcons.fileDown),
                      label: Text(s.text('export_data')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => ref.read(appRuntimeProvider).refresh(),
                      icon: const Icon(LucideIcons.refreshCw),
                      label: Text(s.text('check_status')),
                    ),
                    TextButton.icon(
                      onPressed: () => ref.read(appRuntimeProvider).signOut(),
                      icon: const Icon(LucideIcons.logOut),
                      label: Text(s.text('sign_out')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
