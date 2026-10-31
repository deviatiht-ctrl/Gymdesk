import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../data/member_portal_repository.dart';
import 'member_ui.dart';

/// Onglet « Messages » du membre : conversation directe avec l'accueil du gym,
/// temps réel (canal member_messages) + lecture marquée côté membre via RPC.
class MemberMessagesTab extends StatefulWidget {
  const MemberMessagesTab({super.key, required this.gymId, required this.memberId, required this.accent});
  final String gymId;
  final String memberId;
  final Color accent;

  @override
  State<MemberMessagesTab> createState() => _MemberMessagesTabState();
}

class _MemberMessagesTabState extends State<MemberMessagesTab> {
  final _repo = MemberPortalRepository();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _repo.messagesChannel(widget.memberId, _load);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(_repo.client.removeChannel(channel));
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _repo.messages(widget.gymId);
      if (!mounted) return;
      setState(() {
        _messages = rows;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final status = await _repo.sendMessage(widget.gymId, body);
      if (status == 'ok') {
        _input.clear();
        await _load();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(status == 'rate_limited' ? 'Trop de messages aujourd’hui. Réessayez demain.' : memberAuthError(status))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(memberAuthError('network'))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Écrire au gym', icon: LucideIcons.messagesSquare),
      MemberCard(
        padding: const EdgeInsets.all(0),
        child: SizedBox(
          height: 340,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Une question sur votre abonnement, un casier, un cours ? Écrivez à l’accueil : la réponse arrive ici en direct.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: memberMuted, height: 1.4),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final mine = m['sender'] == 'member';
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .72),
                            decoration: BoxDecoration(
                              color: mine ? widget.accent : memberSurface,
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
                                '${fmtDate(m['created_at'], pattern: 'd MMM HH:mm')}${mine && m['read_by_gym_at'] != null ? ' · vu' : ''}',
                                style: TextStyle(color: mine ? Colors.white70 : memberMuted, fontSize: 10.5),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Votre message pour l’accueil…',
              isDense: true,
              counterText: '',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          style: IconButton.styleFrom(backgroundColor: widget.accent),
          onPressed: _sending ? null : _send,
          icon: const Icon(LucideIcons.send, size: 18),
        ),
      ]),
    ]);
  }
}
