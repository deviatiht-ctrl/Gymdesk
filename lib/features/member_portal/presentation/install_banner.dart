import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/web/pwa.dart';
import 'member_ui.dart';

/// Invite le membre à installer l'espace membre (logo du gym) sur son téléphone.
class InstallBanner extends StatefulWidget {
  const InstallBanner({super.key, required this.gymId, required this.gymName, required this.accent});
  final String gymId;
  final String gymName;
  final Color accent;

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

class _InstallBannerState extends State<InstallBanner> {
  static const _storage = FlutterSecureStorage();
  bool _hidden = true;
  bool _canPrompt = false;
  Timer? _poll;

  String get _key => 'securgym:install_dismissed:${widget.gymId}';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!Pwa.supported || Pwa.isStandalone) return;
    String? dismissed;
    try {
      dismissed = await _storage.read(key: _key);
    } catch (_) {}
    final at = DateTime.tryParse(dismissed ?? '');
    // Masqué 3 jours après « Plus tard », puis on le repropose.
    if (at != null && DateTime.now().difference(at) < const Duration(days: 3)) return;
    if (!mounted) return;
    setState(() {
      _hidden = false;
      _canPrompt = Pwa.canPrompt;
    });
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      final can = Pwa.canPrompt;
      if (mounted && can != _canPrompt) setState(() => _canPrompt = can);
      if (Pwa.isStandalone && mounted) setState(() => _hidden = true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _later() async {
    setState(() => _hidden = true);
    try {
      await _storage.write(key: _key, value: DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<void> _install() async {
    if (_canPrompt) {
      final outcome = await Pwa.prompt();
      if (outcome == 'accepted' && mounted) setState(() => _hidden = true);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => _InstructionsSheet(gymName: widget.gymName, ios: Pwa.isIos, accent: widget.accent),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [widget.accent, darken(widget.accent, .18)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: widget.accent.withAlpha(70), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(14)),
          child: const Icon(LucideIcons.smartphone, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Installez ${widget.gymName} sur votre téléphone',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 2),
            const Text('Accès en un clic depuis l’écran d’accueil, avec le logo de votre gym.',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3)),
          ]),
        ),
        const SizedBox(width: 6),
        Column(mainAxisSize: MainAxisSize.min, children: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: widget.accent,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _install,
            child: const Text('Installer', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white70, visualDensity: VisualDensity.compact),
            onPressed: _later,
            child: const Text('Plus tard', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ]),
    );
  }
}

class _InstructionsSheet extends StatelessWidget {
  const _InstructionsSheet({required this.gymName, required this.ios, required this.accent});
  final String gymName;
  final bool ios;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final steps = ios
        ? const [
            (LucideIcons.compass, 'Ouvrez cette page dans Safari.'),
            (LucideIcons.share, 'Touchez le bouton Partager (carré avec une flèche) en bas de l’écran.'),
            (LucideIcons.squarePlus, 'Choisissez « Sur l’écran d’accueil », puis « Ajouter ».'),
          ]
        : const [
            (LucideIcons.globe, 'Ouvrez cette page dans Chrome.'),
            (LucideIcons.ellipsisVertical, 'Touchez le menu ⋮ en haut à droite.'),
            (LucideIcons.squarePlus, 'Choisissez « Installer l’application » ou « Ajouter à l’écran d’accueil ».'),
          ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Installer $gymName', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: memberInk)),
          const SizedBox(height: 6),
          const Text('L’application s’ouvrira directement sur votre espace membre.', style: TextStyle(color: memberMuted)),
          const SizedBox(height: 18),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: accent.withAlpha(30),
                  child: Text('${i + 1}', style: TextStyle(color: accent, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Icon(steps[i].$1, size: 20, color: accent),
                const SizedBox(width: 10),
                Expanded(child: Text(steps[i].$2, style: const TextStyle(fontSize: 14, height: 1.35))),
              ]),
            ),
        ]),
      ),
    );
  }
}
