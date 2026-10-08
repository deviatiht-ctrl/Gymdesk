import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';
import '../data/staff_draft_store.dart';
import '../data/staff_repository.dart';
import '../domain/staff_profile.dart';

class CreateStaffPage extends ConsumerStatefulWidget {
  const CreateStaffPage({super.key});
  @override
  ConsumerState<CreateStaffPage> createState() => _CreateStaffPageState();
}

class _CreateStaffPageState extends ConsumerState<CreateStaffPage> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final key in ['full_name', 'email', 'phone', 'password'])
      key: TextEditingController(),
  };
  late final StaffRepository _repository;
  late final StaffDraftStore _store;
  Json? _draft;
  String _role = 'reception';
  bool _loading = true;
  bool _busy = false;
  bool _loadFailed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _repository = StaffRepository(
      runtime.client,
      runtime.database!,
      runtime.session!,
    );
    _store = StaffDraftStore(runtime.namespace, runtime.session!.userId);
    _restore();
  }

  Future<void> _restore() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final saved = await _store.read();
      if (!mounted) return;
      if (saved != null) {
        _draft = saved;
        _role = saved['role'] as String? ?? 'reception';
        _fields['full_name']!.text = saved['full_name'] as String? ?? '';
        _fields['email']!.text = saved['email'] as String? ?? '';
        _fields['phone']!.text = saved['phone'] as String? ?? '';
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'local_storage';
          _loadFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validate(String key, String? value, AppStrings s) {
    final text = value?.trim() ?? '';
    if (key != 'phone' && text.isEmpty) return s.text('required');
    if (key == 'full_name' && (text.length < 2 || text.length > 120)) {
      return s.text('invalid_record');
    }
    if (key == 'email' &&
        (text.length > 254 ||
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text))) {
      return s.text('invalid_email');
    }
    if (key == 'phone' && text.length > 32) return s.text('invalid_record');
    if (key == 'password' && (value?.length ?? 0) < 12 ||
        (value?.length ?? 0) > 128) {
      return s.text('weak_password');
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.text('new_staff')),
        content: Text(s.text('create_staff_confirmation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.text('create_staff')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final draft = _draft;
    final command = CreateStaffCommand(
      requestId: draft?['request_id'] as String? ?? const Uuid().v4(),
      staffId: draft?['staff_id'] as String? ?? const Uuid().v4(),
      fullName: _fields['full_name']!.text.trim(),
      email: _fields['email']!.text.trim().toLowerCase(),
      phone: _fields['phone']!.text.trim(),
      role: _role,
      password: _fields['password']!.text,
    );
    try {
      await _store.save(command);
      _draft = command.toJson()..remove('password');
      await _repository.create(command);
      await _store.clear();
      _fields['password']!.clear();
      await HapticFeedback.lightImpact();
      if (mounted) context.pop(true);
    } on StaffFailure catch (e) {
      if ({'owner_exists', 'request_mismatch'}.contains(e.code)) {
        try {
          await _store.clear();
          _draft = null;
        } catch (_) {
          _error = 'local_storage';
        }
      }
      if (mounted) setState(() => _error ??= e.code);
    } catch (_) {
      if (mounted) setState(() => _error = 'local_storage');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(s.text('new_staff'))),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: LoadingPanel(),
                    )
                  : _loadFailed
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: MessagePanel(
                        message: s.text(_error!),
                        action: s.text('retry'),
                        onAction: _restore,
                      ),
                    )
                  : Form(
                      key: _form,
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        shrinkWrap: true,
                        children: [
                          Text(s.text('staff_hint')),
                          if (_draft != null) ...[
                            const SizedBox(height: 16),
                            MessagePanel(
                              message:
                                  '${s.text('provision_resume')} ${_draft!['request_id']}',
                            ),
                          ],
                          const SizedBox(height: 24),
                          for (final key in _fields.keys)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: TextFormField(
                                controller: _fields[key],
                                readOnly:
                                    _busy ||
                                    (_draft != null && key != 'password'),
                                obscureText: key == 'password',
                                autocorrect: key != 'password',
                                enableSuggestions: key != 'password',
                                maxLength: key == 'password'
                                    ? 128
                                    : key == 'phone'
                                    ? 32
                                    : key == 'email'
                                    ? 254
                                    : 120,
                                keyboardType: key == 'email'
                                    ? TextInputType.emailAddress
                                    : key == 'phone'
                                    ? TextInputType.phone
                                    : TextInputType.text,
                                decoration: InputDecoration(
                                  labelText: s.text(
                                    key == 'password' ? 'staff_password' : key,
                                  ),
                                  counterText: '',
                                ),
                                validator: (v) => _validate(key, v, s),
                              ),
                            ),
                          DropdownButtonFormField<String>(
                            initialValue: _role,
                            decoration: InputDecoration(
                              labelText: s.text('staff_role'),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'reception',
                                child: Text(s.text('reception')),
                              ),
                              DropdownMenuItem(
                                value: 'supervisor',
                                child: Text(s.text('supervisor')),
                              ),
                            ],
                            onChanged: _busy || _draft != null
                                ? null
                                : (value) => setState(() => _role = value!),
                          ),
                          if (_error != null)
                            MessagePanel(message: s.text(_error!)),
                          if (_busy) const LoadingPanel(rows: 1),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: Text(
                              s.text(
                                _draft == null
                                    ? 'create_staff'
                                    : 'resume_creation',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
