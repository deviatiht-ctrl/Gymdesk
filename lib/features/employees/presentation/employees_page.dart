import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/access_control/terminal_access_service.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../l10n/app_strings.dart';
import '../../members/data/member_photo_codec.dart';
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
    _repository = EmployeesRepository(
      runtime.database!,
      runtime.session!,
      client: runtime.client,
    );
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : const Color(0xFF0F766E),
    ));
  }

  Future<void> _showProfile(Employee employee) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _EmployeeProfileDialog(
        employee: employee,
        repository: _repository,
        onEdit: () {
          Navigator.pop(context);
          _edit(employee);
        },
        onEnroll: () {
          Navigator.pop(context);
          _enroll(employee);
        },
        onArchive: () {
          Navigator.pop(context);
          _archive(employee);
        },
      ),
    );
  }

  Future<void> _edit([Employee? existing]) async {
    final s = AppStrings.of(context);
    final result = await showDialog<_EmployeeFormResult>(
      context: context,
      builder: (_) => _EmployeeFormDialog(existing: existing, repository: _repository),
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
        employeeNumber: result.employeeNumber,
        notes: result.notes,
        active: result.active,
        photo: result.newPhoto,
        clearPhoto: result.clearPhoto,
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
      subtitle: employee.jobTitle?.isNotEmpty == true
          ? employee.jobTitle!
          : s.text('job_${employee.jobType}'),
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
                for (final e in list)
                  _EmployeeCard(
                    employee: e,
                    repository: _repository,
                    onTap: () => _showProfile(e),
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
  const _EmployeeCard({
    required this.employee,
    required this.repository,
    required this.onTap,
    required this.onEdit,
    required this.onEnroll,
    required this.onArchive,
  });
  final Employee employee;
  final EmployeesRepository repository;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onEnroll;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final color = _jobColors[employee.jobType] ?? _jobColors['other']!;
    final fp = employee.fingerprintRegistered;
    final jobLabel = employee.jobTitle?.isNotEmpty == true
        ? employee.jobTitle!
        : s.text('job_${employee.jobType}');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Photo or Job Icon Avatar
              PersonAvatar(
                size: 52,
                personId: employee.id,
                photoUrl: employee.photoUrl,
                name: employee.fullName,
                db: repository.db,
                client: repository.client,
                backgroundColor: color.withAlpha(25),
                borderColor: color.withAlpha(80),
                borderWidth: 2,
                fallbackIcon: _jobIcons[employee.jobType] ?? LucideIcons.user,
                fallbackColor: color,
                iconSize: 24,
                preferIconFallback: true,
              ),
              const SizedBox(width: 14),
              // Name, Employee Number & Job Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            employee.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A).withAlpha(12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Text(
                            employee.employeeNumber,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: color.withAlpha(50)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_jobIcons[employee.jobType] ?? LucideIcons.user, size: 12, color: color),
                              const SizedBox(width: 5),
                              Text(
                                jobLabel,
                                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        if (employee.phone != null && employee.phone!.isNotEmpty)
                          Text(
                            employee.phone!,
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Chips & Action buttons
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
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
                  FilledButton.tonalIcon(
                    onPressed: onEnroll,
                    icon: const Icon(LucideIcons.fingerprint, size: 16),
                    label: Text(s.text(fp ? 're_enroll_fingerprint' : 'enroll_fingerprint'), style: const TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    tooltip: s.text('view_profile'),
                    onPressed: onTap,
                    icon: const Icon(LucideIcons.user, size: 18),
                  ),
                  IconButton(
                    tooltip: s.text('edit_employee'),
                    onPressed: onEdit,
                    icon: const Icon(LucideIcons.pencil, size: 18),
                  ),
                  IconButton(
                    tooltip: s.text('archive_employee'),
                    onPressed: onArchive,
                    icon: Icon(LucideIcons.trash2, size: 18, color: Colors.red.shade700),
                  ),
                ],
              ),
            ],
          ),
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
    required this.employeeNumber,
    required this.notes,
    required this.active,
    this.newPhoto,
    this.clearPhoto = false,
  });
  final String firstName;
  final String lastName;
  final String phone;
  final String email;
  final String jobType;
  final String jobTitle;
  final String employeeNumber;
  final String notes;
  final bool active;
  final Uint8List? newPhoto;
  final bool clearPhoto;
}

class _EmployeeFormDialog extends StatefulWidget {
  const _EmployeeFormDialog({this.existing, required this.repository});
  final Employee? existing;
  final EmployeesRepository repository;

  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  final _form = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final _first = TextEditingController(text: widget.existing?.firstName ?? '');
  late final _last = TextEditingController(text: widget.existing?.lastName ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _title = TextEditingController(text: widget.existing?.jobTitle ?? '');
  late final _empNumber = TextEditingController(text: widget.existing?.employeeNumber ?? _generateDefaultEmpNumber());
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late String _job = widget.existing?.jobType ?? 'coach';
  late bool _active = widget.existing?.active ?? true;

  Uint8List? _photoBytes;
  bool _photoCleared = false;
  bool _loadingExistingPhoto = false;

  static String _generateDefaultEmpNumber() {
    final rand = (math.Random().nextInt(0x8FFFFF) + 0x100000).toRadixString(16).toUpperCase();
    return 'EMP-$rand';
  }

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _loadExistingPhoto();
    }
  }

  Future<void> _loadExistingPhoto() async {
    setState(() => _loadingExistingPhoto = true);
    try {
      final bytes = await widget.repository.photoBytes(widget.existing!);
      if (mounted) {
        setState(() {
          _photoBytes = bytes;
          _loadingExistingPhoto = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingExistingPhoto = false);
    }
  }

  Future<void> _pickPhoto() async {
    final s = AppStrings.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: Text(s.text('take_instant_photo')),
              subtitle: Text(s.text('photo_instant_hint')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: Text(s.text('choose_from_gallery')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_photoBytes != null || widget.existing?.photoUrl != null)
              ListTile(
                leading: Icon(LucideIcons.trash2, color: Theme.of(context).colorScheme.error),
                title: Text(
                  s.text('delete'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  setState(() {
                    _photoBytes = null;
                    _photoCleared = true;
                  });
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );

    if (source == null) return;
    try {
      final file = await _picker.pickImage(source: source, maxWidth: 1200, maxHeight: 1200);
      if (file == null) return;
      final raw = await file.readAsBytes();
      final encoded = encodeMemberPhoto(raw);
      if (mounted) {
        setState(() {
          _photoBytes = encoded;
          _photoCleared = false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.text('invalid_photo'))),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _email, _title, _empNumber, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final color = _jobColors[_job] ?? _jobColors['other']!;

    return AlertDialog(
      title: Text(s.text(widget.existing == null ? 'new_employee' : 'edit_employee')),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Photo Avatar & Selector
              Center(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        GestureDetector(
                          onTap: _pickPhoto,
                          child: _loadingExistingPhoto
                              ? Container(
                                  width: 90,
                                  height: 90,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: color.withAlpha(20),
                                    border: Border.all(color: color, width: 2.5),
                                  ),
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : PersonAvatar(
                                  size: 90,
                                  personId: _photoCleared ? null : widget.existing?.id,
                                  photoUrl: _photoCleared ? null : widget.existing?.photoUrl,
                                  name: '${_first.text} ${_last.text}'.trim(),
                                  db: widget.repository.db,
                                  client: widget.repository.client,
                                  initialBytes: _photoBytes,
                                  backgroundColor: color.withAlpha(20),
                                  borderColor: color,
                                  borderWidth: 2.5,
                                  fallbackIcon: LucideIcons.camera,
                                  fallbackColor: color,
                                  iconSize: 34,
                                  preferIconFallback: true,
                                ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: InkWell(
                            onTap: _pickPhoto,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF0F766E),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.pencil, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(LucideIcons.camera, size: 16),
                      label: Text(_photoBytes != null ? s.text('change_photo') : s.text('choose_photo')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _first,
                    autofocus: widget.existing == null,
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
              // Matricule / Employee Number
              TextFormField(
                controller: _empNumber,
                maxLength: 30,
                decoration: InputDecoration(
                  labelText: s.text('employee_number'),
                  prefixIcon: const Icon(LucideIcons.idCard, size: 18),
                  counterText: '',
                  helperText: 'Nimewo idantifikasyon / matrikil pou aksè a.',
                ),
              ),
              const SizedBox(height: 12),
              // Job Type Dropdown
              DropdownButtonFormField<String>(
                initialValue: _job,
                decoration: InputDecoration(
                  labelText: s.text('job_type'),
                  prefixIcon: Icon(_jobIcons[_job], color: _jobColors[_job], size: 18),
                ),
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
              // Conditional Custom Job Title
              if (_job == 'other') ...[
                TextFormField(
                  controller: _title,
                  maxLength: 80,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '${s.text('custom_job_hint')} *',
                    helperText: 'Egzanp: Kesyè, Sipèvizè, Asistan...',
                    prefixIcon: const Icon(LucideIcons.briefcase, size: 18),
                    counterText: '',
                  ),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? s.text('custom_job_required') : null,
                ),
              ] else ...[
                TextFormField(
                  controller: _title,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: '${s.text('job_title')} (Opsyonèl)',
                    prefixIcon: const Icon(LucideIcons.briefcase, size: 18),
                    counterText: '',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _phone,
                    maxLength: 32,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: s.text('phone'),
                      prefixIcon: const Icon(LucideIcons.phone, size: 18),
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: s.text('email'),
                      prefixIcon: const Icon(LucideIcons.mail, size: 18),
                    ),
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
                decoration: InputDecoration(
                  labelText: s.text('employee_notes'),
                  prefixIcon: const Icon(LucideIcons.fileText, size: 18),
                  counterText: '',
                ),
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
                employeeNumber: _empNumber.text,
                notes: _notes.text,
                active: _active,
                newPhoto: _photoBytes,
                clearPhoto: _photoCleared,
              ),
            );
          },
          child: Text(s.text('save')),
        ),
      ],
    );
  }
}

class _EmployeeProfileDialog extends StatelessWidget {
  const _EmployeeProfileDialog({
    required this.employee,
    required this.repository,
    required this.onEdit,
    required this.onEnroll,
    required this.onArchive,
  });

  final Employee employee;
  final EmployeesRepository repository;
  final VoidCallback onEdit;
  final VoidCallback onEnroll;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final color = _jobColors[employee.jobType] ?? _jobColors['other']!;
    final jobLabel = employee.jobTitle?.isNotEmpty == true
        ? employee.jobTitle!
        : s.text('job_${employee.jobType}');
    final fp = employee.fingerprintRegistered;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Header Banner
            Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.9), color.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  PersonAvatar(
                    size: 96,
                    personId: employee.id,
                    photoUrl: employee.photoUrl,
                    name: employee.fullName,
                    db: repository.db,
                    client: repository.client,
                    backgroundColor: Colors.white,
                    borderColor: Colors.white,
                    borderWidth: 3,
                    shadows: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                    fallbackIcon: _jobIcons[employee.jobType] ?? LucideIcons.user,
                    fallbackColor: color,
                    iconSize: 48,
                    preferIconFallback: true,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    employee.fullName,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // Employee Number Badge with Copy
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: employee.employeeNumber));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Matrikil ${employee.employeeNumber} kopye !')),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.idCard, size: 14, color: Colors.white70),
                          const SizedBox(width: 6),
                          Text(
                            employee.employeeNumber,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                          const SizedBox(width: 6),
                          const Icon(LucideIcons.copy, size: 12, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Position Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_jobIcons[employee.jobType] ?? LucideIcons.user, size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          jobLabel.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Profile Body Info
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Contact Section
                    Text(
                      s.text('contact_info'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),
                    _ProfileTile(
                      icon: LucideIcons.phone,
                      label: s.text('phone'),
                      value: employee.phone?.isNotEmpty == true ? employee.phone! : 'Non renseigné',
                      onCopy: employee.phone?.isNotEmpty == true
                          ? () => Clipboard.setData(ClipboardData(text: employee.phone!))
                          : null,
                    ),
                    const SizedBox(height: 6),
                    _ProfileTile(
                      icon: LucideIcons.mail,
                      label: s.text('email'),
                      value: employee.email?.isNotEmpty == true ? employee.email! : 'Non renseigné',
                      onCopy: employee.email?.isNotEmpty == true
                          ? () => Clipboard.setData(ClipboardData(text: employee.email!))
                          : null,
                    ),
                    const SizedBox(height: 16),
                    // Security & Access Section
                    Text(
                      s.text('security_access'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),
                    _ProfileTile(
                      icon: employee.active ? LucideIcons.shieldCheck : LucideIcons.ban,
                      iconColor: employee.active ? const Color(0xFF10B981) : Colors.red.shade700,
                      label: 'Statut accès',
                      value: s.text(employee.active ? 'employee_active' : 'employee_inactive'),
                    ),
                    const SizedBox(height: 6),
                    _ProfileTile(
                      icon: LucideIcons.fingerprint,
                      iconColor: fp ? const Color(0xFF10B981) : Colors.orange.shade800,
                      label: 'Empreinte biométrique',
                      value: fp
                          ? s.text('captures_count').replaceAll('{n}', '${employee.fingerprintTemplates.length}')
                          : s.text('fingerprint_missing'),
                    ),
                    if (employee.notes != null && employee.notes!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        s.text('employee_notes'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(employee.notes!, style: const TextStyle(fontSize: 13, height: 1.4)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Dialog Action Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  IconButton(
                    tooltip: s.text('archive_employee'),
                    onPressed: onArchive,
                    icon: Icon(LucideIcons.trash2, color: Colors.red.shade700),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: onEnroll,
                    icon: const Icon(LucideIcons.fingerprint, size: 16),
                    label: Text(s.text(fp ? 're_enroll_fingerprint' : 'enroll_fingerprint')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                    onPressed: onEdit,
                    icon: const Icon(LucideIcons.pencil, size: 16),
                    label: Text(s.text('edit_profile')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.value,
    this.onCopy,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor ?? const Color(0xFF64748B)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              icon: const Icon(LucideIcons.copy, size: 16, color: Color(0xFF94A3B8)),
              onPressed: () {
                onCopy!();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$value copié !'), duration: const Duration(seconds: 1)),
                );
              },
            ),
        ],
      ),
    );
  }
}
