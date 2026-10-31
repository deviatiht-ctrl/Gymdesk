import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/web/pwa.dart';
import '../data/member_portal_repository.dart';
import '../data/member_session.dart';
import 'member_auth_view.dart';
import 'member_dashboard_view.dart';
import 'member_ui.dart';

/// `/m/<gymId>` : espace membre d'un gym (connexion, suivi de l'inscription,
/// tableau de bord). Installable sur le téléphone avec le logo du gym.
class MemberPortalPage extends StatefulWidget {
  const MemberPortalPage({super.key, required this.gymId, this.requestId});
  final String gymId;
  final String? requestId;

  @override
  State<MemberPortalPage> createState() => _MemberPortalPageState();
}

class _MemberPortalPageState extends State<MemberPortalPage> with WidgetsBindingObserver {
  final _repo = MemberPortalRepository();
  final _auth = MemberAuth.instance;
  Map<String, dynamic>? _gym;
  Map<String, dynamic>? _me;
  bool _loading = true;
  bool _gymMissing = false;
  bool _recovery = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _auth.signedIn) unawaited(_loadMe(silent: true));
  }

  Future<void> _boot() async {
    await _auth.restore();
    try {
      _recovery = await _auth.consumeRecoveryFragment(Uri.base);
    } catch (_) {}
    try {
      final gym = await _repo.gym(widget.gymId);
      if (gym == null) {
        setState(() {
          _gymMissing = true;
          _loading = false;
        });
        return;
      }
      _gym = gym;
      unawaited(_applyManifest(gym));
    } catch (_) {
      setState(() {
        _error = memberAuthError('network');
        _loading = false;
      });
      return;
    }
    if (_auth.signedIn && !_recovery) {
      await _attachPendingRequest();
      await _loadMe();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _applyManifest(Map<String, dynamic> gym) async {
    final logo = await _repo.logoUrl(gym['logo_url'] as String?, seconds: 60 * 60 * 24 * 365 * 5);
    Pwa.setGymManifest(
      name: gym['name']?.toString() ?? 'Espace membre',
      startPath: '/m/${widget.gymId}',
      iconUrl: logo,
      themeColor: gym['accent_color']?.toString(),
    );
  }

  Future<void> _attachPendingRequest() async {
    final id = widget.requestId;
    if (id == null || id.isEmpty) return;
    try {
      await _repo.attachRequest(id);
    } catch (_) {}
  }

  Future<void> _loadMe({bool silent = false}) async {
    if (!_auth.signedIn) return;
    if (!silent && mounted) setState(() => _error = null);
    try {
      final me = await _repo.me(widget.gymId);
      if (!mounted) return;
      setState(() => _me = me);
      _schedulePoll();
    } on PostgrestException catch (e) {
      if (e.code == '42501' || e.message.contains('JWT')) {
        await _auth.signOut();
        if (mounted) setState(() => _me = null);
      } else if (!silent && mounted) {
        setState(() => _error = memberAuthError('network'));
      }
    } catch (_) {
      if (!silent && mounted) setState(() => _error = memberAuthError('network'));
    }
  }

  /// Inscription en cours : suivi en direct (5 s). Membre actif : rafraîchi chaque minute.
  void _schedulePoll() {
    _poll?.cancel();
    final pending = _me?['state'] == 'pending';
    _poll = Timer.periodic(Duration(seconds: pending ? 5 : 60), (_) => _loadMe(silent: true));
  }

  Future<void> _signOut() async {
    _poll?.cancel();
    await _auth.signOut();
    if (mounted) setState(() => _me = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: memberSurface, body: Center(child: CircularProgressIndicator()));
    }
    if (_gymMissing || _gym == null) {
      return _Shell(
        gym: _gym,
        child: Column(children: [
          const Icon(LucideIcons.searchX, size: 44, color: memberMuted),
          const SizedBox(height: 12),
          Text(_error ?? 'Ce gym est introuvable ou n’est plus actif.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => context.go('/espace-membre'), child: const Text('Voir tous les gyms')),
          if (_error != null) TextButton(onPressed: _boot, child: const Text('Réessayer')),
        ]),
      );
    }
    if (_recovery) {
      return _Shell(gym: _gym, child: _NewPasswordForm(gym: _gym!, onDone: () async {
        setState(() => _recovery = false);
        await _loadMe();
      }));
    }
    if (!_auth.signedIn || _me == null) {
      if (_auth.signedIn && _me == null && _error == null) {
        return const Scaffold(backgroundColor: memberSurface, body: Center(child: CircularProgressIndicator()));
      }
      return _Shell(
        gym: _gym,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_error != null) ...[ErrorBox(_error!), const SizedBox(height: 12)],
          if (_auth.signedIn && _error != null)
            FilledButton(onPressed: _loadMe, child: const Text('Réessayer'))
          else
            MemberAuthView(gym: _gym!, onSignedIn: () async {
              await _attachPendingRequest();
              await _loadMe();
            }),
        ]),
      );
    }
    return switch (_me!['state']) {
      'member' => MemberDashboardView(
          data: _me!,
          onRefresh: _loadMe,
          onSignOut: _signOut,
          onChangeGym: () => context.go('/espace-membre'),
        ),
      'pending' || 'rejected' => _Shell(gym: _gym, child: _PendingView(me: _me!, onSignOut: _signOut)),
      'gym_not_found' => _Shell(gym: _gym, child: const Text('Ce gym n’est plus actif.')),
      _ => _Shell(
          gym: _gym,
          child: _LinkView(gym: _gym!, email: _me!['email']?.toString() ?? '', onLinked: _loadMe, onSignOut: _signOut),
        ),
    };
  }
}

/// Mise en page des écrans hors tableau de bord : en-tête gym + carte centrale.
class _Shell extends StatelessWidget {
  const _Shell({required this.gym, required this.child});
  final Map<String, dynamic>? gym;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = gymAccent(gym?['accent_color'] as String?);
    final name = gym?['name']?.toString() ?? 'SecurGYM';
    return Scaffold(
      backgroundColor: memberSurface,
      body: SingleChildScrollView(
        child: Column(children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [darken(accent, .3), accent],
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 70),
                child: Column(children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                      onPressed: () => context.go('/espace-membre'),
                      icon: const Icon(LucideIcons.chevronLeft, size: 18),
                      label: const Text('Tous les gyms'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GymLogo(path: gym?['logo_url'] as String?, name: name, size: 84, radius: 24, accent: accent),
                  const SizedBox(height: 14),
                  Text(name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  const Text('Espace membre', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -46),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: const [BoxShadow(color: Color(0x1F0F172A), blurRadius: 30, offset: Offset(0, 12))],
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Inscription en ligne en attente de validation : suivi en direct.
class _PendingView extends StatelessWidget {
  const _PendingView({required this.me, required this.onSignOut});
  final Map<String, dynamic> me;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final gym = Map<String, dynamic>.from(me['gym'] as Map? ?? const {});
    final accent = gymAccent(gym['accent_color'] as String?);
    final req = Map<String, dynamic>.from(me['request'] as Map? ?? const {});
    final status = req['status']?.toString() ?? 'pending';
    final rejected = me['state'] == 'rejected';
    final step = switch (status) { 'approved' => 2, 'completed' => 3, _ => 1 };
    final steps = [
      ('Demande envoyée', 'Le gym a reçu votre demande en direct.', LucideIcons.send),
      ('Paiement & validation', 'Présentez-vous à l’accueil pour régler et valider.', LucideIcons.wallet),
      ('Empreinte enregistrée', 'L’accueil enregistre votre empreinte pour la porte.', LucideIcons.fingerprint),
      ('Compte activé', 'Votre espace membre s’ouvre automatiquement.', LucideIcons.partyPopper),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(rejected ? 'Demande non retenue' : 'Inscription en cours',
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: memberInk)),
      const SizedBox(height: 6),
      Text(
        rejected
            ? 'Le gym n’a pas validé votre demande. Contactez l’accueil pour plus d’informations.'
            : 'Bonjour ${req['first_name'] ?? ''} ! Votre compte est créé. Il sera activé dès que le gym valide votre inscription — cette page se met à jour toute seule.',
        style: const TextStyle(color: memberMuted, height: 1.4),
      ),
      if (req['plan_name'] != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: accent.withAlpha(20), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(LucideIcons.badgeCheck, color: accent),
            const SizedBox(width: 10),
            Expanded(child: Text(req['plan_name'].toString(), style: const TextStyle(fontWeight: FontWeight.w800))),
            if (req['plan_price'] != null)
              Text(fmtMoney(req['plan_price'], req['plan_currency']?.toString()),
                  style: TextStyle(fontWeight: FontWeight.w900, color: accent)),
          ]),
        ),
      ],
      const SizedBox(height: 18),
      if (!rejected)
        for (var i = 0; i < steps.length; i++)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < step ? accent : (i == step ? accent.withAlpha(40) : memberSurface),
                ),
                child: i == step
                    ? Padding(padding: const EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                    : Icon(i < step ? LucideIcons.check : steps[i].$3, size: 16, color: i < step ? Colors.white : memberMuted),
              ),
              if (i < steps.length - 1)
                Container(width: 2, height: 30, color: i < step ? accent : const Color(0xFFE2E8F0)),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(steps[i].$1,
                      style: TextStyle(fontWeight: FontWeight.w800, color: i <= step ? memberInk : memberMuted)),
                  Text(steps[i].$2, style: const TextStyle(color: memberMuted, fontSize: 12)),
                ]),
              ),
            ),
          ]),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(LucideIcons.radio, size: 14, color: Color(0xFF10B981)),
        const SizedBox(width: 6),
        Text('Suivi en direct · ${me['email'] ?? ''}', style: const TextStyle(color: memberMuted, fontSize: 12)),
      ]),
      TextButton(onPressed: onSignOut, child: const Text('Se déconnecter')),
    ]);
  }
}

/// Connecté mais pas encore lié à un membre de CE gym (isolation par gym).
class _LinkView extends StatefulWidget {
  const _LinkView({required this.gym, required this.email, required this.onLinked, required this.onSignOut});
  final Map<String, dynamic> gym;
  final String email;
  final Future<void> Function() onLinked;
  final VoidCallback onSignOut;

  @override
  State<_LinkView> createState() => _LinkViewState();
}

class _LinkViewState extends State<_LinkView> {
  final _phone = TextEditingController();
  final _number = TextEditingController();
  bool _needNumber = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await MemberPortalRepository()
          .link(gymId: widget.gym['id'].toString(), phone: _phone.text, memberNumber: _number.text);
      if (status == 'ok') {
        await widget.onLinked();
        return;
      }
      setState(() {
        _needNumber = _needNumber || status == 'need_member_number';
        _error = memberAuthError(status);
      });
    } catch (_) {
      setState(() => _error = memberAuthError('network'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = gymAccent(widget.gym['accent_color'] as String?);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Lier mon compte à ${widget.gym['name']}',
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: memberInk)),
      const SizedBox(height: 6),
      Text(
        'Vous êtes connecté avec ${widget.email}. Pour accéder à votre espace dans ce gym, confirmez le téléphone de votre fiche membre.',
        style: const TextStyle(color: memberMuted, height: 1.4),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Téléphone / WhatsApp', prefixIcon: Icon(LucideIcons.phone, size: 18)),
      ),
      if (_needNumber) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _number,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Numéro de membre', prefixIcon: Icon(LucideIcons.idCard, size: 18)),
        ),
      ],
      if (_error != null) ...[const SizedBox(height: 12), ErrorBox(_error!)],
      const SizedBox(height: 16),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size.fromHeight(50)),
        onPressed: _busy ? null : _link,
        child: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Accéder à mon espace', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => context.go('/join/${widget.gym['id']}?account=1'),
        icon: const Icon(LucideIcons.userPlus, size: 18),
        label: const Text('Je ne suis pas encore membre : s’inscrire'),
      ),
      TextButton(onPressed: widget.onSignOut, child: const Text('Utiliser un autre compte')),
    ]);
  }
}

class _NewPasswordForm extends StatefulWidget {
  const _NewPasswordForm({required this.gym, required this.onDone});
  final Map<String, dynamic> gym;
  final Future<void> Function() onDone;

  @override
  State<_NewPasswordForm> createState() => _NewPasswordFormState();
}

class _NewPasswordFormState extends State<_NewPasswordForm> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _error = memberAuthError('weak_password'));
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await MemberAuth.instance.updatePassword(_password.text);
      await widget.onDone();
    } on MemberAuthException catch (e) {
      setState(() => _error = memberAuthError(e.code));
    } catch (_) {
      setState(() => _error = memberAuthError('network'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = gymAccent(widget.gym['accent_color'] as String?);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Nouveau mot de passe', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 14),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Mot de passe (8+)', prefixIcon: Icon(LucideIcons.lock, size: 18)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _confirm,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Confirmer', prefixIcon: Icon(LucideIcons.lockKeyhole, size: 18)),
      ),
      if (_error != null) ...[const SizedBox(height: 12), ErrorBox(_error!)],
      const SizedBox(height: 16),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size.fromHeight(50)),
        onPressed: _busy ? null : _save,
        child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
    ]);
  }
}
