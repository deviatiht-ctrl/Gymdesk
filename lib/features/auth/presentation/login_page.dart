import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../l10n/app_strings.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await HapticFeedback.lightImpact();
    await ref.read(appRuntimeProvider).signIn(_email.text, _password.text);
    if (mounted) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(appRuntimeProvider);
    final s = AppStrings.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListenableBuilder(
                listenable: runtime,
                builder: (context, _) => AutofillGroup(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GymDesk',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(s.text('account_hint')),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _email,
                          enabled: !runtime.busy,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: s.text('email'),
                          ),
                          validator: (value) =>
                              value == null ||
                                  !RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(value.trim())
                              ? s.text('invalid_email')
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          enabled: !runtime.busy,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: s.text('password'),
                            suffixIcon: IconButton(
                              tooltip: s.text(
                                _obscure ? 'show_password' : 'hide_password',
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                              ),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? s.text('required')
                              : null,
                        ),
                        if (runtime.errorCode != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              s.text(runtime.errorCode!),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: runtime.busy ? null : _submit,
                            child: Text(s.text('sign_in')),
                          ),
                        ),
                        if (runtime.busy) const LoadingPanel(rows: 1),
                        const SizedBox(height: 24),
                        const LanguagePicker(),
                        const SizedBox(height: 32),
                        const Text('Designed by Cvisual'),
                      ],
                    ),
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

class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      DropdownButtonFormField<String>(
        initialValue: ref.watch(appLanguageProvider).languageCode,
        decoration: InputDecoration(
          labelText: AppStrings.of(context).text('language'),
        ),
        items: const [
          DropdownMenuItem(value: 'ht', child: Text('Kreyòl ayisyen')),
          DropdownMenuItem(value: 'fr', child: Text('Français')),
          DropdownMenuItem(value: 'en', child: Text('English')),
        ],
        onChanged: (value) async {
          if (value == null) return;
          try {
            await ref.read(appLanguageProvider.notifier).change(value);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppStrings.of(context).text('local_storage')),
                ),
              );
            }
          }
        },
      );
}
