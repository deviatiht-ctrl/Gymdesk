import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/member_portal_repository.dart';
import '../data/member_session.dart';
import 'member_ui.dart';

/// Connexion membre / activation du compte pour un membre déjà inscrit au gym.
class MemberAuthView extends StatefulWidget {
  const MemberAuthView({super.key, required this.gym, required this.onSignedIn});
  final Map<String, dynamic> gym;
  final VoidCallback onSignedIn;

  @override
  State<MemberAuthView> createState() => _MemberAuthViewState();
}

class _MemberAuthViewState extends State<MemberAuthView> {
  final _repo = MemberPortalRepository();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _phone = TextEditingController();
  final _number = TextEditingController();
  bool _activate = false;
  bool _phoneMode = true;
  bool _needNumber = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  String get _gymId => widget.gym['id'].toString();
  Color get _accent => gymAccent(widget.gym['accent_color'] as String?);

  @override
  void dispose() {
    for (final c in [_email, _password, _confirm, _phone, _number]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validEmail(String v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim());

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

  Future<void> _login() => _run(() async {
        if (!_validEmail(_email.text) || _password.text.isEmpty) {
          throw const MemberAuthException('invalid_credentials');
        }
        await MemberAuth.instance.signIn(_email.text, _password.text);
        widget.onSignedIn();
      });

  Future<void> _phoneLogin() => _run(() async {
        if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 8) {
          throw const MemberAuthException('invalid_phone');
        }
        try {
          await MemberAuth.instance.signInWithPhone(_gymId, _phone.text);
        } on MemberAuthException catch (e) {
          throw MemberAuthException(e.code == 'not_found' ? 'phone_not_found' : e.code);
        }
        widget.onSignedIn();
      });

  Widget _phoneView() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'Membre de ${widget.gym['name']} ? Entrez le numéro de téléphone de votre fiche.',
          style: const TextStyle(color: memberMuted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: _deco('Numéro de téléphone', LucideIcons.phone, hint: '+509 3700 0000'),
          onSubmitted: (_) => _busy ? null : _phoneLogin(),
        ),
        if (_error != null) ...[const SizedBox(height: 14), ErrorBox(_error!)],
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _busy ? null : _phoneLogin,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Entrer dans mon espace', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _setPhoneMode(false)),
          child: const Text('Se connecter avec email et mot de passe'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: _accent,
            side: BorderSide(color: _accent),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => context.go('/join/$_gymId?account=1'),
          icon: const Icon(LucideIcons.userPlus, size: 18),
          label: const Text('S’inscrire en ligne', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]);

  void _setPhoneMode(bool value) {
    _phoneMode = value;
    _error = null;
  }

  Future<void> _activateAccount() => _run(() async {
        final email = _email.text.trim();
        if (!_validEmail(email)) throw const MemberAuthException('invalid_email');
        if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 8) {
          setState(() => _error = 'Entrez le numéro de téléphone enregistré à l’accueil.');
          return;
        }
        if (_password.text.length < 8) throw const MemberAuthException('weak_password');
        if (_password.text != _confirm.text) {
          setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
          return;
        }
        final status = await _repo.check(gymId: _gymId, email: email, phone: _phone.text, memberNumber: _number.text);
        if (status == 'need_member_number') {
          setState(() {
            _needNumber = true;
            _error = memberAuthError(status);
          });
          return;
        }
        if (status != 'ok') throw MemberAuthException(status);
        await MemberAuth.instance.signUpOrSignIn(email, _password.text);
        final link = await _repo.link(gymId: _gymId, phone: _phone.text, memberNumber: _number.text);
        if (link != 'ok') {
          await MemberAuth.instance.signOut();
          throw MemberAuthException(link);
        }
        widget.onSignedIn();
      });

  Future<void> _forgot() => _run(() async {
        if (!_validEmail(_email.text)) throw const MemberAuthException('invalid_email');
        await MemberAuth.instance.sendPasswordReset(_email.text, '${Uri.base.origin}/m/$_gymId');
        if (mounted) {
          setState(() => _info = 'Email envoyé. Ouvrez le lien reçu sur ce téléphone pour choisir un nouveau mot de passe.');
        }
      });

  InputDecoration _deco(String label, IconData icon, {Widget? suffix, String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        suffixIcon: suffix,
        filled: true,
        fillColor: memberSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _accent, width: 1.6),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_phoneMode) return AutofillGroup(child: _phoneView());
    final eye = IconButton(
      icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
      onPressed: () => setState(() => _obscure = !_obscure),
    );
    return AutofillGroup(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: memberSurface, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            _tab('Connexion', !_activate, () => setState(() => _activate = false)),
            _tab('Activer mon compte', _activate, () => setState(() => _activate = true)),
          ]),
        ),
        const SizedBox(height: 18),
        if (_activate)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'Déjà membre de ${widget.gym['name']} ? Entrez l’email et le téléphone de votre fiche, puis choisissez votre mot de passe.',
              style: const TextStyle(color: memberMuted, fontSize: 13, height: 1.4),
            ),
          ),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: _deco('Email', LucideIcons.mail),
        ),
        const SizedBox(height: 12),
        if (_activate) ...[
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: _deco('Téléphone / WhatsApp de votre fiche', LucideIcons.phone, hint: '+509 3700 0000'),
          ),
          const SizedBox(height: 12),
          if (_needNumber) ...[
            TextField(
              controller: _number,
              textCapitalization: TextCapitalization.characters,
              decoration: _deco('Numéro de membre (sur votre reçu)', LucideIcons.idCard),
            ),
            const SizedBox(height: 12),
          ],
        ],
        TextField(
          controller: _password,
          obscureText: _obscure,
          autofillHints: [_activate ? AutofillHints.newPassword : AutofillHints.password],
          decoration: _deco(_activate ? 'Choisissez un mot de passe (8+)' : 'Mot de passe', LucideIcons.lock, suffix: eye),
          onSubmitted: (_) => _activate ? null : _login(),
        ),
        if (_activate) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.newPassword],
            decoration: _deco('Confirmez le mot de passe', LucideIcons.lockKeyhole),
          ),
        ],
        if (_error != null) ...[const SizedBox(height: 14), ErrorBox(_error!)],
        if (_info != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12)),
            child: Text(_info!, style: const TextStyle(color: Color(0xFF065F46), fontSize: 13)),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _busy ? null : (_activate ? _activateAccount : _login),
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_activate ? 'Activer mon espace membre' : 'Se connecter',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
        if (!_activate)
          TextButton(onPressed: _busy ? null : _forgot, child: const Text('Mot de passe oublié ?')),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _setPhoneMode(true)),
          child: const Text('Se connecter avec mon numéro de téléphone'),
        ),
        const SizedBox(height: 10),
        const Row(children: [
          Expanded(child: Divider()),
          Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Pas encore membre ?', style: TextStyle(color: memberMuted, fontSize: 12))),
          Expanded(child: Divider()),
        ]),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: _accent,
            side: BorderSide(color: _accent),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => context.go('/join/$_gymId?account=1'),
          icon: const Icon(LucideIcons.userPlus, size: 18),
          label: const Text('S’inscrire en ligne', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              boxShadow: selected ? const [BoxShadow(color: Color(0x14000000), blurRadius: 8)] : null,
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected ? memberInk : memberMuted,
                )),
          ),
        ),
      );
}
