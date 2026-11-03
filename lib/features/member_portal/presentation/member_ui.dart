import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/member_portal_repository.dart';

/// Couleur d'accent du gym (#RRGGBB) avec repli sur le vert SecurGYM.
Color gymAccent(String? hex) {
  final ok = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex ?? '');
  return ok ? Color(0xFF000000 | int.parse(hex!.substring(1), radix: 16)) : const Color(0xFF0F766E);
}

/// Variante foncée pour les dégradés d'en-tête.
Color darken(Color c, [double amount = .35]) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.05, 1.0)).toColor();
}

const memberInk = Color(0xFF0F172A);
const memberMuted = Color(0xFF64748B);
const memberSurface = Color(0xFFF1F5F9);

String fmtDate(Object? value, {String pattern = 'd MMM yyyy'}) {
  final d = value is DateTime ? value : DateTime.tryParse(value?.toString() ?? '');
  if (d == null) return '—';
  return DateFormat(pattern, 'fr').format(d.isUtc ? d.toLocal() : d);
}

String fmtMoney(Object? value, String? currency) {
  final v = (value as num?)?.toDouble() ?? double.tryParse(value?.toString() ?? '') ?? 0;
  final f = NumberFormat.decimalPatternDigits(locale: 'fr', decimalDigits: v == v.roundToDouble() ? 0 : 2);
  return '${f.format(v)} ${currency ?? 'HTG'}';
}

String memberAuthError(String code) => switch (code) {
      'network' => 'Connexion Internet indisponible. Réessayez.',
      'invalid_credentials' => 'Email ou mot de passe incorrect.',
      'account_exists' =>
        'Cet email a déjà un compte SecurGYM. Utilisez votre mot de passe actuel ou « Mot de passe oublié ».',
      'weak_password' => 'Mot de passe trop faible (8 caractères minimum, mélangez lettres et chiffres).',
      'rate_limited' => 'Trop de tentatives. Patientez quelques minutes.',
      'too_many_attempts' => 'Trop de tentatives. Patientez 15 minutes.',
      'email_confirmation_required' => 'Confirmez votre email (lien reçu par email), puis connectez-vous.',
      'invalid_email' => 'Adresse email invalide.',
      'not_found' =>
        'Aucun membre de ce gym ne correspond à cet email et ce téléphone. Vérifiez qu’ils sont identiques à votre fiche à l’accueil.',
      'need_member_number' =>
        'Votre fiche n’a pas d’email : entrez votre numéro de membre (sur votre reçu) pour confirmer votre identité.',
      'already_linked' => 'Ce membre a déjà un compte. Connectez-vous ou utilisez « Mot de passe oublié ».',
      'gym_not_found' => 'Ce gym n’est pas disponible.',
      'phone_not_found' =>
        'Aucun membre actif de ce gym n’a ce numéro. Vérifiez le numéro donné à l’accueil.',
      'invalid_phone' => 'Entrez votre numéro de téléphone (8 chiffres minimum).',
      'phone_login_failed' => 'Connexion impossible. Réessayez.',
      'reset_failed' => 'Impossible d’envoyer l’email de réinitialisation.',
      'password_update_failed' => 'Impossible de changer le mot de passe.',
      _ => 'Une erreur est survenue. Réessayez.',
    };

/// Logo du gym (bucket privé → URL signée), avec repli sur une initiale.
class GymLogo extends StatefulWidget {
  const GymLogo({super.key, required this.path, required this.name, this.size = 56, this.radius = 16, this.accent});
  final String? path;
  final String name;
  final double size;
  final double radius;
  final Color? accent;

  @override
  State<GymLogo> createState() => _GymLogoState();
}

class _GymLogoState extends State<GymLogo> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GymLogo old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  Future<void> _load() async {
    final url = await MemberPortalRepository().logoUrl(widget.path);
    if (mounted) setState(() => _url = url);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? gymAccent(null);
    final initial = widget.name.trim().isEmpty ? 'G' : widget.name.trim()[0].toUpperCase();
    final fallback = Center(
      child: Text(initial,
          style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: widget.size * .42)),
    );
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(widget.radius),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(widget.size * .08),
      child: _url == null
          ? fallback
          : Image.network(_url!, fit: BoxFit.contain, errorBuilder: (_, _, _) => fallback),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon, this.trailing});
  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 18, color: memberMuted), const SizedBox(width: 8)],
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: memberInk, letterSpacing: .2)),
          ),
          ?trailing,
        ]),
      );
}

class MemberCard extends StatelessWidget {
  const MemberCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color, this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: child,
          ),
        ),
      );
}

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(LucideIcons.circleAlert, color: Color(0xFFDC2626), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13, height: 1.35))),
        ]),
      );
}
