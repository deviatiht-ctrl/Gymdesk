import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import 'member_ui.dart';

/// Côté propriétaire : lien/QR de l'espace membre, messages publiés aux
/// membres, et comptes membres activés (révocables).
class MemberSpaceAdminPage extends ConsumerStatefulWidget {
  const MemberSpaceAdminPage({super.key});

  @override
  ConsumerState<MemberSpaceAdminPage> createState() => _MemberSpaceAdminPageState();
}

class _MemberSpaceAdminPageState extends ConsumerState<MemberSpaceAdminPage> {
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _accounts = [];
  bool _loading = true;
  bool _notMigrated = false;

  String get _gymId => ref.read(appRuntimeProvider).session?.gymId ?? '';
  String get _url => 'https://securgym.com/m/$_gymId';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = ref.read(appRuntimeProvider).client;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        client.from('gym_announcements').select().eq('gym_id', _gymId).order('created_at', ascending: false),
        client
            .from('member_accounts')
            .select('id, email, created_at, last_seen_at, members(first_name, last_name, member_number)')
            .eq('gym_id', _gymId)
            .order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _announcements = (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _accounts = (results[1] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _notMigrated = false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _notMigrated = true;
          _loading = false;
        });
      }
    }
  }

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
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _delete(String table, String id, String question) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(question),
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
      await ref.read(appRuntimeProvider).client.from(table).delete().eq('id', id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appRuntimeProvider).session;
    final gymName = session?.name ?? 'Mon gym';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace membre'),
        actions: [IconButton(onPressed: _load, icon: const Icon(LucideIcons.refreshCw))],
      ),
      floatingActionButton: _notMigrated
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editAnnouncement(),
              icon: const Icon(LucideIcons.megaphone),
              label: const Text('Nouveau message'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
                if (_notMigrated)
                  const ErrorBox(
                    'L’espace membre n’est pas encore activé sur le serveur : appliquez la migration supabase/sql/34_member_portal.sql.',
                  ),
                _linkCard(gymName),
                SectionTitle('Messages aux membres (${_announcements.length})', icon: LucideIcons.megaphone),
                if (_announcements.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Aucun message. Publiez une info (horaires, promo, événement) : elle s’affiche dans l’app de chaque membre.',
                        style: TextStyle(color: memberMuted)),
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
                        onPressed: () => _delete('gym_announcements', a['id'].toString(), 'Supprimer ce message ?'),
                      ),
                    ),
                  ),
                SectionTitle('Comptes membres activés (${_accounts.length})', icon: LucideIcons.smartphone),
                if (_accounts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Aucun membre n’a encore activé son espace.', style: TextStyle(color: memberMuted)),
                  ),
                for (final acc in _accounts)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(LucideIcons.user, size: 18)),
                      title: Text(
                        '${(acc['members'] as Map?)?['first_name'] ?? ''} ${(acc['members'] as Map?)?['last_name'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${acc['email'] ?? ''} · N° ${(acc['members'] as Map?)?['member_number'] ?? '—'}\n'
                        'Activé le ${fmtDate(acc['created_at'])} · Dernière visite app : '
                        '${acc['last_seen_at'] == null ? '—' : fmtDate(acc['last_seen_at'], pattern: 'd MMM HH:mm')}',
                      ),
                      isThreeLine: true,
                      trailing: session?.isOwner == true || session?.isSupervisor == true
                          ? IconButton(
                              tooltip: 'Retirer l’accès',
                              icon: const Icon(LucideIcons.userX, color: Color(0xFFDC2626)),
                              onPressed: () => _delete(
                                'member_accounts',
                                acc['id'].toString(),
                                'Retirer l’accès à l’espace membre pour ce compte ? Le membre devra réactiver son compte.',
                              ),
                            )
                          : null,
                    ),
                  ),
              ]),
            ),
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
              'les nouvelles inscriptions en ligne créent leur compte automatiquement, activé dès votre validation.',
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
