import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../members/data/members_repository.dart';
import 'member_access.dart';
import 'member_ui.dart';

/// Modèles de messages prêts à publier (kind, titre, corps).
const _templates = <(String, String, String)>[
  ('info', 'Bienvenue !', 'Bienvenue dans votre espace membre : abonnement, visites et messages du gym en direct, installable sur votre téléphone.'),
  ('info', 'Nouveaux horaires', 'À partir du …, la salle ouvre de … à ….'),
  ('alert', 'Fermeture exceptionnelle', 'La salle sera fermée le …. Réouverture le …. Merci de votre compréhension.'),
  ('alert', 'Rappel de paiement', 'Pensez à régler votre abonnement avant la fin de votre période pour garder l’accès à la salle.'),
  ('promo', 'Promotion en cours', 'Profitez de … sur les abonnements … jusqu’au …. Renseignez-vous à l’accueil.'),
  ('event', 'Événement', 'Rejoignez-nous le … pour …. Inscription à l’accueil.'),
];

/// Côté propriétaire : membres et accès, messagerie membre ↔ gym,
/// annonces publiées, lien/QR de l'espace membre.
class MemberSpaceAdminPage extends ConsumerStatefulWidget {
  const MemberSpaceAdminPage({super.key});

  @override
  ConsumerState<MemberSpaceAdminPage> createState() => _MemberSpaceAdminPageState();
}

class _MemberSpaceAdminPageState extends ConsumerState<MemberSpaceAdminPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  MembersRepository? _members;
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _notMigrated = false;
  String _query = '';

  String get _gymId => ref.read(appRuntimeProvider).session?.gymId ?? '';
  String get _url => 'https://securgym.com/m/$_gymId';
  Map<String, Map<String, dynamic>> get _accountsByMember => {
        for (final a in _accounts) a['member_id'].toString(): a,
      };

  int get _unread => _messages
      .where((m) => m['sender'] == 'member' && m['read_by_gym_at'] == null)
      .length;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this)..addListener(() => setState(() {}));
    final runtime = ref.read(appRuntimeProvider);
    final db = runtime.database;
    final session = runtime.session;
    if (db != null && session != null) {
      _members = MembersRepository(runtime.client, db, session);
    }
    _load();
    _channel = runtime.client
        .channel('member-space:$_gymId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'member_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gym_id', value: _gymId),
          callback: (_) => _loadMessages(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _tabs.dispose();
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(ref.read(appRuntimeProvider).client.removeChannel(channel));
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await Future.wait([_loadRemoteTables(), _loadMessages()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRemoteTables() async {
    final client = ref.read(appRuntimeProvider).client;
    try {
      final results = await Future.wait([
        client.from('gym_announcements').select().eq('gym_id', _gymId).order('created_at', ascending: false),
        client
            .from('member_accounts')
            .select('id, member_id, email, created_at, last_seen_at')
            .eq('gym_id', _gymId)
            .order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _announcements = (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _accounts = (results[1] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _notMigrated = false;
      });
    } catch (_) {
      if (mounted) setState(() => _notMigrated = true);
    }
  }

  Future<void> _loadMessages() async {
    try {
      final rows = await ref
          .read(appRuntimeProvider)
          .client
          .from('member_messages')
          .select('id, member_id, sender, body, created_at, read_by_gym_at, '
              'members(first_name, last_name, member_number)')
          .eq('gym_id', _gymId)
          .order('created_at', ascending: false)
          .limit(400);
      if (!mounted) return;
      setState(() => _messages = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (_) {}
  }

  // --------------------------------------------------------------- membres
  Future<void> _memberAccess(MemberListEntry entry) async {
    final account = _accountsByMember[entry.member.id];
    final changed = await showMemberAccessSheet(
      context,
      client: ref.read(appRuntimeProvider).client,
      gymId: _gymId,
      memberId: entry.member.id,
      memberName: '${entry.member.firstName} ${entry.member.lastName}'.trim(),
      memberEmail: entry.member.email,
      account: account,
    );
    if (changed || mounted) await _loadRemoteTables();
  }

  Widget _membersTab() {
    final members = _members;
    if (members == null) {
      return const Center(child: Text('Base locale indisponible.'));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'Rechercher un membre…',
            prefixIcon: Icon(LucideIcons.search, size: 18),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      Expanded(
        child: StreamBuilder<List<MemberListEntry>>(
          stream: members.watch(query: _query),
          builder: (context, snapshot) {
            final entries = snapshot.data ?? [];
            final accounts = _accountsByMember;
            final active = entries.where((e) => accounts.containsKey(e.member.id)).length;
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '${entries.length} membre${entries.length > 1 ? 's' : ''} · $active compte${active > 1 ? 's' : ''} espace membre',
                    style: const TextStyle(color: memberMuted, fontSize: 12.5),
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting && entries.isEmpty)
                  const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
                else if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Aucun membre ne correspond.', style: TextStyle(color: memberMuted)),
                  ),
                for (final entry in entries) _memberTile(entry, accounts[entry.member.id]),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _memberTile(MemberListEntry entry, Map<String, dynamic>? account) {
    final member = entry.member;
    final hasAccount = account != null;
    return Card(
      child: ListTile(
        onTap: () => _memberAccess(entry),
        leading: CircleAvatar(child: Text(member.firstName.isEmpty ? '?' : member.firstName[0].toUpperCase())),
        title: Text(member.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${member.memberNumber} · '
          '${hasAccount ? 'Compte actif${account['last_seen_at'] != null ? ' · vu ${fmtDate(account['last_seen_at'], pattern: 'd MMM')}' : ''}' : 'Pas d’accès espace membre'}',
          style: TextStyle(color: hasAccount ? const Color(0xFF059669) : memberMuted, fontSize: 12.5),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            hasAccount ? LucideIcons.smartphone : LucideIcons.userX,
            size: 18,
            color: hasAccount ? const Color(0xFF059669) : memberMuted,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'access') _memberAccess(entry);
              if (v == 'open') context.go('/members/${member.id}');
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'access', child: Text('Accès / mot de passe…')),
              const PopupMenuItem(value: 'open', child: Text('Ouvrir la fiche')),
            ],
          ),
        ]),
      ),
    );
  }

  // --------------------------------------------------------------- messages
  Widget _messagesTab() {
    final byMember = <String, List<Map<String, dynamic>>>{};
    for (final m in _messages) {
      byMember.putIfAbsent(m['member_id'].toString(), () => []).add(m);
    }
    final conversations = byMember.entries.toList()
      ..sort((a, b) => (b.value.first['created_at'] ?? '').toString().compareTo((a.value.first['created_at'] ?? '').toString()));
    if (conversations.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Text('Aucun message de membre. Quand un membre écrit depuis son espace, il apparaît ici en direct.',
              textAlign: TextAlign.center, style: TextStyle(color: memberMuted)),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 90), children: [
      for (final conv in conversations) _conversationTile(conv.key, conv.value),
    ]);
  }

  Widget _conversationTile(String memberId, List<Map<String, dynamic>> messages) {
    final member = Map<String, dynamic>.from(messages.first['members'] as Map? ?? const {});
    final last = messages.first;
    final unread = messages.where((m) => m['sender'] == 'member' && m['read_by_gym_at'] == null).length;
    final name = '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim();
    return Card(
      child: ListTile(
        onTap: () => _openThread(memberId, name.isEmpty ? 'Membre' : name, member['member_number']?.toString() ?? ''),
        leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
        title: Text(name.isEmpty ? 'Membre' : name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${last['sender'] == 'gym' ? 'Vous : ' : ''}${last['body']}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fmtDate(last['created_at'], pattern: 'd MMM HH:mm'), style: const TextStyle(color: memberMuted, fontSize: 11)),
          if (unread > 0)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(10)),
              child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
        ]),
      ),
    );
  }

  Future<void> _openThread(String memberId, String name, String number) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MemberThreadSheet(
        client: ref.read(appRuntimeProvider).client,
        gymId: _gymId,
        memberId: memberId,
        memberName: number.isEmpty ? name : '$name · $number',
        onChanged: _loadMessages,
      ),
    );
    await _markRead(memberId);
  }

  Future<void> _markRead(String memberId) async {
    try {
      await ref
          .read(appRuntimeProvider)
          .client
          .from('member_messages')
          .update({'read_by_gym_at': DateTime.now().toUtc().toIso8601String()})
          .eq('gym_id', _gymId)
          .eq('member_id', memberId)
          .eq('sender', 'member')
          .isFilter('read_by_gym_at', null);
      await _loadMessages();
    } catch (_) {}
  }

  // --------------------------------------------------------------- annonces
  Future<void> _editAnnouncement([Map<String, dynamic>? existing]) async {
    final title = TextEditingController(text: existing?['title']?.toString() ?? '');
    final body = TextEditingController(text: existing?['body']?.toString() ?? '');
    var kind = existing?['kind']?.toString() ?? 'info';
    var pinned = existing?['pinned'] == true;
    var active = existing?['active'] != false;
    DateTime? endsAt = DateTime.tryParse(existing?['ends_at']?.toString() ?? '')?.toLocal();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(existing == null ? 'Nouveau message aux membres' : 'Modifier le message'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (existing == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DropdownButtonFormField<int>(
                      initialValue: null,
                      decoration: const InputDecoration(
                        labelText: 'Modèle prêt à l’emploi (optionnel)',
                        prefixIcon: Icon(LucideIcons.layoutTemplate, size: 18),
                      ),
                      items: [
                        for (var i = 0; i < _templates.length; i++)
                          DropdownMenuItem(value: i, child: Text(_templates[i].$2)),
                      ],
                      onChanged: (i) {
                        if (i == null) return;
                        setD(() {
                          kind = _templates[i].$1;
                          title.text = _templates[i].$2;
                          body.text = _templates[i].$3;
                        });
                      },
                    ),
                  ),
                TextField(controller: title, maxLength: 140, decoration: const InputDecoration(labelText: 'Titre *')),
                TextField(
                  controller: body,
                  maxLines: 5,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'info', label: Text('Info'), icon: Icon(LucideIcons.megaphone, size: 14)),
                    ButtonSegment(value: 'promo', label: Text('Promo'), icon: Icon(LucideIcons.tag, size: 14)),
                    ButtonSegment(value: 'event', label: Text('Événement'), icon: Icon(LucideIcons.calendarDays, size: 14)),
                    ButtonSegment(value: 'alert', label: Text('Alerte'), icon: Icon(LucideIcons.triangleAlert, size: 14)),
                  ],
                  selected: {kind},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setD(() => kind = v.first),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pinned,
                  onChanged: (v) => setD(() => pinned = v),
                  title: const Text('Épingler en haut'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (v) => setD(() => active = v),
                  title: const Text('Visible par les membres'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(LucideIcons.calendarX),
                  title: Text(endsAt == null ? 'Sans date de fin' : 'Visible jusqu’au ${fmtDate(endsAt)}'),
                  trailing: endsAt == null
                      ? null
                      : IconButton(icon: const Icon(LucideIcons.x), onPressed: () => setD(() => endsAt = null)),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                      initialDate: endsAt ?? now.add(const Duration(days: 7)),
                    );
                    if (picked != null) setD(() => endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59));
                  },
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty) return;
                Navigator.pop(context, true);
              },
              child: const Text('Publier'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final client = ref.read(appRuntimeProvider).client;
    final row = {
      'title': title.text.trim(),
      'body': body.text.trim(),
      'kind': kind,
      'pinned': pinned,
      'active': active,
      'ends_at': endsAt?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (existing == null) {
        await client.from('gym_announcements').insert({...row, 'gym_id': _gymId});
      } else {
        await client.from('gym_announcements').update(row).eq('id', existing['id'] as Object);
      }
      await _loadRemoteTables();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _deleteAnnouncement(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('Supprimer ce message ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(appRuntimeProvider).client.from('gym_announcements').delete().eq('id', id);
      await _loadRemoteTables();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Widget _announcementsTab() {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
      if (_announcements.isEmpty)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Aucun message. Publiez une info (horaires, promo, événement) : elle s’affiche dans l’app de chaque membre.',
            style: TextStyle(color: memberMuted),
          ),
        ),
      for (final a in _announcements)
        Card(
          child: ListTile(
            leading: Icon(a['pinned'] == true ? LucideIcons.pin : LucideIcons.megaphone,
                color: a['active'] == true ? Theme.of(context).colorScheme.primary : memberMuted),
            title: Text(a['title']?.toString() ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: a['active'] == true ? null : TextDecoration.lineThrough,
                )),
            subtitle: Text(
              [
                if ((a['body']?.toString() ?? '').isNotEmpty) a['body'].toString(),
                '${fmtDate(a['created_at'])}${a['ends_at'] != null ? ' → ${fmtDate(a['ends_at'])}' : ''}',
              ].join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _editAnnouncement(a),
            trailing: IconButton(
              icon: const Icon(LucideIcons.trash2, color: Color(0xFFDC2626)),
              onPressed: () => _deleteAnnouncement(a['id'].toString()),
            ),
          ),
        ),
    ]);
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appRuntimeProvider).session;
    final gymName = session?.name ?? 'Mon gym';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace membre'),
        actions: [IconButton(onPressed: _load, icon: const Icon(LucideIcons.refreshCw))],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Membres', icon: Icon(LucideIcons.users, size: 18)),
            Tab(
              text: 'Messages',
              icon: _unread > 0
                  ? Badge(label: Text('$_unread'), child: const Icon(LucideIcons.messagesSquare, size: 18))
                  : const Icon(LucideIcons.messagesSquare, size: 18),
            ),
            Tab(text: 'Annonces (${_announcements.length})', icon: const Icon(LucideIcons.megaphone, size: 18)),
            const Tab(text: 'Lien', icon: Icon(LucideIcons.qrCode, size: 18)),
          ],
        ),
      ),
      floatingActionButton: _notMigrated || _tabs.index != 2
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editAnnouncement(),
              icon: const Icon(LucideIcons.megaphone),
              label: const Text('Nouveau message'),
            ),
      body: Column(children: [
        if (_notMigrated)
          const Padding(
            padding: EdgeInsets.all(12),
            child: ErrorBox(
              'L’espace membre n’est pas encore activé sur le serveur : appliquez la migration supabase/sql/34_member_portal.sql.',
            ),
          ),
        Expanded(
          child: _loading && _announcements.isEmpty && _accounts.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _membersTab(),
                    RefreshIndicator(onRefresh: _loadMessages, child: _messagesTab()),
                    _announcementsTab(),
                    ListView(padding: const EdgeInsets.all(16), children: [_linkCard(gymName)]),
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _linkCard(String gymName) {
    final message = 'Bienvenue chez $gymName ! Activez votre espace membre (abonnement, visites, messages du gym) '
        'et installez l’app sur votre téléphone : $_url';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(builder: (context, c) {
          final qr = Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: QrImageView(data: _url, size: 170, gapless: true),
          );
          final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Lien de votre espace membre', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
              'Affichez ce QR à l’accueil. Les membres actuels activent leur compte avec leur email + téléphone de leur fiche ; '
              'vous pouvez aussi leur créer un accès directement depuis l’onglet Membres.',
              style: TextStyle(color: memberMuted, height: 1.4),
            ),
            const SizedBox(height: 10),
            SelectableText(_url, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _url));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié')));
                },
                icon: const Icon(LucideIcons.copy, size: 16),
                label: const Text('Copier'),
              ),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}'),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(LucideIcons.messageCircle, size: 16),
                label: const Text('Partager WhatsApp'),
              ),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication),
                icon: const Icon(LucideIcons.externalLink, size: 16),
                label: const Text('Ouvrir'),
              ),
            ]),
          ]);
          return c.maxWidth > 640
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [qr, const SizedBox(width: 20), Expanded(child: info)])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Center(child: qr), const SizedBox(height: 16), info]);
        }),
      ),
    );
  }
}

/// Conversation membre ↔ gym : fil des messages + réponse de l'accueil.
class _MemberThreadSheet extends StatefulWidget {
  const _MemberThreadSheet({
    required this.client,
    required this.gymId,
    required this.memberId,
    required this.memberName,
    required this.onChanged,
  });
  final SupabaseClient client;
  final String gymId;
  final String memberId;
  final String memberName;
  final Future<void> Function() onChanged;

  @override
  State<_MemberThreadSheet> createState() => _MemberThreadSheetState();
}

class _MemberThreadSheetState extends State<_MemberThreadSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = widget.client
        .channel('thread:${widget.memberId}:${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'member_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'member_id', value: widget.memberId),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(widget.client.removeChannel(channel));
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.client
          .from('member_messages')
          .select('id, sender, body, created_at, read_by_gym_at, read_by_member_at')
          .eq('gym_id', widget.gymId)
          .eq('member_id', widget.memberId)
          .order('created_at')
          .limit(200);
      if (!mounted) return;
      setState(() => _messages = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (_) {}
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.client.from('member_messages').insert({
        'gym_id': widget.gymId,
        'member_id': widget.memberId,
        'sender': 'gym',
        'body': body,
        'read_by_gym_at': DateTime.now().toUtc().toIso8601String(),
      });
      _input.clear();
      await _load();
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Envoi impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              const Icon(LucideIcons.messagesSquare, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.memberName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('Aucun message. Écrivez la première réponse.', style: TextStyle(color: memberMuted)))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final mine = m['sender'] == 'gym';
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .72),
                          decoration: BoxDecoration(
                            color: mine ? accent : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(mine ? 16 : 4),
                              bottomRight: Radius.circular(mine ? 4 : 16),
                            ),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(m['body']?.toString() ?? '',
                                style: TextStyle(color: mine ? Colors.white : memberInk, fontSize: 14, height: 1.3)),
                            const SizedBox(height: 3),
                            Text(
                              '${fmtDate(m['created_at'], pattern: 'd MMM HH:mm')}${mine && m['read_by_member_at'] != null ? ' · lu' : ''}',
                              style: TextStyle(color: mine ? Colors.white70 : memberMuted, fontSize: 10.5),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, MediaQuery.viewInsetsOf(context).bottom + 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Répondre au membre…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: const Icon(LucideIcons.send, size: 18),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
