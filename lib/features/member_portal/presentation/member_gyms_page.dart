import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/member_portal_repository.dart';
import 'member_ui.dart';

/// /espace-membre : tous les gyms SecurGYM avec leur logo. Le membre choisit
/// le sien pour se connecter ou s'inscrire.
class MemberGymsPage extends StatefulWidget {
  const MemberGymsPage({super.key});

  @override
  State<MemberGymsPage> createState() => _MemberGymsPageState();
}

class _MemberGymsPageState extends State<MemberGymsPage> {
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
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 1100 ? 4 : width > 760 ? 3 : 2;

    return Scaffold(
      backgroundColor: memberSurface,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B1220), Color(0xFF0F3D3A), Color(0xFF0F766E)],
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(30),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(LucideIcons.shieldCheck, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Text('SecurGYM',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => context.go('/login'),
                            style: TextButton.styleFrom(foregroundColor: Colors.white70),
                            icon: const Icon(LucideIcons.building2, size: 16),
                            label: const Text('Propriétaire'),
                          ),
                        ]),
                        const SizedBox(height: 26),
                        const Text('Espace membre',
                            style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1)),
                        const SizedBox(height: 8),
                        const Text(
                          'Choisissez votre gym pour suivre votre abonnement, vos visites et les messages de votre salle.',
                          style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _search,
                          style: const TextStyle(color: memberInk),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            hintText: 'Rechercher un gym…',
                            prefixIcon: const Icon(LucideIcons.search, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_gyms == null && !_error)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (_error)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(LucideIcons.wifiOff, size: 40, color: memberMuted),
                  const SizedBox(height: 12),
                  const Text('Impossible de charger les gyms.', style: TextStyle(color: memberMuted)),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _load, icon: const Icon(LucideIcons.refreshCw, size: 16), label: const Text('Réessayer')),
                ]),
              ),
            )
          else if (gyms.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Aucun gym trouvé.', style: TextStyle(color: memberMuted))),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: width > 1150 ? (width - 1100) / 2 : 18, vertical: 22),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: .82,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _GymTile(gym: gyms[i]),
                  childCount: gyms.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 30)),
        ]),
      ),
    );
  }
}

class _GymTile extends StatelessWidget {
  const _GymTile({required this.gym});
  final Map<String, dynamic> gym;

  @override
  Widget build(BuildContext context) {
    final accent = gymAccent(gym['accent_color'] as String?);
    final name = gym['name']?.toString() ?? 'Gym';
    final address = gym['address']?.toString() ?? '';
    return MemberCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context.go('/m/${gym['id']}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [accent.withAlpha(36), accent.withAlpha(12)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(child: GymLogo(path: gym['logo_url'] as String?, name: name, size: 74, accent: accent)),
          ),
        ),
        const SizedBox(height: 12),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: memberInk)),
        const SizedBox(height: 2),
        Text(address.isEmpty ? 'Connexion membre' : address,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: memberMuted)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(12)),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(LucideIcons.logIn, size: 15, color: Colors.white),
            SizedBox(width: 6),
            Text('Connexion membre', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        ),
      ]),
    );
  }
}
