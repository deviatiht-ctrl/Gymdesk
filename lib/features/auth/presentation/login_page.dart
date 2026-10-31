import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/runtime.dart';
import '../../../core/widgets/async_panel.dart';
import '../../../core/widgets/securgym_background.dart';
import '../../../l10n/app_strings.dart';
import '../../member_portal/presentation/member_gyms_panel.dart';

/// Connexion propriétaire / personnel + espace membre.
/// Laptop : deux colonnes (liste des gyms | connexion). Mobile : onglets.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.memberFirst = false});

  /// Ouvre l'onglet « Membre » en premier sur mobile (`/espace-membre`).
  final bool memberFirst;
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  late bool _memberTab = widget.memberFirst;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await HapticFeedback.lightImpact();
    final runtime = ref.read(appRuntimeProvider);
    await runtime.signIn(_email.text, _password.text);
    if (!mounted) return;
    _password.clear();
    // Sur /espace-membre (route publique) le routeur ne redirige pas tout seul.
    if (runtime.phase != SessionPhase.signedOut && GoRouterState.of(context).uri.path != '/login') {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(appRuntimeProvider);
    final s = AppStrings.of(context);
    const brandOrange = Color(0xffff6600);

    final card = _loginCard(runtime, s, brandOrange);
    return Scaffold(
      backgroundColor: const Color(0xff121417),
      body: SecurGymBackground(
        child: LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= 960) {
              final height = (c.maxHeight - 48).clamp(480.0, 780.0);
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: SizedBox(
                      height: height,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Expanded(child: MemberGymsPanel()),
                          const SizedBox(width: 28),
                          SizedBox(
                            width: 420,
                            child: Center(child: SingleChildScrollView(child: card)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth >= 640 ? 600 : 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _tabs(brandOrange),
                      const SizedBox(height: 16),
                      _memberTab ? const MemberGymsPanel(expand: false) : card,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _tabs(Color brandOrange) {
    Widget tab(String label, IconData icon, bool selected, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? brandOrange : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : const Color(0xff9ca3af)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xff9ca3af),
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xff1a1d24).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          tab('Propriétaire / Personnel', LucideIcons.building2, !_memberTab, () => setState(() => _memberTab = false)),
          tab('Espace membre', LucideIcons.users, _memberTab, () => setState(() => _memberTab = true)),
        ],
      ),
    );
  }

  Widget _loginCard(AppRuntime runtime, AppStrings s, Color brandOrange) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xff1a1d24).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 36, offset: const Offset(0, 12)),
        ],
      ),
      child: ListenableBuilder(
        listenable: runtime,
        builder: (context, _) => AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Image.asset('assets/brand/logo_horizontal.png', width: 220, fit: BoxFit.contain)),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    s.text('account_hint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xff9ca3af), fontSize: 13),
                  ),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _email,
                  enabled: !runtime.busy,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: s.text('email'),
                    labelStyle: const TextStyle(color: Color(0xff9ca3af)),
                    fillColor: const Color(0xff222630),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                  ),
                  validator: (value) => value == null || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
                      ? s.text('invalid_email')
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  enabled: !runtime.busy,
                  style: const TextStyle(color: Colors.white),
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: s.text('password'),
                    labelStyle: const TextStyle(color: Color(0xff9ca3af)),
                    fillColor: const Color(0xff222630),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    suffixIcon: IconButton(
                      tooltip: s.text(_obscure ? 'show_password' : 'hide_password'),
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, color: const Color(0xff9ca3af)),
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty ? s.text('required') : null,
                ),
                if (runtime.errorCode != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      s.text(runtime.errorCode!),
                      style: const TextStyle(color: Color(0xffff5555), fontWeight: FontWeight.bold),
                    ),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: brandOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: runtime.busy ? null : _submit,
                    child: Text(s.text('sign_in'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xff374151)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => context.go('/signup'),
                    child: Text(s.text('create_gym_trial')),
                  ),
                ),
                if (runtime.busy) const Padding(padding: EdgeInsets.only(top: 16), child: LoadingPanel(rows: 1)),
                const SizedBox(height: 24),
                const LanguagePicker(),
                const SizedBox(height: 24),
                const Center(
                  child: Text('SecurGYM · securgym.com', style: TextStyle(color: Color(0xff6b7280), fontSize: 12)),
                ),
              ],
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
  Widget build(BuildContext context, WidgetRef ref) => DropdownButtonFormField<String>(
    initialValue: ref.watch(appLanguageProvider).languageCode,
    decoration: InputDecoration(labelText: AppStrings.of(context).text('language')),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(AppStrings.of(context).text('local_storage'))));
        }
      }
    },
  );
}
