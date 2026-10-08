import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';

class PasswordResetPage extends ConsumerStatefulWidget {
  const PasswordResetPage({super.key});
  @override
  ConsumerState<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends ConsumerState<PasswordResetPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(appRuntimeProvider);
    final s = AppStrings.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListenableBuilder(
                listenable: runtime,
                builder: (context, _) => Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.text('reset_owner'),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      Text(s.text('password_recovery_hint')),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        enabled: !runtime.busy,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: (_) => runtime.activity(),
                        decoration: InputDecoration(
                          labelText: s.text('new_password'),
                        ),
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            value == null ||
                                value.length < 12 ||
                                value.length > 128
                            ? s.text('weak_password')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmation,
                        obscureText: true,
                        enabled: !runtime.busy,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: (_) => runtime.activity(),
                        decoration: InputDecoration(
                          labelText: s.text('confirm_password'),
                        ),
                        validator: (value) => value != _password.text
                            ? s.text('password_mismatch')
                            : null,
                      ),
                      if (runtime.errorCode != null)
                        MessagePanel(message: s.text(runtime.errorCode!)),
                      if (runtime.busy) const LoadingPanel(rows: 1),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: runtime.busy
                            ? null
                            : () async {
                                if (!_form.currentState!.validate()) return;
                                await runtime.finishPasswordRecovery(
                                  _password.text,
                                );
                                if (mounted) {
                                  _password.clear();
                                  _confirmation.clear();
                                }
                              },
                        child: Text(s.text('save_password')),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: runtime.busy ? null : runtime.signOut,
                        child: Text(s.text('sign_out')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
