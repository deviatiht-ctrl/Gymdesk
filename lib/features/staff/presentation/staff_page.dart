import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../../members/presentation/fingerprint_enrollment_dialog.dart';
import '../data/staff_repository.dart';
import '../domain/staff_profile.dart';

class StaffPage extends ConsumerStatefulWidget {
  const StaffPage({super.key});
  @override
  ConsumerState<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends ConsumerState<StaffPage> {
  late final StaffRepository _repository;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = StaffRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
  }

  Future<void> _create() async {
    final created = await context.push<bool>('/settings/staff/new');
    if (created == true && mounted) {
      await ref.read(appRuntimeProvider).sync?.synchronize(retry: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('staff_created'))),
      );
    }
  }

  Future<void> _profile(StaffProfile person) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final name = TextEditingController(text: person.fullName);
    final phone = TextEditingController(text: person.phone ?? '');
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${s.text('edit_profile')} · ${person.fullName}'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: InputDecoration(labelText: s.text('full_name')),
                validator: (v) => (v?.trim().length ?? 0) < 2
                    ? s.text('invalid_record')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phone,
                maxLength: 32,
                decoration: InputDecoration(
                  labelText: s.text('phone'),
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.text('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: Text(s.text('save')),
          ),
        ],
      ),
    );
    if (accepted != true) {
      name.dispose();
      phone.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.updateProfile(
        person,
        fullName: name.text,
        phone: phone.text.trim(),
      );
      await HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text('staff_saved'))));
      }
    } on StaffFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text(e.code))));
      }
    } finally {
      name.dispose();
      phone.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  String _jobTitleText(StaffProfile p, AppStrings s) {
    if (p.role == 'owner') return s.text('owner');
    if (p.role == 'super_admin') return 'Super Admin';
    final job = p.jobTitle;
    return switch (job) {
      'caissier' => s.text('job_title_cashier'),
      'secretaire' => s.text('job_title_secretary'),
      'superviseur' => s.text('job_title_supervisor'),
      _ => s.text(p.role),
    };
  }

  Future<void> _access(StaffProfile person) async {
    if (_busy || !{'supervisor', 'reception'}.contains(person.role)) return;
    final s = AppStrings.of(context);
    var role = person.role;
    var jobTitle = person.jobTitle;
    var active = person.active;
    var permMembersAdd = person.canAddMembers;
    var permCashier = person.canCashier;
    var permPaymentsView = person.canViewPayments;
    var permReceiptsView = person.canViewReceipts;
    var permReportsView = person.canViewReports;
    var permPlansManage = person.canManagePlans;
    var permAccessControl = person.canAccessControl;

    void applyPreset(String job, StateSetter setDialog) {
      setDialog(() {
        jobTitle = job;
        if (job == 'caissier') {
          role = 'reception';
          permMembersAdd = true;
          permCashier = true;
          permPaymentsView = true;
          permReceiptsView = true;
          permReportsView = false;
          permPlansManage = false;
          permAccessControl = true;
        } else if (job == 'secretaire') {
          role = 'reception';
          permMembersAdd = true;
          permCashier = false;
          permPaymentsView = false;
          permReceiptsView = true;
          permReportsView = false;
          permPlansManage = false;
          permAccessControl = true;
        } else if (job == 'superviseur') {
          role = 'supervisor';
          permMembersAdd = true;
          permCashier = true;
          permPaymentsView = true;
          permReceiptsView = true;
          permReportsView = true;
          permPlansManage = true;
          permAccessControl = true;
        }
      });
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('${s.text('change_access')} · ${person.fullName}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: ['caissier', 'secretaire', 'superviseur'].contains(jobTitle) ? jobTitle : 'personnalise',
                    decoration: InputDecoration(
                      labelText: s.text('staff_position'),
                      prefixIcon: const Icon(LucideIcons.briefcase),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'caissier',
                        child: Text(s.text('job_title_cashier')),
                      ),
                      DropdownMenuItem(
                        value: 'secretaire',
                        child: Text(s.text('job_title_secretary')),
                      ),
                      DropdownMenuItem(
                        value: 'superviseur',
                        child: Text(s.text('job_title_supervisor')),
                      ),
                      DropdownMenuItem(
                        value: 'personnalise',
                        child: Text(s.text('job_title_custom')),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) applyPreset(val, setDialog);
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.text(active ? 'active' : 'suspended'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    value: active,
                    onChanged: (value) => setDialog(() => active = value),
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Icon(LucideIcons.shieldCheck, color: Color(0xFF0F766E), size: 18),
                      const SizedBox(width: 6),
                      Text(
                        s.text('staff_permissions'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F766E)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.text('perm_members_add')),
                    value: permMembersAdd,
                    onChanged: (v) => setDialog(() => permMembersAdd = v ?? true),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.text('perm_cashier')),
                    value: permCashier,
                    onChanged: (v) => setDialog(() => permCashier = v ?? true),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.text('perm_payments_view')),
                    value: permPaymentsView,
                    onChanged: (v) => setDialog(() => permPaymentsView = v ?? true),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.text('perm_receipts_view')),
                    value: permReceiptsView,
                    onChanged: (v) => setDialog(() => permReceiptsView = v ?? true),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.text('perm_reports_view')),
                    value: permReportsView,
                    onChanged: (v) => setDialog(() => permReportsView = v ?? true),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.text('perm_plans_manage')),
                    value: permPlansManage,
                    onChanged: (v) => setDialog(() => permPlansManage = v ?? true),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.text('perm_access_control')),
                    value: permAccessControl,
                    onChanged: (v) => setDialog(() => permAccessControl = v ?? true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.text('save')),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final permissions = <String, dynamic>{
        'job_title': jobTitle,
        'can_add_members': permMembersAdd,
        'can_cashier': permCashier,
        'can_view_payments': permPaymentsView,
        'can_view_receipts': permReceiptsView,
        'can_view_reports': permReportsView,
        'can_manage_plans': permPlansManage,
        'can_access_control': permAccessControl,
      };
      await _repository.updateAccess(
        person,
        role: role,
        active: active,
        permissions: permissions,
      );
      await HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text('staff_saved'))));
      }
    } on StaffFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text(e.code))));
        if (e.code == 'conflict') {
          await ref.read(appRuntimeProvider).sync?.synchronize();
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enrollFingerprint(StaffProfile person) async {
    if (_busy) return;
    final s = AppStrings.of(context);

    if (person.fingerprintRegistered) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${s.text('fingerprint')} · ${person.fullName}'),
          content: Text(s.text('fingerprint_registered_desc')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: Text(s.text('cancel')),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              onPressed: () => Navigator.pop(context, 'delete'),
              child: Text(s.text('remove_fingerprint')),
            ),
            FilledButton.icon(
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              onPressed: () => Navigator.pop(context, 're_enroll'),
              label: Text(s.text('re_enroll_fingerprint')),
            ),
          ],
        ),
      );

      if (choice == 'delete') {
        setState(() => _busy = true);
        try {
          await _repository.clearFingerprints(person);
          await ref.read(appRuntimeProvider).sync?.synchronize();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.text('fingerprint_removed'))),
            );
          }
        } on StaffFailure catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.text(e.code))),
            );
          }
        } finally {
          if (mounted) setState(() => _busy = false);
        }
        return;
      } else if (choice != 're_enroll') {
        return;
      }
    }

    if (!mounted) return;
    await FingerprintEnrollmentDialog.showGeneric(
      context,
      displayName: person.fullName,
      subtitle: _jobTitleText(person, s),
      onCaptured: (captures) => _repository.saveFingerprints(person, captures),
      onSaved: () {
        ref.read(appRuntimeProvider).sync?.synchronize();
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final session = ref.watch(appRuntimeProvider).session!;
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
                    s.text('staff'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(LucideIcons.userPlus),
                    label: Text(s.text('new_staff')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(s.text('staff_online')),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: StreamBuilder<List<StaffProfile>>(
            stream: _repository.watch(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: MessagePanel(message: s.text('local_storage')),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: LoadingPanel(),
                );
              }
              if (snapshot.data!.isEmpty) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: MessagePanel(
                    message: s.text('staff_empty'),
                    action: s.text('new_staff'),
                    onAction: _create,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final person = snapshot.data![index];
                  final isSelf = person.id == session.staffId;
                  final manageable =
                      {'supervisor', 'reception'}.contains(person.role) && !isSelf;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    title: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          person.fullName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xfff0f1f0),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${_jobTitleText(person, s)} · ${s.text(person.active ? 'active' : 'suspended')}',
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: person.fingerprintRegistered
                                ? const Color(0xffe6f4ea)
                                : const Color(0xfff1f3f4),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.fingerprint,
                                size: 14,
                                color: person.fingerprintRegistered
                                    ? const Color(0xff137333)
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                person.fingerprintRegistered
                                    ? s.text('fingerprint_ok')
                                    : s.text('fingerprint_missing'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: person.fingerprintRegistered
                                      ? const Color(0xff137333)
                                      : Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    subtitle: person.phone == null ? null : Text(person.phone!),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        if (session.role == 'owner' || isSelf)
                          IconButton(
                            tooltip: person.fingerprintRegistered
                                ? s.text('re_enroll_fingerprint')
                                : s.text('enroll_fingerprint'),
                            onPressed: _busy ? null : () => _enrollFingerprint(person),
                            icon: Icon(
                              LucideIcons.fingerprint,
                              color: person.fingerprintRegistered ? const Color(0xff137333) : null,
                            ),
                          ),
                        if (isSelf || manageable)
                          IconButton(
                            tooltip: s.text('edit_profile'),
                            onPressed: _busy ? null : () => _profile(person),
                            icon: const Icon(LucideIcons.pencil),
                          ),
                        if (manageable)
                          IconButton(
                            tooltip: s.text('change_access'),
                            onPressed: _busy ? null : () => _access(person),
                            icon: Icon(
                              person.active
                                  ? LucideIcons.userCheck
                                  : LucideIcons.userX,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
