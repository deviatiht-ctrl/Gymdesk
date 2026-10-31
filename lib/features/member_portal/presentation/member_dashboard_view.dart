import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/member_portal_repository.dart';
import 'install_banner.dart';
import 'member_ui.dart';

/// Tableau de bord du membre : abonnement, activité, paiements, gym.
class MemberDashboardView extends StatefulWidget {
  const MemberDashboardView({
    super.key,
    required this.data,
    required this.onRefresh,
    required this.onSignOut,
    required this.onChangeGym,
  });

  final Map<String, dynamic> data;
  final Future<void> Function() onRefresh;
  final VoidCallback onSignOut;
  final VoidCallback onChangeGym;

  @override
  State<MemberDashboardView> createState() => _MemberDashboardViewState();
}

class _MemberDashboardViewState extends State<MemberDashboardView> {
  final _repo = MemberPortalRepository();
  int _tab = 0;
  String? _photoUrl;
  String? _photoPath;

  Map<String, dynamic> get _gym => Map<String, dynamic>.from(widget.data['gym'] as Map? ?? const {});
  Map<String, dynamic> get _member => Map<String, dynamic>.from(widget.data['member'] as Map? ?? const {});
  Map<String, dynamic>? get _sub =>
      widget.data['subscription'] == null ? null : Map<String, dynamic>.from(widget.data['subscription'] as Map);
  Color get _accent => gymAccent(_gym['accent_color'] as String?);
  String get _currency => _gym['currency']?.toString() ?? 'HTG';

  List<Map<String, dynamic>> _list(String key) => (widget.data[key] as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPhoto();
  }

  @override
  void didUpdateWidget(MemberDashboardView old) {
    super.didUpdateWidget(old);
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final path = _member['photo_url'] as String?;
    if (path == _photoPath) return;
    _photoPath = path;
    final url = await _repo.photoUrl(path);
    if (mounted) setState(() => _photoUrl = url);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_home(), _activity(), _payments(), _gymInfo()];
    return Scaffold(
      backgroundColor: memberSurface,
      body: RefreshIndicator(
        color: _accent,
        onRefresh: widget.onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab]),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        backgroundColor: Colors.white,
        indicatorColor: _accent.withAlpha(36),
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(LucideIcons.house), label: 'Accueil'),
          NavigationDestination(icon: Icon(LucideIcons.activity), label: 'Activité'),
          NavigationDestination(icon: Icon(LucideIcons.receipt), label: 'Paiements'),
          NavigationDestination(icon: Icon(LucideIcons.building2), label: 'Mon gym'),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ header
  Widget _header() {
    final first = _member['first_name']?.toString() ?? '';
    final hour = DateTime.now().hour;
    final hello = hour < 12 ? 'Bonjour' : hour < 18 ? 'Bon après-midi' : 'Bonsoir';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [darken(_accent, .28), _accent],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 26),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  GymLogo(path: _gym['logo_url'] as String?, name: _gym['name']?.toString() ?? '', size: 40, radius: 12, accent: _accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_gym['name']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(LucideIcons.ellipsisVertical, color: Colors.white),
                    onSelected: (v) {
                      if (v == 'refresh') widget.onRefresh();
                      if (v == 'gym') widget.onChangeGym();
                      if (v == 'out') widget.onSignOut();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(LucideIcons.refreshCw), title: Text('Actualiser'))),
                      PopupMenuItem(value: 'gym', child: ListTile(leading: Icon(LucideIcons.arrowLeftRight), title: Text('Changer de gym'))),
                      PopupMenuItem(value: 'out', child: ListTile(leading: Icon(LucideIcons.logOut), title: Text('Se déconnecter'))),
                    ],
                  ),
                ]),
                const SizedBox(height: 22),
                Row(children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white.withAlpha(50),
                    backgroundImage: _photoUrl == null ? null : NetworkImage(_photoUrl!),
                    child: _photoUrl == null
                        ? Text(first.isEmpty ? '?' : first[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800))
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$hello,', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                      Text(first, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1)),
                      const SizedBox(height: 4),
                      Text('Membre n° ${_member['member_number'] ?? '—'}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ home
  Widget _home() {
    final announcements = _list('announcements');
    final att = Map<String, dynamic>.from(widget.data['attendance'] as Map? ?? const {});
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InstallBanner(gymId: _gym['id'].toString(), gymName: _gym['name']?.toString() ?? 'Mon gym', accent: _accent),
      const SizedBox(height: 14),
      _subscriptionCard(),
      if (announcements.isNotEmpty) ...[
        const SectionTitle('Messages du gym', icon: LucideIcons.megaphone),
        for (final a in announcements) Padding(padding: const EdgeInsets.only(bottom: 10), child: _announcement(a)),
      ],
      const SectionTitle('Cette période', icon: LucideIcons.flame),
      Row(children: [
        Expanded(child: _statTile('${att['this_month'] ?? 0}', 'Visites ce mois', LucideIcons.calendarCheck)),
        const SizedBox(width: 10),
        Expanded(child: _statTile('${att['last_30'] ?? 0}', '30 derniers jours', LucideIcons.trendingUp)),
        const SizedBox(width: 10),
        Expanded(child: _statTile('${att['total'] ?? 0}', 'Total visites', LucideIcons.trophy)),
      ]),
      const SizedBox(height: 10),
      MemberCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(LucideIcons.clock, color: _accent, size: 20),
          const SizedBox(width: 12),
          const Expanded(child: Text('Dernière visite', style: TextStyle(color: memberMuted))),
          Text(att['last_visit'] == null ? 'Aucune' : fmtDate(att['last_visit'], pattern: 'EEE d MMM · HH:mm'),
              style: const TextStyle(fontWeight: FontWeight.w700, color: memberInk)),
        ]),
      ),
    ]);
  }

  Widget _subscriptionCard() {
    final sub = _sub;
    final pending = widget.data['pending_renewal'] as Map?;
    if (sub == null) {
      return MemberCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Aucun abonnement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: memberInk)),
          const SizedBox(height: 6),
          const Text('Choisissez une formule pour commencer ; l’accueil confirmera votre paiement.',
              style: TextStyle(color: memberMuted)),
          const SizedBox(height: 14),
          _renewButton(pending, label: 'Choisir une formule'),
        ]),
      );
    }
    final status = sub['status']?.toString() ?? 'active';
    final daysLeft = (sub['days_left'] as num?)?.toInt() ?? 0;
    final total = math.max(1, (sub['total_days'] as num?)?.toInt() ?? 30);
    final ratio = status == 'active' ? (daysLeft / total).clamp(0.0, 1.0) : 0.0;
    final balance = (sub['balance'] as num?)?.toDouble() ?? 0;
    final (label, color, icon) = switch (status) {
      'active' when daysLeft <= 3 => ('Expire bientôt', const Color(0xFFF59E0B), LucideIcons.triangleAlert),
      'active' => ('Actif', const Color(0xFF10B981), LucideIcons.circleCheck),
      'upcoming' => ('À venir', const Color(0xFF3B82F6), LucideIcons.calendarClock),
      'pending' => ('Paiement en attente', const Color(0xFFF59E0B), LucideIcons.hourglass),
      'suspended' => ('Suspendu', const Color(0xFFEF4444), LucideIcons.ban),
      _ => ('Expiré', const Color(0xFFEF4444), LucideIcons.circleX),
    };
    return MemberCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 104,
            height: 104,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: ratio,
                  strokeWidth: 10,
                  strokeCap: StrokeCap.round,
                  backgroundColor: color.withAlpha(30),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(status == 'active' ? '$daysLeft' : '0',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: memberInk, height: 1)),
                Text(daysLeft == 1 ? 'jour' : 'jours', style: const TextStyle(color: memberMuted, fontSize: 12)),
              ]),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 5),
                  Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
                ]),
              ),
              const SizedBox(height: 8),
              Text(sub['plan_name']?.toString() ?? 'Abonnement',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: memberInk)),
              const SizedBox(height: 4),
              Text('${fmtDate(sub['start_date'])} → ${fmtDate(sub['end_date'])}',
                  style: const TextStyle(color: memberMuted, fontSize: 13)),
            ]),
          ),
        ]),
        if (balance > 0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(LucideIcons.wallet, color: Color(0xFFB45309), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Solde à régler : ${fmtMoney(balance, sub['currency']?.toString() ?? _currency)}',
                    style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        _renewButton(pending),
      ]),
    );
  }

  Widget _renewButton(Map? pending, {String label = 'Renouveler mon abonnement'}) {
    if (pending != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(LucideIcons.hourglass, color: Color(0xFF2563EB), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Demande de renouvellement envoyée${pending['plan_name'] != null ? ' (${pending['plan_name']})' : ''}. '
              'Passez à l’accueil pour le paiement.',
              style: const TextStyle(color: Color(0xFF1E40AF), fontSize: 13),
            ),
          ),
        ]),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: _openRenewal,
      icon: const Icon(LucideIcons.refreshCw, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Future<void> _openRenewal() async {
    final plans = _list('plans');
    String? selected = plans.isNotEmpty ? plans.first['id'].toString() : null;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Choisir une formule', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text('Votre demande arrive en direct à l’accueil. Le paiement se fait sur place.',
                  style: TextStyle(color: memberMuted)),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .5),
                child: ListView(shrinkWrap: true, children: [
                  for (final p in plans)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: MemberCard(
                        padding: const EdgeInsets.all(14),
                        color: selected == p['id'].toString() ? _accent.withAlpha(20) : Colors.white,
                        onTap: () => setSheet(() => selected = p['id'].toString()),
                        child: Row(children: [
                          Icon(selected == p['id'].toString() ? LucideIcons.circleCheck : LucideIcons.circle,
                              color: selected == p['id'].toString() ? _accent : memberMuted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('${p['duration_days']} jours', style: const TextStyle(color: memberMuted, fontSize: 12)),
                            ]),
                          ),
                          Text(fmtMoney(p['price'], p['currency']?.toString()),
                              style: TextStyle(fontWeight: FontWeight.w900, color: _accent)),
                        ]),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent, minimumSize: const Size.fromHeight(50)),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Envoyer la demande', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status = await _repo.requestRenewal(_gym['id'].toString(), selected);
      messenger.showSnackBar(SnackBar(
        content: Text(status == 'ok' || status == 'already_pending'
            ? 'Demande envoyée ! L’accueil la voit en direct.'
            : memberAuthError(status)),
      ));
      await widget.onRefresh();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(memberAuthError('network'))));
    }
  }

  Widget _announcement(Map<String, dynamic> a) {
    final (color, icon) = switch (a['kind']) {
      'promo' => (const Color(0xFF8B5CF6), LucideIcons.tag),
      'event' => (const Color(0xFF3B82F6), LucideIcons.calendarDays),
      'alert' => (const Color(0xFFEF4444), LucideIcons.triangleAlert),
      _ => (_accent, LucideIcons.megaphone),
    };
    return MemberCard(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(a['title']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: memberInk)),
              ),
              if (a['pinned'] == true) Icon(LucideIcons.pin, size: 14, color: color),
            ]),
            if ((a['body']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(a['body'].toString(), style: const TextStyle(color: Color(0xFF334155), height: 1.4)),
            ],
            const SizedBox(height: 6),
            Text(fmtDate(a['created_at'], pattern: 'd MMM yyyy'), style: const TextStyle(color: memberMuted, fontSize: 11.5)),
          ]),
        ),
      ]),
    );
  }

  Widget _statTile(String value, String label, IconData icon) => MemberCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: _accent),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: memberInk)),
          Text(label, maxLines: 2, style: const TextStyle(fontSize: 11.5, color: memberMuted, height: 1.2)),
        ]),
      );

  // ------------------------------------------------------------------ activity
  Widget _activity() {
    final att = Map<String, dynamic>.from(widget.data['attendance'] as Map? ?? const {});
    final weeks = (att['weeks'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final weekdays = {
      for (final e in (att['weekdays'] as List? ?? const []))
        ((e as Map)['dow'] as num).toInt(): (e['count'] as num).toInt(),
    };
    final maxWeek = weeks.fold<int>(1, (m, w) => math.max(m, (w['count'] as num?)?.toInt() ?? 0));
    final maxDay = weekdays.values.fold<int>(1, math.max);
    const dayNames = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final thisWeek = weeks.isEmpty ? 0 : (weeks.last['count'] as num?)?.toInt() ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Jours d’entraînement par semaine', icon: LucideIcons.chartColumn),
      MemberCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('$thisWeek jour${thisWeek > 1 ? 's' : ''} cette semaine',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: memberInk)),
          Text(thisWeek >= 3 ? 'Excellent rythme, continuez !' : 'Objectif : 3 séances par semaine 💪',
              style: const TextStyle(color: memberMuted, fontSize: 12.5)),
          const SizedBox(height: 18),
          SizedBox(
            height: 150,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < weeks.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('${weeks[i]['count']}', style: const TextStyle(fontSize: 11, color: memberMuted, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        height: 4 + 100 * (((weeks[i]['count'] as num?)?.toInt() ?? 0) / maxWeek),
                        decoration: BoxDecoration(
                          color: i == weeks.length - 1 ? _accent : _accent.withAlpha(90),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(fmtDate(weeks[i]['week'], pattern: 'd/M'), style: const TextStyle(fontSize: 10, color: memberMuted)),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
      const SectionTitle('Vos jours préférés (6 mois)', icon: LucideIcons.calendarRange),
      MemberCard(
        child: Column(children: [
          for (var d = 1; d <= 7; d++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 38, child: Text(dayNames[d - 1], style: const TextStyle(color: memberMuted, fontWeight: FontWeight.w600))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (weekdays[d] ?? 0) / maxDay,
                      minHeight: 10,
                      backgroundColor: memberSurface,
                      valueColor: AlwaysStoppedAnimation(_accent),
                    ),
                  ),
                ),
                SizedBox(width: 34, child: Text('${weekdays[d] ?? 0}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ),
        ]),
      ),
      const SectionTitle('Historique des abonnements', icon: LucideIcons.history),
      for (final s in _list('subscriptions'))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MemberCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Icon(LucideIcons.badgeCheck, color: _accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['plan_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${fmtDate(s['start_date'])} → ${fmtDate(s['end_date'])}',
                      style: const TextStyle(color: memberMuted, fontSize: 12)),
                ]),
              ),
              Text(fmtMoney(s['price'], s['currency']?.toString()), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      if (_list('subscriptions').isEmpty)
        const Padding(padding: EdgeInsets.all(12), child: Text('Aucun abonnement pour l’instant.', style: TextStyle(color: memberMuted))),
    ]);
  }

  // ------------------------------------------------------------------ payments
  Widget _payments() {
    final payments = _list('payments');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Paiements & reçus', icon: LucideIcons.receipt),
      if (payments.isEmpty)
        const Padding(padding: EdgeInsets.all(12), child: Text('Aucun paiement enregistré.', style: TextStyle(color: memberMuted))),
      for (final p in payments)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MemberCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12)),
                child: const Icon(LucideIcons.banknote, color: Color(0xFF059669), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fmtMoney(p['amount'], p['currency']?.toString()),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  Text(
                    [
                      fmtDate(p['paid_at'], pattern: 'd MMM yyyy'),
                      if ((p['reason']?.toString() ?? '').isNotEmpty) p['reason'].toString(),
                      _method(p['method']?.toString()),
                    ].join(' · '),
                    style: const TextStyle(color: memberMuted, fontSize: 12),
                  ),
                ]),
              ),
              if (p['receipt_path'] != null)
                IconButton(
                  tooltip: 'Reçu PDF',
                  icon: Icon(LucideIcons.fileDown, color: _accent),
                  onPressed: () async {
                    final url = await _repo.receiptUrl(p['receipt_path'] as String?);
                    if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                ),
            ]),
          ),
        ),
    ]);
  }

  String _method(String? m) => switch (m) {
        'cash' => 'Espèces',
        'moncash' => 'MonCash',
        'natcash' => 'NatCash',
        'bank' => 'Banque',
        'card' => 'Carte',
        'cheque' => 'Chèque',
        'credit' => 'Crédit',
        _ => 'Autre',
      };

  // ------------------------------------------------------------------ gym
  Widget _gymInfo() {
    final phone = _gym['phone']?.toString() ?? '';
    final email = _gym['email']?.toString() ?? '';
    final address = _gym['address']?.toString() ?? '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Ma carte membre', icon: LucideIcons.idCard),
      MemberCard(
        color: memberInk,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_member['first_name'] ?? ''} ${_member['last_name'] ?? ''}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 4),
              Text('N° ${_member['member_number'] ?? '—'}', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              Row(children: [
                Icon(LucideIcons.fingerprint,
                    size: 16, color: _member['fingerprint_registered'] == true ? const Color(0xFF34D399) : Colors.white38),
                const SizedBox(width: 6),
                Text(_member['fingerprint_registered'] == true ? 'Empreinte enregistrée' : 'Empreinte à enregistrer à l’accueil',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              Text('Membre depuis ${fmtDate(_member['created_at'], pattern: 'MMMM yyyy')}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ]),
          ),
          GymLogo(path: _gym['logo_url'] as String?, name: _gym['name']?.toString() ?? '', size: 58, accent: _accent),
        ]),
      ),
      const SectionTitle('Contacter le gym', icon: LucideIcons.messageCircle),
      if (digits.length >= 8) ...[
        _contact(LucideIcons.messageCircle, 'WhatsApp', phone, () => launchUrl(Uri.parse('https://wa.me/${digits.length == 8 ? '509$digits' : digits}'), mode: LaunchMode.externalApplication)),
        _contact(LucideIcons.phone, 'Appeler', phone, () => launchUrl(Uri.parse('tel:$phone'))),
      ],
      if (email.isNotEmpty) _contact(LucideIcons.mail, 'Email', email, () => launchUrl(Uri.parse('mailto:$email'))),
      if (address.isNotEmpty)
        _contact(LucideIcons.mapPin, 'Adresse', address,
            () => launchUrl(Uri.parse('https://maps.google.com/?q=${Uri.encodeComponent(address)}'), mode: LaunchMode.externalApplication)),
      if (digits.length < 8 && email.isEmpty && address.isEmpty)
        const Padding(padding: EdgeInsets.all(12), child: Text('Coordonnées non renseignées.', style: TextStyle(color: memberMuted))),
      const SizedBox(height: 18),
      Text('Connecté : ${widget.data['email'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(color: memberMuted, fontSize: 12)),
      TextButton.icon(onPressed: widget.onSignOut, icon: const Icon(LucideIcons.logOut, size: 16), label: const Text('Se déconnecter')),
    ]);
  }

  Widget _contact(IconData icon, String title, String value, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: MemberCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          onTap: onTap,
          child: Row(children: [
            Icon(icon, color: _accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(value, style: const TextStyle(color: memberMuted, fontSize: 12.5)),
              ]),
            ),
            const Icon(LucideIcons.chevronRight, color: memberMuted, size: 18),
          ]),
        ),
      );
}
