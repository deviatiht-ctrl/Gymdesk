import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/member_portal_repository.dart';
import 'member_ui.dart';

const _brandOrange = Color(0xffff6600);
const _panelColor = Color(0xff1a1d24);
const _tileColor = Color(0xff222630);
const _muted = Color(0xff9ca3af);

/// Liste des gyms (thème sombre de la page de connexion) : le membre touche son
/// gym, ou « Se connecter en tant que membre » s'il ne le voit pas.
/// [expand] : la grille défile à l'intérieur du panneau (colonne laptop) ;
/// sinon elle prend sa hauteur naturelle (mobile, dans un scroll parent).
class MemberGymsPanel extends StatefulWidget {
  const MemberGymsPanel({super.key, this.expand = true});
  final bool expand;

  @override
  State<MemberGymsPanel> createState() => _MemberGymsPanelState();
}

class _MemberGymsPanelState extends State<MemberGymsPanel> {
  final _repo = MemberPortalRepository();
  final _search = TextEditingController();
  List<Map<String, dynamic>>? _gyms;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = false);
    try {
      final gyms = await _repo.gyms();
      if (mounted) setState(() => _gyms = gyms);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final gyms = (_gyms ?? const <Map<String, dynamic>>[])
        .where((g) =>
            q.isEmpty ||
            (g['name']?.toString().toLowerCase().contains(q) ?? false) ||
            (g['address']?.toString().toLowerCase().contains(q) ?? false))
        .toList();

    final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: _brandOrange.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
          child: const Icon(LucideIcons.users, color: _brandOrange, size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Espace membre', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            Text('Choisissez votre gym', style: TextStyle(color: _muted, fontSize: 13)),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      TextField(
        controller: _search,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Rechercher un gym…',
          hintStyle: const TextStyle(color: _muted),
          prefixIcon: const Icon(LucideIcons.search, size: 18, color: _muted),
          filled: true,
          fillColor: _tileColor,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
          ),
        ),
      ),
      const SizedBox(height: 14),
    ]);

    final memberButton = SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: _brandOrange),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => context.go('/espace-membre/connexion'),
        icon: const Icon(LucideIcons.logIn, size: 18, color: _brandOrange),
        label: const Text('Se connecter en tant que membre', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );

    final Widget body;
    if (_gyms == null && !_error) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: _brandOrange)),
      );
    } else if (_error) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(children: [
          const Icon(LucideIcons.wifiOff, color: _muted, size: 32),
          const SizedBox(height: 10),
          const Text('Impossible de charger les gyms.', style: TextStyle(color: _muted)),
          TextButton(onPressed: _load, child: const Text('Réessayer', style: TextStyle(color: _brandOrange))),
        ]),
      );
    } else if (gyms.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Text('Aucun gym trouvé.', style: TextStyle(color: _muted))),
      );
    } else {
      body = LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth >= 620 ? 3 : c.maxWidth >= 300 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: !widget.expand,
          physics: widget.expand ? null : const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 150,
          ),
          itemCount: gyms.length,
          itemBuilder: (context, i) => _DarkGymTile(gym: gyms[i]),
        );
      });
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _panelColor.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .45), blurRadius: 36, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (widget.expand) Expanded(child: body) else body,
          const SizedBox(height: 16),
          const Text('Votre gym n’apparaît pas ?', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 8),
          memberButton,
        ],
      ),
    );
  }
}

class _DarkGymTile extends StatelessWidget {
  const _DarkGymTile({required this.gym});
  final Map<String, dynamic> gym;

  @override
  Widget build(BuildContext context) {
    final accent = gymAccent(gym['accent_color'] as String?);
    final name = gym['name']?.toString() ?? 'Gym';
    final address = gym['address']?.toString() ?? '';
    return Material(
      color: _tileColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        hoverColor: _brandOrange.withValues(alpha: .08),
        onTap: () => context.go('/m/${gym['id']}'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Center(child: GymLogo(path: gym['logo_url'] as String?, name: name, size: 64, accent: accent)),
            ),
            const SizedBox(height: 10),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
            Text(address.isEmpty ? 'Connexion membre' : address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 11.5)),
          ]),
        ),
      ),
    );
  }
}
