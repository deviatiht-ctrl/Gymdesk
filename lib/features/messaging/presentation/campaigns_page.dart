import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/sync/sync_models.dart';
import '../../../l10n/app_strings.dart';
import '../../../core/whatsapp/whatsapp_client.dart';
import '../../../core/whatsapp/whatsapp_notification_service.dart';
import '../../../core/whatsapp/whatsapp_antiban_helper.dart';
import '../../members/data/members_repository.dart';

class CampaignsPage extends ConsumerStatefulWidget {
  const CampaignsPage({super.key});

  @override
  ConsumerState<CampaignsPage> createState() => _CampaignsPageState();
}

class _CampaignsPageState extends ConsumerState<CampaignsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Fòmilè Kanpay
  final _titleController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final _searchController = TextEditingController();

  String _channel = 'email'; // 'email' | 'whatsapp'
  String _templateKey = 'inactive_winback';
  String _filterStatus = 'all'; // 'all' | 'active' | 'expired'
  String _speedMode = 'safe'; // 'safe' (15s-27s), 'moderate' (8s-14s), 'fast' (4s-7s)
  int _totalActiveMembers = 0;
  int _totalExpiredMembers = 0;
  int _totalAllMembers = 0;

  bool _loadingPreview = false;
  List<Map<String, dynamic>> _previewRecipients = [];
  final Set<String> _selectedMemberIds = {};

  bool _showVisualPreview = false;
  bool _isSending = false;

  // Istorik
  bool _loadingHistory = true;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = AppStrings.of(context);
      _applyTemplate('inactive_winback', s);
      _runPreview();
    });
  }

  void _applyTemplate(String val, AppStrings s) {
    setState(() {
      _templateKey = val;
      final isFr = s.locale.languageCode == 'fr';
      final isEn = s.locale.languageCode == 'en';

      if (val == 'inactive_winback') {
        _titleController.text = isFr
            ? 'Tu nous manques ! Reviens t\'entraîner chez nous'
            : isEn
                ? 'We miss you! Come back to training'
                : 'Ou manke nou ! Retounen antrene nan gym lan';
        _subjectController.text = isFr
            ? '🏋️ Ton pass Gym vous attend : offre spéciale reprise !'
            : isEn
                ? '🏋️ Your Gym pass awaits: special comeback offer!'
                : '🏋️ Pwofite yon òf espesyal pou w retounen antrene !';
        _bodyController.text = isFr
            ? 'Bonjour {nom},\n\nCela fait un moment que nous ne t\'avons pas vu chez {gym} ! Ta santé, ta forme et ton énergie se construisent chaque jour.\n\nReviens t\'entraîner dès cette semaine chez {gym} et bénéficie d\'une offre exclusive sur ton réabonnement. Toute l\'équipe et les coachs de {gym} t\'attendent avec impatience pour t\'aider à atteindre tes objectifs.\n\nÀ très vite chez {gym} !'
            : isEn
                ? 'Hello {nom},\n\nIt\'s been a while since we saw you at {gym}! Your fitness and energy matter every single day.\n\nCome back to {gym} this week and enjoy an exclusive discount on your renewal. The whole coaching team at {gym} is waiting for you.\n\nSee you soon at {gym}!'
                : 'Bonjou {nom},\n\nSa fè yon ti moman depi nou pa wè w nan {gym} ! Sante w, fòs ou ak enèji w se pi gwo richès ou.\n\nRetounen antrene semèn sa a nan {gym} epi pwofite yon rabè espesyal sou re-abònman w lan. Tout ekip la ak antrenè {gym} yo ap tann ou pou kontinye avanse ansanm.\n\nN ap tann ou nan {gym} !';
      } else if (val == 'expiring_reminder') {
        _titleController.text = isFr
            ? 'Rappel : Ton abonnement expire bientôt'
            : isEn
                ? 'Reminder: Your membership expires soon'
                : 'Rapèl : Abònman w lan ap fini byento';
        _subjectController.text = isFr
            ? '⏳ Pense à renouveler pour ne pas perdre ton accès'
            : isEn
                ? '⏳ Don\'t forget to renew to keep your access active'
                : '⏳ Pa bliye renouvle abònman w lan pou w pa pèdi aksè w';
        _bodyController.text = isFr
            ? 'Bonjour {nom},\n\nTon abonnement arrive bientôt à échéance.\n\nPour conserver ton accès fluide aux portes et continuer tes entraînements sans interruption, passe à la réception dès aujourd\'hui pour renouveler ta formule.\n\nBon entraînement !'
            : isEn
                ? 'Hello {nom},\n\nYour gym membership will expire in a few days.\n\nPlease visit reception today to renew and maintain your uninterrupted door access.\n\nGood workout!'
                : 'Bonjou {nom},\n\nAbònman w lan nan gym lan ap fini nan kèk jou sèlman.\n\nTanpri pase nan resepsyon an jodi a pou w ka renouvle l epi kenbe aksè anprent ou aktif san rete.\n\nBon antrenman !';
      } else if (val == 'fitness_challenge') {
        _titleController.text = isFr
            ? 'Grand Défi Fitness ce Samedi !'
            : isEn
                ? 'Big Fitness Challenge This Saturday!'
                : 'Gwo Defi Fitness Samdi sa a !';
        _subjectController.text = isFr
            ? 'Grand Défi & Cours Collectif ce samedi'
            : isEn
                ? 'Special Fitness Challenge this Saturday'
                : 'Gwo Defi ak Antrenman Kolektif Samdi a';
        _bodyController.text = isFr
            ? 'Bonjour {nom},\n\nCe samedi, nous organisons une session spéciale de Bootcamp & Fitness Challenge ! Au programme : des épreuves conviviales, des conseils nutritionnels personnalisés, et des cadeaux pour les participants.\n\nRendez-vous dès 9h00 en tenue de sport. Viens te dépasser avec nous !'
            : isEn
                ? 'Hello {nom},\n\nThis Saturday, we are hosting a special Bootcamp & Fitness Challenge! Friendly competitions, personalized nutrition advice, and gifts await.\n\nJoin us at 9:00 AM ready to sweat!'
                : 'Bonjou {nom},\n\nSamdi sa a, nou gen yon gwo sesyon antrenman espesyal Bootcamp ak Defi Fitness ! Ap gen konpetisyon amikal, konsèy nitrisyon ak kado pou tout moun k ap patisipe.\n\nRann ou disponib a 9h00 nan maten. Vin depase limit ou ansanm ak nou !';
      } else if (val == 'special_discount') {
        _titleController.text = isFr
            ? 'Offre Promotionnelle Exclusive'
            : isEn
                ? 'Exclusive Member Promotion'
                : 'Spesyal Pwomosyon pou Manm yo';
        _subjectController.text = isFr
            ? 'Remise spéciale sur les abonnements de 3 mois et plus'
            : isEn
                ? 'Special discount on 3-month renewals and more'
                : 'Rabè espesyal sou renouvèlman 3 mwa oswa plis';
        _bodyController.text = isFr
            ? 'Bonjour {nom},\n\nProfite dès aujourd\'hui d\'une réduction spéciale pour tout renouvellement de 3 mois ou plus. Invite un ami et bénéficie d\'une semaine supplémentaire offerte !\n\nOffre valable pour une durée limitée à la réception.'
            : isEn
                ? 'Hello {nom},\n\nTake advantage of a special discount on any renewal of 3 months or more. Bring a friend and get an extra free week!\n\nLimited-time offer available at reception.'
                : 'Bonjou {nom},\n\nPwofite kounye a yon rabè espesyal si w renouvle pou 3 mwa oswa plis. Vin ak yon zanmi epi n ap ba w yon semèn gratis anplis sou abònman w lan !\n\nÒf sa a disponib nan resepsyon an pou yon ti tan sèlman.';
      } else if (val == 'price_change') {
        _titleController.text = isFr
            ? 'Mise à jour tarifaire de la salle'
            : isEn
                ? 'Gym Membership Price Update'
                : 'Mizajou sou Pri ak Fòmil Gym lan';
        _subjectController.text = isFr
            ? 'Information Importante : Évolution des Tarifs'
            : isEn
                ? 'Important Notice: Membership Rate Changes'
                : 'Enfòmasyon Enpòtan: Chanjman nan Tarif yo';
        _bodyController.text = isFr
            ? 'Bonjour {nom},\n\nNous vous informons qu\'un ajustement de nos formules entrera en vigueur prochainement afin de continuer à moderniser les équipements et les espaces d\'entraînement.\n\nMerci de votre confiance et de votre fidélité !'
            : isEn
                ? 'Hello {nom},\n\nPlease be informed of an upcoming pricing update to help us upgrade gym equipment and workout areas.\n\nThank you for your loyalty!'
                : 'Bonjou {nom},\n\nNou vle enfòme w ke apati mwa kap vini an, ap gen yon ti ajisteman nan tarif abònman nou yo pou pèmèt nou kontinye modènize ekipman ak sal antrenman an.\n\nNou remèsye w anpil pou fidelite w !';
      }
    });
  }

  Future<void> _runPreview() async {
    setState(() => _loadingPreview = true);
    final runtime = ref.read(appRuntimeProvider);
    final gymId = runtime.session?.gymId;
    final List<Map<String, dynamic>> rawMembers = [];

    // 1. Lire d'abord avec MembersRepository (calcul précis de validité d'abonnement Offline-first)
    if (runtime.database != null && gymId != null && runtime.session != null) {
      try {
        final repo = MembersRepository(runtime.client, runtime.database!, runtime.session!);
        final entries = await repo.watch().first;
        for (final entry in entries) {
          final m = entry.member;
          final isValid = entry.validity.valid;
          rawMembers.add({
            'member_id': m.id,
            'name': '${m.firstName} ${m.lastName}'.trim(),
            'email': m.email?.trim() ?? '',
            'phone': m.phone?.trim() ?? '',
            'whatsapp': m.whatsapp?.trim() ?? '',
            'status': isValid ? 'active' : 'expired',
            'is_active': isValid,
            'plan_name': 'Abonnement Gym',
            'days_left': entry.validity.daysLeft,
          });
        }
      } catch (_) {
        // Fallback lecture directe table SQLite si exception
        try {
          final rows = await runtime.database!
              .watchRecords(SyncEntity.members, limit: 10000)
              .first;
          for (final row in rows) {
            try {
              final p = jsonDecode(row.payload) as Map<String, dynamic>;
              rawMembers.add({
                'member_id': p['id']?.toString() ?? '',
                'name': '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim(),
                'email': p['email']?.toString() ?? '',
                'phone': p['phone']?.toString() ?? '',
                'whatsapp': p['whatsapp']?.toString() ?? '',
                'status': p['status']?.toString() ?? 'active',
                'plan_name': 'Abonnement Gym',
              });
            } catch (_) {}
          }
        } catch (_) {}
      }
    }

    // 2. Si la base locale n'avait aucun membre ou n'était pas initialisée, interroger Supabase
    if (rawMembers.isEmpty) {
      try {
        final client = Supabase.instance.client;
        try {
          final res = await client.rpc('campaign_preview', params: {
            'p_filter': {'status': 'all'},
          });
          final list = List<Map<String, dynamic>>.from(res as List? ?? []);
          rawMembers.addAll(list);
        } catch (_) {
          var query = client.from('members').select('id, first_name, last_name, email, phone, whatsapp, status, subscriptions(id, status, end_date, deleted_at)');
          if (gymId != null) query = query.eq('gym_id', gymId);
          final membersRes = await query;
          final today = DateTime.now().toUtc();
          final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
          for (final m in (membersRes as List)) {
            final p = m as Map<String, dynamic>;
            final subs = p['subscriptions'] as List? ?? [];
            bool hasValidSub = false;
            for (final s in subs) {
              final subMap = s as Map<String, dynamic>;
              if (subMap['deleted_at'] == null && subMap['status'] != 'cancelled') {
                final endDate = subMap['end_date']?.toString() ?? '';
                if (endDate.compareTo(todayStr) >= 0) {
                  hasValidSub = true;
                  break;
                }
              }
            }
            rawMembers.add({
              'member_id': p['id']?.toString() ?? '',
              'name': '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim(),
              'email': p['email']?.toString() ?? '',
              'phone': p['phone']?.toString() ?? '',
              'whatsapp': p['whatsapp']?.toString() ?? '',
              'status': hasValidSub ? 'active' : 'expired',
              'is_active': hasValidSub,
              'plan_name': 'Abonnement Gym',
            });
          }
        }
      } catch (_) {}
    }

    // Kalkile kantite manm pou badges yo
    final totalAll = rawMembers.length;
    final totalActive = rawMembers.where((m) => m['status'] == 'active').length;
    final totalExpired = rawMembers.where((m) => m['status'] == 'expired' || m['status'] == 'inactive').length;

    // 3. Appliquer le filtre sélectionné (Tous, Inactifs, Actifs)
    final filtered = rawMembers.where((m) {
      final st = m['status']?.toString().toLowerCase() ?? '';
      if (_filterStatus == 'expired' || _filterStatus == 'inactive') {
        return st == 'expired' || st == 'inactive';
      }
      if (_filterStatus == 'active') {
        return st == 'active';
      }
      return true; // 'all'
    }).toList();

    if (mounted) {
      setState(() {
        _totalAllMembers = totalAll;
        _totalActiveMembers = totalActive;
        _totalExpiredMembers = totalExpired;
        _previewRecipients = filtered;
        _selectedMemberIds.clear();
        for (final m in filtered) {
          final id = m['member_id']?.toString() ?? '';
          final email = m['email']?.toString() ?? '';
          final phone = (m['whatsapp']?.toString().isNotEmpty ?? false)
              ? m['whatsapp'].toString()
              : m['phone']?.toString() ?? '';
          final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');

          if (_channel == 'whatsapp') {
            if (id.isNotEmpty && cleanPhone.length >= 8) {
              _selectedMemberIds.add(id);
            }
          } else {
            if (id.isNotEmpty && email.contains('@')) {
              _selectedMemberIds.add(id);
            }
          }
        }
        _loadingPreview = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredRecipients {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _previewRecipients;
    return _previewRecipients.where((m) {
      final name = (m['name']?.toString() ?? '').toLowerCase();
      final email = (m['email']?.toString() ?? '').toLowerCase();
      final phone = (m['phone']?.toString() ?? '').toLowerCase();
      final whatsapp = (m['whatsapp']?.toString() ?? '').toLowerCase();
      return name.contains(query) || email.contains(query) || phone.contains(query) || whatsapp.contains(query);
    }).toList();
  }

  void _selectAll() {
    setState(() {
      for (final m in _filteredRecipients) {
        final id = m['member_id']?.toString() ?? '';
        if (id.isNotEmpty) _selectedMemberIds.add(id);
      }
    });
  }

  void _deselectAll() {
    setState(() {
      for (final m in _filteredRecipients) {
        final id = m['member_id']?.toString() ?? '';
        _selectedMemberIds.remove(id);
      }
    });
  }

  void _autoFormatAntiBan() {
    final currentText = _bodyController.text.trim();
    if (currentText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tanpri ekri mesaj ou anvan, pou nou ka fòmate l pou Anti-Ban.')),
      );
      return;
    }
    final s = AppStrings.of(context);
    final spintax = WhatsAppAntiBanHelper.autoSpintaxifyAnnouncement(
      currentText,
      lang: s.locale.languageCode,
    );
    setState(() {
      _bodyController.text = spintax;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✨ Mesaj ou an fòmate kounye a ak varyasyon Anti-Ban !'),
        backgroundColor: Color(0xFF0F766E),
      ),
    );
  }

  void _insertTag(String tag) {
    final currentText = _bodyController.text;
    final selection = _bodyController.selection;
    if (selection.start >= 0 && selection.end >= 0) {
      final newText = currentText.replaceRange(selection.start, selection.end, tag);
      _bodyController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + tag.length),
      );
    } else {
      _bodyController.text = '$currentText $tag';
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    final gymId = ref.read(appRuntimeProvider).session?.gymId;
    if (gymId == null) {
      setState(() => _loadingHistory = false);
      return;
    }
    try {
      final client = Supabase.instance.client;
      final res = await client
          .from('campaigns')
          .select()
          .eq('gym_id', gymId)
          .order('created_at', ascending: false)
          .limit(30);
      if (mounted) {
        setState(() {
          _history = List<Map<String, dynamic>>.from(res as List? ?? []);
          _loadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _sendCampaign() async {
    if (_isSending) return;
    final s = AppStrings.of(context);
    final title = _titleController.text.trim();
    final subject = _subjectController.text.trim();
    final body = _bodyController.text.trim();

    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.text('fill_required_fields'))),
      );
      return;
    }
    if (_channel == 'email' && (title.isEmpty || subject.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.text('fill_required_fields'))),
      );
      return;
    }

    final targetRecipients = _previewRecipients
        .where((m) => _selectedMemberIds.contains(m['member_id']?.toString() ?? ''))
        .toList();

    if (targetRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.text('no_selected_members'))),
      );
      return;
    }

    final channelName = _channel == 'whatsapp' ? 'WhatsApp (SecurGYM)' : 'Email';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('send_campaign_btn')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Êtes-vous sûr de vouloir envoyer cette campagne ($channelName) à ${targetRecipients.length} membre(s) sélectionné(s) ?'),
            const SizedBox(height: 12),
            if (subject.isNotEmpty)
              Text('• Objet : $subject', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('• Canal : $channelName'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _channel == 'whatsapp' ? Colors.green : const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.text('send_campaign_btn')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSending = true);

    if (_channel == 'whatsapp') {
      await _sendWhatsAppCampaign(targetRecipients, title, body, s);
    } else {
      await _sendEmailCampaign(targetRecipients, title, subject, body, s);
    }
  }

  void _showAntiBanPreviewDialog() {
    final s = AppStrings.of(context);
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tanpri mete yon tèks nan kò mesaj la anvan pou w ka wè aperçu a.')),
      );
      return;
    }
    final runtime = ref.read(appRuntimeProvider);
    final gym = runtime.session?.gym ?? const <String, dynamic>{};
    final gymName = gym['name'] as String? ?? 'SecurGYM';

    final variations = WhatsAppAntiBanHelper.generateSemanticAnglesPreview(
      body: body,
      gymName: gymName,
      lang: s.locale.languageCode,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Row(
          children: [
            const Icon(LucideIcons.bot, color: Color(0xFF15803D)),
            const SizedBox(width: 8),
            Text(
              '🤖 Aperçu 5 Gwo Ang Semantik (IA Anti-Ban)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pou WhatsApp pa janm detekte spam oswa mesaj menm jan, motè IA a re-ekri mesaj la an 5 ang semantik diferan (Ofisyèl, Amikal, Planifikasyon, Flash, Respè). Chak manm resevwa yon estrikti fraz diferan :',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 14),
                for (int i = 0; i < variations.length; i++) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                variations[i]['title'] ?? 'Ang ${i + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '🛡️ Hash SHA-256 Inik',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          variations[i]['content'] ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fèmen'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendWhatsAppCampaign(
    List<Map<String, dynamic>> recipients,
    String title,
    String body,
    AppStrings s,
  ) async {
    final runtime = ref.read(appRuntimeProvider);
    final gymId = runtime.session?.gymId;
    final notifService = ref.read(whatsAppNotificationServiceProvider);

    // 1. Verifye si gym nan gen aksè abònman WhatsApp aktif (pa sispann, pa ekspire)
    final access = await notifService.checkGymAccess(gymId: gymId);
    if (!access.hasAccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ ${access.message}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 7),
          ),
        );
        setState(() => _isSending = false);
      }
      return;
    }

    // 2. Verifye si sèvis WhatsApp la konekte sou aparèy la
    final waClient = ref.read(whatsAppClientProvider);
    final waState = await waClient.checkStatus();

    if (!waState.isReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ WhatsApp pa konekte. Tanpri ale nan Panèl Admin > WhatsApp pou konekte li anvan.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSending = false);
      }
      return;
    }

    final gym = runtime.session?.gym ?? const <String, dynamic>{};
    final gymName = gym['name'] as String? ?? 'SecurGYM';
    final gymPhone = gym['phone'] as String? ?? '';
    final footer = WhatsAppNotificationService.buildCampaignFooter(
      gymName: gymName,
      gymPhone: gymPhone,
      lang: s.locale.languageCode,
    );

    // Bwat dyalòg pwogresyon an dirèk ak Pwoteksyon Anti-Ban (StatefulWidget pou evite paralèl loop)
    if (!mounted) return;
    final sentCount = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _WhatsAppCampaignProgressDialog(
        recipients: recipients,
        title: title,
        body: body,
        footer: footer,
        gymId: gymId,
        gymName: gymName,
        waClient: waClient,
        lang: s.locale.languageCode,
        speedMode: _speedMode,
      ),
    ) ?? 0;

    // 3. Anrejistre kanpay la nan baz done Supabase
    try {
      if (gymId != null && sentCount > 0) {
        await Supabase.instance.client.from('campaigns').insert({
          'gym_id': gymId,
          'title': title,
          'subject': title,
          'body_text': body,
          'template_key': _templateKey,
          'channels': ['whatsapp'],
          'recipient_count': sentCount,
          'status': 'sent',
        });
      }
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sentCount < recipients.length
                ? 'Kanpay sispann oswa fini : $sentCount voye sou ${recipients.length} manm.'
                : '$sentCount / ${recipients.length} ${s.text('campaign_whatsapp_sent_summary')}',
          ),
          backgroundColor: sentCount > 0 ? const Color(0xFF059669) : Colors.amber.shade800,
        ),
      );
      _loadHistory();
      setState(() => _isSending = false);
    }
  }

  Future<void> _sendEmailCampaign(
    List<Map<String, dynamic>> targetRecipients,
    String title,
    String subject,
    String body,
    AppStrings s,
  ) async {
    try {
      final count = await Supabase.instance.client.rpc('campaign_send_members', params: {
        'p_title': title,
        'p_subject': subject,
        'p_body': body,
        'p_template_key': _templateKey,
        'p_member_ids': targetRecipients.map((m) => m['member_id'].toString()).toList(),
        'p_filter': {'status': _filterStatus},
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count / ${targetRecipients.length} ${s.text('campaign_queued_summary')}'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
        _loadHistory();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.text('campaign_send_failed')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('campaigns_title')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(LucideIcons.mailPlus), text: s.text('new_campaign')),
            Tab(icon: const Icon(LucideIcons.history), text: s.text('campaign_history')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildComposeTab(s),
          _buildHistoryTab(s),
        ],
      ),
    );
  }

  Widget _buildComposeTab(AppStrings s) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 0. Chwa Kanal la (Email vs WhatsApp)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'email',
                      icon: const Icon(LucideIcons.mail, size: 18),
                      label: Text(s.text('campaign_channel_email')),
                    ),
                    ButtonSegment(
                      value: 'whatsapp',
                      icon: const Icon(LucideIcons.messageSquare, size: 18, color: Colors.green),
                      label: Text(s.text('campaign_channel_whatsapp')),
                    ),
                  ],
                  selected: {_channel},
                  onSelectionChanged: (set) {
                    setState(() {
                      _channel = set.first;
                      _runPreview();
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),

              // 1. Barre de choix du Modèle Gym
              Card(
                elevation: 0,
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.sparkles, color: Color(0xFF0F766E), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            s.text('template_label'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildTemplateChip('inactive_winback', s.text('template_inactive_winback'), s),
                          _buildTemplateChip('expiring_reminder', s.text('template_expiring_reminder'), s),
                          _buildTemplateChip('fitness_challenge', s.text('template_fitness_challenge'), s),
                          _buildTemplateChip('special_discount', s.text('template_special_discount'), s),
                          _buildTemplateChip('price_change', s.text('template_price_change'), s),
                          _buildTemplateChip('custom', s.text('template_custom'), s),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 2. Section Filtre & Sélection des Membres
              Card(
                elevation: 0,
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(LucideIcons.users, color: Color(0xFF0F766E), size: 20),
                              const SizedBox(width: 8),
                              Text(
                                s.text('target_audience'),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                avatar: const Icon(LucideIcons.users, size: 16),
                                label: Text('Tout Moun ($_totalAllMembers)'),
                                selected: _filterStatus == 'all',
                                backgroundColor: isDark ? const Color(0xFF0F172A) : null,
                                selectedColor: isDark ? const Color(0xFF134E4A) : const Color(0xFFCCFBF1),
                                labelStyle: TextStyle(
                                  color: _filterStatus == 'all'
                                      ? (isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E))
                                      : (isDark ? const Color(0xFFCBD5E1) : Colors.black87),
                                  fontWeight: _filterStatus == 'all' ? FontWeight.bold : FontWeight.normal,
                                ),
                                onSelected: (val) {
                                  if (val) {
                                    setState(() => _filterStatus = 'all');
                                    _runPreview();
                                  }
                                },
                              ),
                              ChoiceChip(
                                avatar: const Icon(LucideIcons.checkCircle2, size: 16, color: Color(0xFF15803D)),
                                label: Text('Moun ki Aktif sèlman ($_totalActiveMembers)'),
                                selected: _filterStatus == 'active',
                                backgroundColor: isDark ? const Color(0xFF0F172A) : null,
                                selectedColor: isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7),
                                labelStyle: TextStyle(
                                  color: _filterStatus == 'active'
                                      ? (isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D))
                                      : (isDark ? const Color(0xFFCBD5E1) : Colors.black87),
                                  fontWeight: _filterStatus == 'active' ? FontWeight.bold : FontWeight.normal,
                                ),
                                onSelected: (val) {
                                  if (val) {
                                    setState(() => _filterStatus = 'active');
                                    _runPreview();
                                  }
                                },
                              ),
                              ChoiceChip(
                                avatar: const Icon(LucideIcons.alertTriangle, size: 16, color: Color(0xFFB91C1C)),
                                label: Text('Inaktif / Ekspire ($_totalExpiredMembers)'),
                                selected: _filterStatus == 'expired',
                                backgroundColor: isDark ? const Color(0xFF0F172A) : null,
                                selectedColor: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2),
                                labelStyle: TextStyle(
                                  color: _filterStatus == 'expired'
                                      ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C))
                                      : (isDark ? const Color(0xFFCBD5E1) : Colors.black87),
                                  fontWeight: _filterStatus == 'expired' ? FontWeight.bold : FontWeight.normal,
                                ),
                                onSelected: (val) {
                                  if (val) {
                                    setState(() => _filterStatus = 'expired');
                                    _runPreview();
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: s.text('search_recipients'),
                                prefixIcon: const Icon(LucideIcons.search, size: 18),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _selectAll,
                            icon: const Icon(LucideIcons.checkCheck, size: 16),
                            label: Text(s.text('select_all')),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _deselectAll,
                            child: Text(s.text('deselect_all')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_selectedMemberIds.length} / ${_filteredRecipients.length} ${s.text('selected_members_count')}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.refreshCw, size: 16),
                            onPressed: _runPreview,
                            tooltip: s.text('sync'),
                          ),
                        ],
                      ),
                      const Divider(),
                      Container(
                        height: 220,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                        ),
                        child: _loadingPreview
                            ? const Center(child: CircularProgressIndicator())
                            : _filteredRecipients.isEmpty
                                ? Center(child: Text(s.text('no_recipients_found'), style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))))
                                : ListView.separated(
                                    itemCount: _filteredRecipients.length,
                                    separatorBuilder: (_, index) => Divider(height: 1, color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200),
                                    itemBuilder: (context, idx) {
                                      final item = _filteredRecipients[idx];
                                      final id = item['member_id']?.toString() ?? '';
                                      final isSelected = _selectedMemberIds.contains(id);
                                      final isInactive = item['status'] == 'expired' || item['status'] == 'inactive';

                                      return CheckboxListTile(
                                        dense: true,
                                        value: isSelected,
                                        activeColor: const Color(0xFF0F766E),
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedMemberIds.add(id);
                                            } else {
                                              _selectedMemberIds.remove(id);
                                            }
                                          });
                                        },
                                        title: Row(
                                          children: [
                                            Text(
                                              item['name']?.toString() ?? '',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isInactive
                                                    ? (isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2))
                                                    : (isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7)),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                isInactive ? 'Inactif' : 'Actif',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isInactive
                                                      ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C))
                                                      : (isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D)),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        subtitle: Row(
                                          children: [
                                            if (item['email'] == null || !item['email'].toString().contains('@'))
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                margin: const EdgeInsets.only(right: 6),
                                                decoration: BoxDecoration(
                                                  color: isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'Sans email (WhatsApp)',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              )
                                            else
                                              Text(
                                                item['email'].toString(),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                                                ),
                                              ),
                                            if (item['phone'] != null && item['phone'].toString().isNotEmpty)
                                              Text(
                                                ' • ${item['phone']}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark ? const Color(0xFF64748B) : Colors.grey.shade600,
                                                ),
                                              ),
                                          ],
                                        ),
                                        secondary: CircleAvatar(
                                          backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                          child: Text(
                                            (item['name']?.toString() ?? 'M').substring(0, 1).toUpperCase(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : const Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 3. Bouton Bascule : Éditer vs Aperçu Design Email
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _showVisualPreview ? s.text('preview_email_design') : s.text('edit_message'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        icon: const Icon(LucideIcons.pencil, size: 16),
                        label: Text(s.text('edit_message')),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: const Icon(LucideIcons.eye, size: 16),
                        label: Text(s.text('preview_email_design')),
                      ),
                    ],
                    selected: {_showVisualPreview},
                    onSelectionChanged: (set) => setState(() => _showVisualPreview = set.first),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 4. Contenu : Mode Édition ou Mode Aperçu Visuel
              if (!_showVisualPreview) ...[
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: _channel == 'whatsapp' ? 'Tit Kanpay la (Antèt mesaj la, opsyonèl)' : '${s.text('campaign_title_field')} *',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_channel == 'email') ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _subjectController,
                    decoration: InputDecoration(
                      labelText: '${s.text('campaign_subject_field')} *',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_channel == 'whatsapp') ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF064E3B).withOpacity(0.35) : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF059669) : const Color(0xFF86EFAC),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.shieldCheck, color: Color(0xFF15803D), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pwoteksyon Anti-Ban Meta Aktif',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
                                side: BorderSide(
                                  color: isDark ? const Color(0xFF059669) : const Color(0xFF86EFAC),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              icon: const Icon(LucideIcons.bot, size: 14),
                              label: const Text('🤖 Preview 5 Ang Diferan (IA)', style: TextStyle(fontSize: 12)),
                              onPressed: _showAntiBanPreviewDialog,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Chak mesaj ap pase nan yon motè semantik IA ki jenere 5 ang diferan (Ofisyèl, Amikal, Planifikasyon, Flash, Respè) ak anprent kriptografik inik pou WhatsApp pa janm wè 2 mesaj menm jan. Chwazi ritm delè a :',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF166534),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.timer, size: 16, color: Color(0xFF15803D)),
                                const SizedBox(width: 6),
                                Text(
                                  'Ritm Delè Anti-Ban :',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            DropdownButton<String>(
                              value: _speedMode,
                              isDense: true,
                              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'safe',
                                  child: Text('🛡️ Maksimòm (15s - 27s + 60s pòz) - Rekòmande pou 100+ moun'),
                                ),
                                DropdownMenuItem(
                                  value: 'moderate',
                                  child: Text('⚡ Modere (8s - 14s + 30s pòz)'),
                                ),
                                DropdownMenuItem(
                                  value: 'fast',
                                  child: Text('🚀 Estanda (4s - 7s)'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _speedMode = val);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Tags & Spintax : ', style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF94A3B8) : Colors.grey)),
                    ActionChip(
                      label: Text(s.text('insert_tag_nom')),
                      onPressed: () => _insertTag('{nom}'),
                    ),
                    ActionChip(
                      label: const Text('{prenom}'),
                      tooltip: 'Premye non manm lan sèlman',
                      onPressed: () => _insertTag('{prenom}'),
                    ),
                    ActionChip(
                      label: Text(s.text('insert_tag_gym')),
                      onPressed: () => _insertTag('{gym}'),
                    ),
                    if (_channel == 'whatsapp') ...[
                      ActionChip(
                        avatar: const Icon(LucideIcons.wand2, size: 14, color: Colors.teal),
                        label: const Text('✨ Fòma Anti-Ban Otomatik', style: TextStyle(fontWeight: FontWeight.bold)),
                        tooltip: 'Transfòme mesaj ou an fòma Spintax Anti-Ban otomatik pou varye chak mesaj',
                        onPressed: _autoFormatAntiBan,
                      ),
                      ActionChip(
                        avatar: const Icon(LucideIcons.sun, size: 14, color: Colors.amber),
                        label: const Text('{salitasyon}'),
                        tooltip: 'Chanje Bonjou / Bonswa otomatik selon lè a',
                        onPressed: () => _insertTag('{salitasyon}'),
                      ),
                      ActionChip(
                        avatar: const Icon(LucideIcons.heartHandshake, size: 14, color: Colors.green),
                        label: const Text('{konklizyon}'),
                        tooltip: 'Varye konklizyon ak fòmil politès yo',
                        onPressed: () => _insertTag('{konklizyon}'),
                      ),
                      ActionChip(
                        avatar: const Icon(LucideIcons.shuffle, size: 14, color: Colors.teal),
                        label: const Text('{Opsyon 1|Opsyon 2}'),
                        tooltip: 'Mete yon varyasyon Spintax',
                        onPressed: () => _insertTag('{Bonjou|Bonswa} {nom}! {Nou kontan enfòme w ke|Nou pase fè w sonje ke} '),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bodyController,
                  maxLines: 7,
                  decoration: InputDecoration(
                    labelText: '${s.text('campaign_body_field')} *',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                // Panneau d'Aperçu Visuel Email Gym
                _buildVisualEmailPreview(s),
              ],

              const SizedBox(height: 24),

              // 6. Bouton d'Envoi Principal
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isSending ? null : _sendCampaign,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.send),
                  label: Text(
                    _isSending
                        ? s.text('sending_campaign')
                        : '${s.text('send_campaign_btn')} (${_selectedMemberIds.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTemplateChip(String key, String label, AppStrings s) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _templateKey == key;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label),
      backgroundColor: isDark ? const Color(0xFF0F172A) : null,
      selectedColor: isDark ? const Color(0xFF134E4A) : const Color(0xFFCCFBF1),
      labelStyle: TextStyle(
        color: isSelected
            ? (isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E))
            : (isDark ? const Color(0xFFE2E8F0) : Colors.black87),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => _applyTemplate(key, s),
    );
  }

  Widget _buildVisualEmailPreview(AppStrings s) {
    final title = _titleController.text.trim().isEmpty ? 'Titre de la Campagne' : _titleController.text.trim();
    final body = _bodyController.text.trim().isEmpty ? 'Contenu de votre message...' : _bodyController.text.trim();
    final sampleName = _filteredRecipients.isNotEmpty ? _filteredRecipients.first['name'] : 'Jean Dupont';
    final gymName = ref.read(appRuntimeProvider).session?.name ?? 'GymDesk';

    final paragraphs = body
        .replaceAll('{nom}', sampleName)
        .replaceAll('{non}', sampleName)
        .replaceAll('{name}', sampleName)
        .replaceAll('{gym}', gymName)
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Bandeau Gradient Supérieur
                Container(
                  height: 6,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    gradient: LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0D9488)]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCCFBF1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          gymName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F766E),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bonjour $sampleName,',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 12),
                      for (final p in paragraphs) ...[
                        Text(
                          p,
                          style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF334155)),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        s.text('cta_button_text'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$gymName — Espace Forme & Santé',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Vous recevez cet email car vous êtes inscrit comme membre de notre salle de sport.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab(AppStrings s) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_history.isEmpty) {
      return Center(
        child: Text(
          s.text('campaign_history'),
          style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _history.length,
      itemBuilder: (context, idx) {
        final item = _history[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isDark ? const Color(0xFF334155) : Colors.grey.shade300),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isDark ? const Color(0xFF0C4A6E) : const Color(0xFFE0F2FE),
              child: Icon(LucideIcons.mailCheck, color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1)),
            ),
            title: Text(
              item['title']?.toString() ?? '',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            subtitle: Text(
              '${item['subject'] ?? ''}\n${item['created_at']?.toString().substring(0, 16) ?? ''}',
              style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
            isThreeLine: true,
            trailing: Chip(
              label: Text('${item['recipient_count'] ?? 0}'),
              backgroundColor: isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7),
              labelStyle: TextStyle(
                color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }
}


/// Dyalòg Pwogresyon Kanpay WhatsApp ak Pwoteksyon Anti-Ban
/// StatefulWidget endepandan pou garanti ekzekisyon strikteman sekansyèl (1 sèl loop, 0 paralèl)
class _WhatsAppCampaignProgressDialog extends StatefulWidget {
  const _WhatsAppCampaignProgressDialog({
    required this.recipients,
    required this.title,
    required this.body,
    required this.footer,
    required this.gymId,
    required this.gymName,
    required this.waClient,
    required this.lang,
    this.speedMode = 'safe',
  });

  final List<Map<String, dynamic>> recipients;
  final String title;
  final String body;
  final String footer;
  final String? gymId;
  final String gymName;
  final WhatsAppClient waClient;
  final String lang;
  final String speedMode;

  @override
  State<_WhatsAppCampaignProgressDialog> createState() => _WhatsAppCampaignProgressDialogState();
}

class _WhatsAppCampaignProgressDialogState extends State<_WhatsAppCampaignProgressDialog> {
  int _sentCount = 0;
  int _failedCount = 0;
  bool _isCancelled = false;
  bool _isPaused = false;
  bool _hasStarted = false;
  String _currentRecipient = '';
  String _progressStatus = 'Preparasyon pou voye...';
  int _coolingSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasStarted && mounted) {
        _hasStarted = true;
        _startSending();
      }
    });
  }

  Future<void> _startSending() async {
    for (int i = 0; i < widget.recipients.length; i++) {
      if (_isCancelled || !mounted) break;

      // Poz entèaktif
      while (_isPaused && !_isCancelled && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (_isCancelled || !mounted) break;

      final m = widget.recipients[i];
      final rawPhone = (m['whatsapp']?.toString().isNotEmpty ?? false)
          ? m['whatsapp'].toString()
          : m['phone']?.toString() ?? '';
      final phone = WhatsAppClient.normalizePhone(rawPhone);
      if (phone.length < 8) {
        if (mounted) setState(() => _failedCount++);
        continue;
      }

      final memberName = m['name']?.toString() ?? '';
      final currentAngleNum = (i % 5) + 1;
      if (mounted) {
        setState(() {
          _currentRecipient = '$memberName ($phone)';
          _progressStatus = 'Voye bay: $_currentRecipient (Ang Semantik #$currentAngleNum/5)';
          _coolingSeconds = 0;
        });
      }

      // Tèks varye ak motè IA semantik (50+ Ang Diferan + Spintax + Hash Cryptographique Envizib)
      final fullMsg = WhatsAppAntiBanHelper.humanizeMessage(
        body: widget.body,
        memberName: memberName,
        gymName: widget.gymName,
        title: widget.title.isNotEmpty ? widget.title : null,
        footer: widget.footer,
        lang: widget.lang,
        recipientIndex: i,
        addZeroWidthFingerprint: true,
        useSemanticArchetypes: true,
      );

      // Voye ak kind 'manual_direct' pou pase nan Fast Lane imedya sou WhatsApp Web
      final res = await widget.waClient.sendMessage(
        to: phone,
        message: fullMsg,
        kind: 'manual_direct',
        gymId: widget.gymId,
      );

      if (mounted) {
        setState(() {
          if (res.success) {
            _sentCount++;
          } else {
            _failedCount++;
          }
        });
      }

      // Reta entèlijan ant chak voye dapre mòd sekirite chwazi a
      if (i < widget.recipients.length - 1 && !_isCancelled) {
        final isCool = WhatsAppAntiBanHelper.isCoolingBreak(index: i + 1, speedMode: widget.speedMode);
        if (isCool) {
          final coolSecs = WhatsAppAntiBanHelper.getCoolingDurationSeconds(speedMode: widget.speedMode);
          for (int sec = coolSecs; sec > 0; sec--) {
            if (_isCancelled || !mounted) break;
            while (_isPaused && !_isCancelled && mounted) {
              await Future<void>.delayed(const Duration(milliseconds: 300));
            }
            if (mounted) {
              setState(() {
                _coolingSeconds = sec;
                _progressStatus = '⏳ Pòz refwadisman Anti-Ban ($sec s) pou reset algoritm Meta a...';
              });
            }
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        } else {
          final delay = WhatsAppAntiBanHelper.getPacingDelay(index: i + 1, speedMode: widget.speedMode);
          final totalSec = (delay.inMilliseconds / 1000).ceil();
          for (int s = totalSec; s > 0; s--) {
            if (_isCancelled || !mounted) break;
            while (_isPaused && !_isCancelled && mounted) {
              await Future<void>.delayed(const Duration(milliseconds: 300));
            }
            if (mounted) {
              setState(() {
                _progressStatus = '🛡️ Reta Anti-Ban ($s s) anvan pwochen moun (Ang #${((i + 1) % 5) + 1}/5)...';
              });
            }
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
      }
    }

    if (mounted) {
      Navigator.of(context).pop(_sentCount);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = widget.recipients.length;
    final processed = (_sentCount + _failedCount).clamp(0, total);
    final progress = total > 0 ? (processed / total) : 0.0;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(LucideIcons.send, color: Color(0xFF15803D)),
          const SizedBox(width: 8),
          Text(
            'Voye Kanpay WhatsApp (Anti-Ban Pro)',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.shieldCheck, size: 16, color: Color(0xFF15803D)),
                  const SizedBox(width: 6),
                  Text(
                    'Motè IA Semantik (5 Ang Diferan) + Reta Imèn (${widget.speedMode})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF15803D)),
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Mesaj voye : ${_sentCount.clamp(0, total)} / $total',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                if (_failedCount > 0)
                  Text(
                    '${_failedCount.clamp(0, total)} echwe',
                    style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _progressStatus,
                style: TextStyle(
                  fontSize: 13,
                  color: _coolingSeconds > 0
                      ? const Color(0xFFF59E0B)
                      : (_isPaused ? Colors.amber.shade700 : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155))),
                  fontWeight: (_coolingSeconds > 0 || _isPaused) ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: _isPaused ? Colors.green : Colors.amber.shade700,
            side: BorderSide(color: _isPaused ? Colors.green : Colors.amber.shade700),
          ),
          onPressed: () {
            setState(() {
              _isPaused = !_isPaused;
              if (_isPaused) {
                _progressStatus = '⏸️ Kanpay an poz. Klike "Kontinye voye" lè w pare.';
              } else {
                _progressStatus = 'Repriz voye kanpay la...';
              }
            });
          },
          icon: Icon(_isPaused ? LucideIcons.play : LucideIcons.pause, size: 16),
          label: Text(_isPaused ? 'Kontinye voye' : 'Fè yon pòz (Pause)'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            setState(() {
              _isCancelled = true;
              _isPaused = false;
              _progressStatus = 'Kanpe voye a...';
            });
            Navigator.of(context).pop(_sentCount);
          },
          icon: const Icon(LucideIcons.octagonAlert, size: 16),
          label: const Text('Kanpe voye a (Annuler)'),
        ),
      ],
    );
  }
}
