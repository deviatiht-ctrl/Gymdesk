import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../badges/data/whatsapp_service.dart';
import '../data/member_account_admin.dart';
import 'member_ui.dart';

/// Génère un mot de passe lisible à communiquer au membre (pas de 0/O/1/l).
String generateMemberPassword() {
  const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final rng = Random.secure();
  final raw = List.generate(10, (_) => chars[rng.nextInt(chars.length)]).join();
  return '${raw.substring(0, 4)}-${raw.substring(4, 8)}${raw.substring(8)}';
}

/// Fenêtre « accès espace membre » côté personnel : définit/réinitialise le
/// mot de passe du membre via l'Edge Function manage_member_account.
/// `account` (ligne member_accounts, ou null) sert à afficher l'état actuel.
Future<bool> showMemberAccessSheet(
  BuildContext context, {
  required SupabaseClient client,
  required String gymId,
  required String memberId,
  required String memberName,
  String? memberEmail,
  String? memberPhone,
  Map<String, dynamic>? account,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _MemberAccessSheet(
        client: client,
        gymId: gymId,
        memberId: memberId,
        memberName: memberName,
        memberEmail: memberEmail,
        memberPhone: memberPhone,
        account: account,
      ),
    ),
  );
  return result == true;
}

class _MemberAccessSheet extends StatefulWidget {
  const _MemberAccessSheet({
    required this.client,
    required this.gymId,
    required this.memberId,
    required this.memberName,
    required this.memberEmail,
    required this.memberPhone,
    required this.account,
  });
  final SupabaseClient client;
  final String gymId;
  final String memberId;
  final String memberName;
  final String? memberEmail;
  final String? memberPhone;
  final Map<String, dynamic>? account;

  @override
  State<_MemberAccessSheet> createState() => _MemberAccessSheetState();
}

class _MemberAccessSheetState extends State<_MemberAccessSheet> {
  late final TextEditingController _email;
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _done;
  ({String email, String password})? _sent;

  bool get _hasAccount => widget.account != null;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(
      text: (widget.account?['email'] ?? widget.memberEmail ?? '').toString(),
    );
    _password.text = generateMemberPassword();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    try {
      final password = _password.text;
      final result = await MemberAccountAdmin(widget.client).setPassword(
        gymId: widget.gymId,
        memberId: widget.memberId,
        email: _email.text,
        password: password,
      );
      if (!mounted) return;
      setState(() {
        _sent = (email: result.email, password: password);
        _done = result.emailSent
            ? 'Accès créé. Les identifiants ont été envoyés automatiquement par email à ${result.email}.'
            : 'Accès créé pour ${result.email}, mais l’email n’a pas pu être envoyé. Envoyez les identifiants par WhatsApp.';
      });
    } on MemberAccountException catch (e) {
      setState(() => _error = memberAccountError(e.code));
    } catch (_) {
      setState(() => _error = memberAccountError('network'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendWhatsApp() async {
    final sent = _sent;
    if (sent == null) return;
    final message = 'Bonjour ${widget.memberName},\n\n'
        'Votre accès à l’espace membre est prêt.\n'
        '• Lien : https://securgym.com/m/${widget.gymId}\n'
        '• Email : ${sent.email}\n'
        '• Mot de passe : ${sent.password}\n\n'
        'Ce mot de passe est personnel, ne le partagez avec personne.';
    final phone = WhatsAppService.formatPhoneNumber(widget.memberPhone ?? '');
    final uri = Uri.parse('https://wa.me/${phone.length >= 8 ? phone : ''}?text=${Uri.encodeComponent(message)}');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d’ouvrir WhatsApp.')));
    }
  }

  Future<void> _revoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer l’accès ?'),
        content: const Text('Le membre ne pourra plus se connecter à son espace. Ses données restent intactes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await MemberAccountAdmin(widget.client).revoke(gymId: widget.gymId, memberId: widget.memberId);
      if (mounted) Navigator.pop(context, true);
    } on MemberAccountException catch (e) {
      setState(() {
        _busy = false;
        _error = memberAccountError(e.code);
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _error = memberAccountError('network');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Espace membre — ${widget.memberName}',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: memberInk)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(
              _hasAccount ? LucideIcons.circleCheck : LucideIcons.circleOff,
              size: 16,
              color: _hasAccount ? const Color(0xFF059669) : memberMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _hasAccount
                    ? 'Compte actif${account?['last_seen_at'] != null ? ' · vu ${fmtDate(account?['last_seen_at'], pattern: 'd MMM · HH:mm')}' : ''}'
                    : 'Aucun accès : définissez un mot de passe pour l’activer.',
                style: const TextStyle(color: memberMuted, fontSize: 13),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email de connexion du membre',
              prefixIcon: Icon(LucideIcons.mail, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Mot de passe (8 caractères min.)',
              prefixIcon: const Icon(LucideIcons.lock, size: 18),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Afficher',
                  icon: Icon(_showPassword ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
                IconButton(
                  tooltip: 'Copier',
                  icon: const Icon(LucideIcons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _password.text));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Mot de passe copié.')));
                  },
                ),
                IconButton(
                  tooltip: 'Générer',
                  icon: const Icon(LucideIcons.dices, size: 18),
                  onPressed: () => setState(() => _password.text = generateMemberPassword()),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Le mot de passe remplace l’ancien si le membre avait déjà un accès. Il est envoyé automatiquement au membre par email ; vous pouvez aussi l’envoyer par WhatsApp.',
            style: TextStyle(color: memberMuted, fontSize: 12, height: 1.35),
          ),
          if (_error != null) ...[const SizedBox(height: 12), ErrorBox(_error!)],
          if (_done != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(children: [
                const Icon(LucideIcons.circleCheck, color: Color(0xFF059669), size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(_done!, style: const TextStyle(color: Color(0xFF065F46), fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF128C7E),
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: _sendWhatsApp,
              icon: const Icon(LucideIcons.messageCircle, size: 18),
              label: const Text('Envoyer aussi par WhatsApp', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _busy ? null : _save,
            icon: const Icon(LucideIcons.keyRound, size: 18),
            label: Text(_hasAccount ? 'Réinitialiser le mot de passe' : 'Créer l’accès',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (_hasAccount)
            TextButton.icon(
              onPressed: _busy ? null : _revoke,
              icon: const Icon(LucideIcons.userX, size: 16, color: Color(0xFFDC2626)),
              label: const Text('Retirer l’accès', style: TextStyle(color: Color(0xFFDC2626))),
            ),
        ]),
      ),
    );
  }
}
