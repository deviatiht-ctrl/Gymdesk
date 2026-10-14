import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/access_control/terminal_access_service.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../members/presentation/fingerprint_enrollment_dialog.dart';
import '../data/employees_repository.dart';
import '../domain/employee.dart';

const _jobColors = <String, Color>{
  'coach': Color(0xFF0F766E),
  'reception': Color(0xFF2563EB),
  'cleaning': Color(0xFF7C3AED),
  'security': Color(0xFFB91C1C),
  'manager': Color(0xFFB45309),
  'maintenance': Color(0xFF475569),
  'other': Color(0xFF64748B),
};

const _jobIcons = <String, IconData>{
  'coach': LucideIcons.dumbbell,
  'reception': LucideIcons.conciergeBell,
  'cleaning': LucideIcons.sparkles,
  'security': LucideIcons.shieldCheck,
  'manager': LucideIcons.briefcase,
  'maintenance': LucideIcons.wrench,
  'other': LucideIcons.user,
};

class EmployeesPage extends ConsumerStatefulWidget {
  const EmployeesPage({super.key});
  @override
  ConsumerState<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends ConsumerState<EmployeesPage> {
  late final EmployeesRepository _repository;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = EmployeesRepository(runtime.database!, runtime.session!);
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : const Color(0xFF0F766E),
    ));
  }

  Future<void> _edit([Employee? existing]) async {
    final s = AppStrings.of(context);
    final result = await showDialog<_EmployeeFormResult>(
      context: context,
      builder: (_) => _EmployeeFormDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    try {
      final id = await _repository.save(
        existing: existing,
        firstName: result.firstName,
        lastName: result.lastName,
        jobType: result.jobType,
        phone: result.phone,
        email: result.email,
        jobTitle: result.jobTitle,
        notes: result.notes,
        active: result.active,
      );
      unawaited(ref.read(appRuntimeProvider).sync?.synchronize());
      _toast(s.text('employee_saved'));
      if (existing == null && mounted) {
        // Popup anprent lan monte touswit apre kreyasyon an.
        final created = (await _repository.all()).where((e) => e.id == id).firstOrNull;
        if (created != null && mounted) await _enroll(created);
      } else if (existing != null && existing.active != result.active) {
        unawaited(_syncTerminal(silent: true));
      }
    } on EmployeeFailure catch (e) {
      _toast(s.text(e.code), error: true);
    }
  }

  Future<void> _enroll(Employee employee) async {
    final s = AppStrings.of(context);
    await FingerprintEnrollmentDialog.showGeneric(
      context,
      displayName: employee.fullName,
      subtitle: s.text('job_${employee.jobType}'),
      onCaptured: (captures) => _repository.saveFingerprints(employee, captures),
      onSaved: () => unawaited(_syncTerminal(silent: true)),
    );
  }

  Future<void> _archive(Employee employee) async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${s.text('archive_employee')} · ${employee.fullName}'),
        content: Text(s.text('archive_employee_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.text('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.text('archive_employee')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repository.archive(employee);
      unawaited(ref.read(appRuntimeProvider).sync?.synchronize());
      _toast(s.text('employee_archived'));
      unawaited(_syncTerminal(silent: true));
    } on EmployeeFailure catch (e) {
      _toast(s.text(e.code), error: true);
    }
  }

  Future<void> _syncTerminal({bool silent = false}) async {
    if (_syncing) return;
    final s = AppStrings.of(context);
    final runtime = ref.read(appRuntimeProvider);
    setState(() => _syncing = true);
    try {
      final service = TerminalAccessService(runtime.client, runtime.database!, runtime.session!);
      final cfg = await TerminalAccessService.loadConfig(runtime.client, runtime.session!);
      final result = await service.syncToTerminal(cfg);
      if (result.ok && result.enrolled == 0 && result.removed == 0 && result.errors.isEmpty) {
        if (!silent) _toast(s.text('terminal_sync_nothing'));
      } else if (result.ok) {
        _toast(s.text('terminal_sync_done')
            .replaceAll('{n}', '${result.enrolled}')
            .replaceAll('{r}', '${result.removed}'));
      } else if (!silent || !result.errors.contains('agent_offline')) {
        _toast(s.text('terminal_sync_failed'), error: true);
      }
    } catch (_) {
      if (!silent) _toast(s.text('terminal_sync_failed'), error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('employees')),
        actions: [
          TextButton.icon(
            onPressed: _syncing ? null : () => _syncTerminal(),
            icon: _syncing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.refreshCw, size: 18),
            label: Text(s.text('sync_terminal_now')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        onPressed: () => _edit(),
        icon: const Icon(LucideIcons.userPlus),
        label: Text(s.text('new_employee')),
      ),
      body: StreamBuilder<List<Employee>>(
        stream: _repository.watch(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(padding: const EdgeInsets.all(24), child: MessagePanel(message: s.text('local_storage')));
          }
          if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(24), child: LoadingPanel());
          final list = snapshot.data!;
          final withFp = list.where((e) => e.fingerprintRegistered).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
            children: [
              Text(s.text('employees_hint'), style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _MiniStat(icon: LucideIcons.users, label: s.text('employees'), value: '${list.length}', color: const Color(0xFF0F766E)),
                _MiniStat(icon: LucideIcons.fingerprint, label: s.text('fingerprint_ok'), value: '$withFp', color: const Color(0xFF2563EB)),
                _MiniStat(
                  icon: LucideIcons.fingerprintPattern,
                  label: s.text('fingerprint_missing'),
                  value: '${list.length - withFp}',
                  color: Colors.orange.shade700,
                ),
              ]),
              const SizedBox(height: 8),
              Text(s.text('employees_sync_hint'), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              if (list.isEmpty)
                MessagePanel(message: s.text('employees_empty'), action: s.text('new_employee'), onAction: () => _edit())
              else
                for (final e in list) _EmployeeCard(
                  employee: e,
                  onEdit: () => _edit(e),
                  onEnroll: () => _enroll(e),
                  onArchive: () => _archive(e),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 190,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withAlpha(18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ]),
      );
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee, required this.onEdit, required this.onEnroll, required this.onArchive});
  final Employee employee;
  final VoidCallback onEdit;
  final VoidCallback onEnroll;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final color = _jobColors[employee.jobType] ?? _jobColors['other']!;
    final fp = employee.fingerprintRegistered;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 10,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: color.withAlpha(30),
              child: Icon(_jobIcons[employee.jobType] ?? LucideIcons.user, color: color),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 340),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(employee.fullName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  [
                    employee.jobTitle?.isNotEmpty == true ? employee.jobTitle! : s.text('job_${employee.jobType}'),
                    if (employee.phone != null) employee.phone!,
                  ].join(' · '),
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ]),
            ),
            _Chip(
              icon: fp ? LucideIcons.fingerprint : LucideIcons.circleAlert,
              label: s.text(fp ? 'fingerprint_ok' : 'fingerprint_missing'),
              color: fp ? const Color(0xFF15803D) : Colors.orange.shade800,
            ),
            _Chip(
              icon: employee.active ? LucideIcons.doorOpen : LucideIcons.ban,
              label: s.text(employee.active ? 'employee_active' : 'employee_inactive'),
              color: employee.active ? const Color(0xFF0F766E) : Colors.red.shade700,
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              FilledButton.tonalIcon(
                onPressed: onEnroll,
                icon: const Icon(LucideIcons.fingerprint, size: 18),
                label: Text(s.text(fp ? 're_enroll_fingerprint' : 'enroll_fingerprint')),
              ),
              IconButton(tooltip: s.text('edit_employee'), onPressed: onEdit, icon: const Icon(LucideIcons.pencil)),
              IconButton(
                tooltip: s.text('archive_employee'),
                onPressed: onArchive,
                icon: Icon(LucideIcons.trash2, color: Colors.red.shade700),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withAlpha(90)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ]),
      );
}

class _EmployeeFormResult {
  const _EmployeeFormResult({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.jobType,
    required this.jobTitle,
    required this.notes,
    required this.active,
  });
  final String firstName;
  final String lastName;
  final String phone;
  final String email;
  final String jobType;
  final String jobTitle;
  final String notes;
  final bool active;
}

class _EmployeeFormDialog extends StatefulWidget {
  const _EmployeeFormDialog({this.existing});
  final Employee? existing;
  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: widget.existing?.firstName ?? '');
  late final _last = TextEditingController(text: widget.existing?.lastName ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _title = TextEditingController(text: widget.existing?.jobTitle ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late String _job = widget.existing?.jobType ?? 'coach';
  late bool _active = widget.existing?.active ?? true;

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _email, _title, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return AlertDialog(
      title: Text(s.text(widget.existing == null ? 'new_employee' : 'edit_employee')),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _first,
                    autofocus: true,
                    decoration: InputDecoration(labelText: s.text('first_name')),
                    validator: (v) => (v?.trim().isEmpty ?? true) ? s.text('required') : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(controller: _last, decoration: InputDecoration(labelText: s.text('last_name'))),
                ),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _job,
                decoration: InputDecoration(labelText: s.text('job_type')),
                items: [
                  for (final j in Employee.jobTypes)
                    DropdownMenuItem(
                      value: j,
                      child: Row(children: [
                        Icon(_jobIcons[j], size: 18, color: _jobColors[j]),
                        const SizedBox(width: 10),
                        Text(s.text('job_$j')),
                      ]),
                    ),
                ],
                onChanged: (v) => setState(() => _job = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _title, maxLength: 80, decoration: InputDecoration(labelText: s.text('job_title'), counterText: '')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _phone,
                    maxLength: 32,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: s.text('phone'), counterText: ''),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: s.text('email')),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      return t.isEmpty || RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t) ? null : s.text('invalid_email');
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                maxLength: 1000,
                decoration: InputDecoration(labelText: s.text('employee_notes'), counterText: ''),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.text(_active ? 'employee_active' : 'employee_inactive')),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('cancel'))),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              _EmployeeFormResult(
                firstName: _first.text,
                lastName: _last.text,
                phone: _phone.text,
                email: _email.text,
                jobType: _job,
                jobTitle: _title.text,
                notes: _notes.text,
                active: _active,
              ),
            );
          },
          child: Text(s.text('save')),
        ),
      ],
    );
  }
}
