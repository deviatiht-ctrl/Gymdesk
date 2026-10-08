import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/auth/pin_service.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';

class PinPage extends ConsumerStatefulWidget {
  const PinPage({super.key});
  @override
  ConsumerState<PinPage> createState() => _PinPageState();
}

class _PinPageState extends ConsumerState<PinPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  PinStatus? _status;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await ref.read(appRuntimeProvider).pinStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _loading = false;
        });
      }
    } on PinFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.code;
          _loading = false;
        });
      }
    }
  }

  String? _validatePin(String? value, AppStrings s) {
    final pin = value ?? '';
    return RegExp(r'^\d{6,12}$').hasMatch(pin) ? null : s.text('pin_format');
  }

  Future<void> _save() async {
    final status = _status;
    if (_busy || status == null || !_form.currentState!.validate()) return;
    final s = AppStrings.of(context);
    if (_next.text != _confirm.text) {
      setState(() => _error = 'pin_mismatch');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(appRuntimeProvider)
          .configurePin(_next.text, previous: _current.text);
      for (final field in [_current, _next, _confirm]) {
        field.clear();
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text('pin_saved'))));
      }
      await _load();
    } on PinFailure catch (e) {
      if (mounted) setState(() => _error = e.code);
      if (e.code == 'pin_incorrect' ||
          e.code == 'pin_cooldown' ||
          e.code == 'pin_password_required') {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final status = _status;
    if (_busy || status?.enabled != true) return;
    final s = AppStrings.of(context);
    final recent = ref.read(appRuntimeProvider).pinRecentlyAuthenticated;
    if (!recent && !RegExp(r'^\d{6,12}$').hasMatch(_current.text)) {
      setState(() => _error = 'pin_format');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(appRuntimeProvider).removePin(_current.text);
      for (final field in [_current, _next, _confirm]) {
        field.clear();
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.text('pin_removed'))));
      }
      await _load();
    } on PinFailure catch (e) {
      if (mounted) setState(() => _error = e.code);
      if (e.code == 'pin_incorrect' ||
          e.code == 'pin_cooldown' ||
          e.code == 'pin_password_required') {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final field in [_current, _next, _confirm]) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final status = _status;
    final enabled = status?.enabled == true;
    final recent = ref.watch(appRuntimeProvider).pinRecentlyAuthenticated;
    return Scaffold(
      appBar: AppBar(title: Text(s.text('pin'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: LoadingPanel(),
                  )
                : Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      shrinkWrap: true,
                      children: [
                        Text(
                          s.text(enabled ? 'pin_change' : 'pin_setup'),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(s.text('pin_security')),
                        const SizedBox(height: 8),
                        Text(s.text(enabled ? 'pin_on_hint' : 'pin_off_hint')),
                        if (status != null && status.enabled)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              '${s.text(status.failures >= 10 ? 'pin_password_required' : 'enabled')} · ${s.text('failed')}: ${status.failures}',
                            ),
                          ),
                        const SizedBox(height: 24),
                        if (enabled && !recent)
                          TextFormField(
                            controller: _current,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.number,
                            maxLength: 12,
                            decoration: InputDecoration(
                              labelText: s.text('current_pin'),
                              counterText: '',
                            ),
                            validator: (v) => _validatePin(v, s),
                          ),
                        TextFormField(
                          controller: _next,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.number,
                          maxLength: 12,
                          decoration: InputDecoration(
                            labelText: s.text('new_pin'),
                            counterText: '',
                          ),
                          validator: (v) => _validatePin(v, s),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirm,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.number,
                          maxLength: 12,
                          decoration: InputDecoration(
                            labelText: s.text('confirm_pin'),
                            counterText: '',
                          ),
                          validator: (v) => _validatePin(v, s),
                        ),
                        if (_error != null)
                          MessagePanel(message: s.text(_error!)),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _save,
                          child: Text(
                            s.text(enabled ? 'pin_change' : 'pin_setup'),
                          ),
                        ),
                        if (enabled) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : ref.read(appRuntimeProvider).lockNow,
                                icon: const Icon(LucideIcons.lockKeyhole),
                                label: Text(s.text('lock_now')),
                              ),
                              TextButton(
                                onPressed: _busy ? null : _remove,
                                child: Text(s.text('pin_remove')),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
