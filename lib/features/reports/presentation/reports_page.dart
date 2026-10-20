import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../payments/domain/currency.dart';
import '../data/report_pdf.dart';
import '../data/reports_repository.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  late final ReportsRepository _repository;
  int _days = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = ReportsRepository(runtime.database!, runtime.session!);
  }

  DateTime get _end => DateTime.now().toUtc();
  DateTime get _start => _end.subtract(Duration(days: _days));

  Future<void> _export(ReportSnapshot snapshot) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() => _busy = true);
    try {
      final gym = ref.read(appRuntimeProvider).session?.gym;
      final bytes = await buildReportPdf(
        snapshot,
        gymName: gym?['name'] as String? ?? 'GymDesk',
        currency: gym?['currency'] as String? ?? 'USD',
        labels: {
          'payments': s.text('payments'),
          'revenue': s.text('revenue'),
          'collected': s.text('collected_by_currency'),
          'entries': s.text('entries_today'),
          'denied': s.text('denied_today'),
          'date': s.text('date'),
          'member': s.text('member'),
          'amount': s.text('amount'),
          'method': s.text('payment_method'),
          'staff': s.text('staff'),
          'reason': s.text('payment_reason'),
          'attendance': s.text('attendance'),
          'result': s.text('result'),
          'entry': s.text('entry_number'),
          'expiring': s.text('expiring_soon'),
          'end': s.text('end_date'),
          'audit': s.text('audit_log'),
          'action': s.text('action'),
          'entity': s.text('entity'),
        },
      );
      try {
        await ref
            .read(appRuntimeProvider)
            .client
            .rpc(
              'audit',
              params: {
                'p_action': 'export',
                'p_entity': 'gyms',
                'p_entity_id': gym?['id'],
                'p_details': {
                  'report': 'operational',
                  'start': snapshot.start.toIso8601String(),
                  'end': snapshot.end.toIso8601String(),
                },
              },
            );
      } catch (_) {}
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'gymdesk-report-${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text('report_export_failed'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendEmailReport(ReportSnapshot report) async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = AppStrings.of(context);
    try {
      final runtime = ref.read(appRuntimeProvider);
      await _repository.sendDailyReportEmail(
        date: _start,
        report: report,
        client: runtime.client,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xff1f6f4a),
            content: Text(s.text('report_sent_email')),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('${s.text('report_send_error')}: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final role = ref.watch(appRuntimeProvider).session?.role;
    final locale = Localizations.localeOf(context).toString();
    final tabCount = role == 'owner' ? 4 : 3;
    return DefaultTabController(
      length: tabCount,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 20,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.text('reports'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(s.text('reports_hint')),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    SegmentedButton<int>(
                      segments: [
                        ButtonSegment(value: 0, label: Text(s.text('today'))),
                        ButtonSegment(
                          value: 6,
                          label: Text(s.text('last_7_days')),
                        ),
                        ButtonSegment(
                          value: 29,
                          label: Text(s.text('last_30_days')),
                        ),
                      ],
                      selected: {_days},
                      onSelectionChanged: (values) =>
                          setState(() => _days = values.first),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TabBar(
            tabs: [
              Tab(text: s.text('summary')),
              Tab(text: s.text('payments')),
              Tab(text: s.text('attendance')),
              if (role == 'owner') Tab(text: s.text('audit_log')),
            ],
          ),
          Expanded(
            child: FutureBuilder<ReportSnapshot>(
              future: _repository.load(start: _start, end: _end),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: MessagePanel(message: s.text('local_storage')),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: LoadingPanel(),
                  );
                }
                final report = snapshot.data!;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Text(
                            '${DateFormat.yMd(locale).format(report.start)} → ${DateFormat.yMd(locale).format(report.end)}',
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: _busy ? null : () => _sendEmailReport(report),
                                icon: const Icon(LucideIcons.mail, size: 16),
                                label: Text(s.text('send_report_email')),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : () => _export(report),
                                icon: const Icon(LucideIcons.fileDown),
                                label: Text(s.text('export_pdf')),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: _paymentsCsv(report)),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(s.text('report_copied')),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(LucideIcons.copy),
                                label: Text(s.text('copy_csv')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _summary(report),
                          _payments(report, locale),
                          _attendance(report, locale),
                          if (role == 'owner') _audit(report, locale),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(ReportSnapshot report) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _line(
        AppStrings.of(context).text('payments'),
        '${report.payments.length}',
      ),
      _line(
        AppStrings.of(context).text('revenue'),
        report.revenue.toStringAsFixed(2),
      ),
      for (final entry in report.registrationCollected.entries)
        if (entry.value > 0)
          _line(
            '${AppStrings.of(context).text('total_registration_fees')} (${entry.key})',
            money(entry.value, entry.key),
          ),
      for (final entry in report.planFeesCollected.entries)
        if (entry.value > 0)
          _line(
            '${AppStrings.of(context).text('total_subscriptions')} (${entry.key})',
            money(entry.value, entry.key),
          ),
      for (final entry in report.collected.entries)
        _line(
          '${AppStrings.of(context).text('collected_by_currency')} (${entry.key})',
          money(entry.value, entry.key),
        ),
      _line(AppStrings.of(context).text('entries_today'), '${report.granted}'),
      _line(AppStrings.of(context).text('denied_today'), '${report.denied}'),
      const SizedBox(height: 20),
      Text(
        AppStrings.of(context).text('expiring_soon'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      if (report.expiring.isEmpty)
        Text(AppStrings.of(context).text('no_expiring')),
      for (final subscription in report.expiring.take(20))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(report.memberName(subscription.memberId)),
          subtitle: Text(
            DateFormat.yMd(
              Localizations.localeOf(context).toString(),
            ).format(subscription.endDate),
          ),
        ),
    ],
  );

  Widget _payments(ReportSnapshot report, String locale) =>
      report.payments.isEmpty
      ? _empty('payments_empty')
      : ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final payment in report.payments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        report.memberName(payment.memberId),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: payment.registrationFee > 0 ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        payment.paymentReason,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: payment.registrationFee > 0 ? const Color(0xFF1D4ED8) : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${DateFormat.yMd(locale).add_Hm().format(payment.paidAt.toLocal())} · ${AppStrings.of(context).text('method_${payment.method}')} · ${report.staffName(payment.receivedBy)}${payment.registrationFee > 0 ? ' · ${AppStrings.of(context).text('registration_fee')} : ${payment.registrationFee.toStringAsFixed(0)} ${payment.currency}' : ''}',
                ),
                trailing: Text(
                  '${payment.amount.toStringAsFixed(2)} ${payment.currency}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        );

  Widget _attendance(ReportSnapshot report, String locale) =>
      report.attendance.isEmpty
      ? _empty('scans_empty')
      : ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final entry in report.attendance)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  entry.result == 'granted'
                      ? LucideIcons.circleCheck
                      : LucideIcons.circleAlert,
                  color: entry.result == 'granted'
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  entry.memberId == null
                      ? AppStrings.of(context).text('unknown_member')
                      : report.memberName(entry.memberId),
                ),
                subtitle: Text(
                  '${DateFormat.yMd(locale).add_Hm().format(entry.scannedAt.toLocal())} · ${AppStrings.of(context).text('scan_${entry.result}')}${entry.wasOffline ? ' · ${AppStrings.of(context).text('offline')}' : ''}',
                ),
                trailing: entry.entryNumberToday == null
                    ? null
                    : Text('#${entry.entryNumberToday}'),
              ),
          ],
        );

  Widget _audit(ReportSnapshot report, String locale) => report.audit.isEmpty
      ? _empty('audit_empty')
      : ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final entry in report.audit)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${entry.action} · ${AppStrings.of(context).text(entry.entity)}',
                ),
                subtitle: Text(
                  '${DateFormat.yMd(locale).add_Hm().format(entry.createdAt.toLocal())} · ${report.staffName(entry.actorId)}',
                ),
              ),
          ],
        );

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
  Widget _empty(String key) => Padding(
    padding: const EdgeInsets.all(24),
    child: MessagePanel(message: AppStrings.of(context).text(key)),
  );

  String _paymentsCsv(ReportSnapshot report) {
    String cell(String? value) => '"${(value ?? '').replaceAll('"', '""')}"';
    return [
      [
        'date',
        'member',
        'reason',
        'amount',
        'registration_fee',
        'plan_fee',
        'currency',
        'paid_currency',
        'paid_amount',
        'exchange_rate',
        'method',
        'staff',
      ].map((v) => cell(v)).join(','),
      ...report.payments.map(
        (payment) => [
          payment.paidAt.toIso8601String(),
          report.memberName(payment.memberId),
          payment.paymentReason,
          payment.amount.toStringAsFixed(2),
          payment.registrationFee.toStringAsFixed(2),
          payment.planFee.toStringAsFixed(2),
          payment.currency,
          payment.paidCurrency,
          payment.paidAmount.toStringAsFixed(2),
          payment.exchangeRate?.toStringAsFixed(4) ?? '',
          payment.method,
          report.staffName(payment.receivedBy),
        ].map(cell).join(','),
      ),
    ].join('\n');
  }
}
