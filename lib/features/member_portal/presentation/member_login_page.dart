import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/securgym_background.dart';
import '../data/member_portal_repository.dart';
import '../data/member_session.dart';
import 'member_ui.dart';

const _brandOrange = Color(0xffff6600);
const _muted = Color(0xff9ca3af);
const _field = Color(0xff222630);

/// `/espace-membre/connexion` : connexion membre sans choisir de gym (le membre ne
/// voit pas son gym dans la liste). Après connexion on ouvre son gym, ou on lui
/// laisse choisir s'il est membre de plusieurs gyms.
class MemberLoginPage extends StatefulWidget {
  const MemberLoginPage({super.key});

  @override
  State<MemberLoginPage> createState() => _MemberLoginPageState();
}

class _MemberLoginPageState extends State<MemberLoginPage> {
  final _repo = MemberPortalRepository();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _recovery = false;
  String? _error;
  String? _info;
  List<Map<String, dynamic>>? _gyms;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await MemberAuth.instance.restore();
    bool recovery = false;
    try {
      recovery = await MemberAuth.instance.consumeRecoveryFragment(Uri.base);
    } catch (_) {}
    if (!mounted) return;
    if (recovery) {
      setState(() => _recovery = true);
    } else if (MemberAuth.instance.signedIn) {
      await _openGyms();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on MemberAuthException catch (e) {
      if (mounted) setState(() => _error = memberAuthError(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = memberAuthError('network'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validEmail(String v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim());

  Future<void> _login() => _run(() async {
        if (!_validEmail(_email.text) || _password.text.isEmpty) {
          throw const MemberAuthException('invalid_credentials');
        }
        await MemberAuth.instance.signIn(_email.text, _password.text);
        await _openGyms();
      });

  Future<void> _openGyms() async {
    final gyms = await _repo.myGyms();
    if (!mounted) return;
    if (gyms.length == 1) {
      context.go('/m/${gyms.first['id']}');
      return;
    }
    setState(() => _gyms = gyms);
  }

  Future<void> _forgot() => _run(() async {
        if (!_validEmail(_email.text)) throw const MemberAuthException('invalid_email');
        await MemberAuth.instance.sendPasswordReset(_email.text, '${Uri.base.origin}/espace-membre/connexion');
        if (mounted) setState(() => _info = 'Email envoyé. Ouvrez le lien reçu pour choisir un nouveau mot de passe.');
      });

  Future<void> _savePassword() => _run(() async {
        if (_password.text.length < 8) throw const MemberAuthException('weak_password');
        if (_password.text != _confirm.text) {
          setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
          return;
        }
        await MemberAuth.instance.updatePassword(_password.text);
        if (mounted) setState(() => _recovery = false);
        await _openGyms();
      });

  Future<void> _signOut() async {
    await MemberAuth.instance.signOut();
    if (mounted) setState(() => _gyms = null);
  }

  InputDecoration _deco(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted),
        prefixIcon: Icon(icon, size: 18, color: _muted),
        suffixIcon: suffix,
        filled: true,
        fillColor: _field,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff121417),
      body: SecurGymBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xff1a1d24).withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: .1)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: .45), blurRadius: 36, offset: const Offset(0, 12)),
                  ],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: _muted, padding: EdgeInsets.zero),
                      onPressed: () => context.go('/login'),
                      icon: const Icon(LucideIcons.chevronLeft, size: 18),
                      label: const Text('Retour'),
                    ),
                  ),
                  Center(child: Image.asset('assets/brand/logo_horizontal.png', width: 200, fit: BoxFit.contain)),
                  const SizedBox(height: 12),
                  const Text('Connexion membre',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 22),
                  ..._content(),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content() {
    final messages = [
      if (_error != null) ...[const SizedBox(height: 14), ErrorBox(_error!)],
      if (_info != null) ...[
        const SizedBox(height: 14),
        Text(_info!, style: const TextStyle(color: Color(0xff34d399), fontSize: 13)),
      ],
    ];
    final primary = FilledButton.styleFrom(
      backgroundColor: _brandOrange,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    if (_recovery) {
      return [
        TextField(
          controller: _password,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: _deco('Nouveau mot de passe (8+)', LucideIcons.lock),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: _deco('Confirmer', LucideIcons.lockKeyhole),
        ),
        ...messages,
        const SizedBox(height: 18),
        FilledButton(style: primary, onPressed: _busy ? null : _savePassword, child: const Text('Enregistrer')),
      ];
    }

    if (_gyms != null) {
      return [
        Text(
          _gyms!.isEmpty
              ? 'Aucun gym n’est encore lié à ce compte. Retournez à la liste, choisissez votre gym puis « Activer mon compte ».'
              : 'Choisissez votre gym :',
          style: const TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        for (final g in _gyms!)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: _field,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: GymLogo(
                  path: g['logo_url'] as String?,
                  name: g['name']?.toString() ?? '',
                  size: 40,
                  radius: 10,
                  accent: gymAccent(g['accent_color'] as String?),
                ),
                title: Text(g['name']?.toString() ?? '',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: Text(g['state'] == 'pending' ? 'Inscription en cours' : 'Membre',
                    style: const TextStyle(color: _muted)),
                trailing: const Icon(LucideIcons.chevronRight, color: _muted),
                onTap: () => context.go('/m/${g['id']}'),
              ),
            ),
          ),
        const SizedBox(height: 6),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xff374151)),
            minimumSize: const Size.fromHeight(44),
          ),
          onPressed: () => context.go('/login'),
          child: const Text('Voir la liste des gyms'),
        ),
        TextButton(
          onPressed: _signOut,
          child: const Text('Utiliser un autre compte', style: TextStyle(color: _muted)),
        ),
      ];
    }

    return [
      AutofillGroup(
        child: Column(children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            style: const TextStyle(color: Colors.white),
            decoration: _deco('Email', LucideIcons.mail),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            style: const TextStyle(color: Colors.white),
            onSubmitted: (_) => _login(),
            decoration: _deco(
              'Mot de passe',
              LucideIcons.lock,
              suffix: IconButton(
                icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18, color: _muted),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ]),
      ),
      ...messages,
      const SizedBox(height: 18),
      FilledButton(
        style: primary,
        onPressed: _busy ? null : _login,
        child: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Se connecter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
      TextButton(
        onPressed: _busy ? null : _forgot,
        child: const Text('Mot de passe oublié ?', style: TextStyle(color: _muted)),
      ),
      const SizedBox(height: 4),
      const Text(
        'Première connexion ? Choisissez votre gym dans la liste puis « Activer mon compte ».',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
      ),
    ];
  }
}
