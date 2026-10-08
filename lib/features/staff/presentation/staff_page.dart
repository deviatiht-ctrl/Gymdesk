import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
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

  Future<void> _access(StaffProfile person) async {
    if (_busy || !{'supervisor', 'reception'}.contains(person.role)) return;
    final s = AppStrings.of(context);
    var role = person.role;
    var active = person.active;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('${s.text('change_access')} · ${person.fullName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.text('save_access_confirmation')),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: InputDecoration(labelText: s.text('staff_role')),
                items: [
                  DropdownMenuItem(
                    value: 'supervisor',
                    child: Text(s.text('supervisor')),
                  ),
                  DropdownMenuItem(
                    value: 'reception',
                    child: Text(s.text('reception')),
                  ),
                ],
                onChanged: (value) => setDialog(() => role = value!),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.text(active ? 'active' : 'suspended')),
                value: active,
                onChanged: (value) => setDialog(() => active = value),
              ),
            ],
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
      await _repository.updateAccess(person, role: role, active: active);
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
                            '${s.text(person.role)} · ${s.text(person.active ? 'active' : 'suspended')}',
                          ),
                        ),
                      ],
                    ),
                    subtitle: person.phone == null ? null : Text(person.phone!),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
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
