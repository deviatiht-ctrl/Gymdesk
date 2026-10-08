import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/providers.dart';
import '../../../app/runtime.dart';
import '../../../l10n/app_strings.dart';

class UnlockPage extends ConsumerStatefulWidget {
  const UnlockPage({super.key});
  @override
  ConsumerState<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends ConsumerState<UnlockPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    await ref.read(appRuntimeProvider).unlock(_controller.text);
    if (mounted && ref.read(appRuntimeProvider).phase == SessionPhase.ready) {
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(appRuntimeProvider);
    final s = AppStrings.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(LucideIcons.lockKeyhole, size: 40),
                  const SizedBox(height: 24),
                  Text(
                    s.text('unlock_session'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(s.text('pin_unlock_hint')),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.number,
                    maxLength: 12,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _unlock(),
                    decoration: InputDecoration(
                      labelText: s.text('pin'),
                      counterText: '',
                    ),
                  ),
                  if (runtime.errorCode != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        s.text(runtime.errorCode!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if ({'pin_storage', 'pin_missing', 'pin_password_required'}
                      .contains(runtime.errorCode))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        s.text('pin_use_password_hint'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: runtime.busy ? null : _unlock,
                    icon: runtime.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.lockOpen),
                    label: Text(
                      s.text(runtime.busy ? 'verifying' : 'unlock'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: runtime.busy ? null : runtime.signOut,
                    child: Text(s.text('use_password')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
