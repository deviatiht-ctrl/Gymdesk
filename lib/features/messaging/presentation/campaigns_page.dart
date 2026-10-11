import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/sync/sync_models.dart';
import '../../../l10n/app_strings.dart';
import '../data/brevo_service.dart';

class CampaignsPage extends ConsumerStatefulWidget {
  const CampaignsPage({super.key});

  @override
  ConsumerState<CampaignsPage> createState() => _CampaignsPageState();
}

class _CampaignsPageState extends ConsumerState<CampaignsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _brevoService = BrevoService();

  // Fòmilè Kanpay
  final _titleController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final _searchController = TextEditingController();

  String _templateKey = 'inactive_winback';
  String _filterStatus = 'all'; // Tout manm parètTous les membres s'affichent par défaut

  bool _loadingPreview = false;
  List<Map<String, dynamic>> _previewRecipients = [];
  final Set<String> _selectedMemberIds = {};

  bool _showVisualPreview = false;
  bool _isSending = false;
  BrevoSendProgress? _sendProgress;

  // Konfigirasyon Brevo
  BrevoConfig _brevoConfig = const BrevoConfig(apiKey: '', senderEmail: '', senderName: 'GymDesk');

  // Istorik
  bool _loadingHistory = true;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBrevoConfig();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = AppStrings.of(context);
      _applyTemplate('inactive_winback', s);
      _runPreview();
    });
  }

  Future<void> _loadBrevoConfig() async {
    final cfg = await _brevoService.loadConfig();
    if (mounted) setState(() => _brevoConfig = cfg);
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
            ? 'Bonjour {nom},\n\nCela fait un moment que nous ne t\'avons pas vu à la salle ! Ta santé, ta forme et ton énergie se construisent chaque jour.\n\nReviens t\'entraîner dès cette semaine et bénéficie d\'une offre exclusive sur ton réabonnement. Toute l\'équipe et les coachs t\'attendent avec impatience pour t\'aider à atteindre tes objectifs.\n\nÀ très vite à la salle !'
            : isEn
                ? 'Hello {nom},\n\nIt\'s been a while since we saw you at the gym! Your fitness and energy matter every single day.\n\nCome back this week and enjoy an exclusive discount on your renewal. The whole coaching team is waiting for you.\n\nSee you soon at the gym!'
                : 'Bonjou {nom},\n\nSa fè yon ti moman depi nou pa wè w nan gym lan ! Sante w, fòs ou ak enèji w se pi gwo richès ou.\n\nRetounen antrene semèn sa a epi pwofite yon rabè espesyal sou re-abònman w lan. Tout ekip la ak antrenè yo ap tann ou pou kontinye avanse ansanm.\n\nN ap tann ou !';
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
            ? '🔥 Rejoins le Grand Défi & Cours Collectif ce samedi'
            : isEn
                ? '🔥 Join our Special Fitness Challenge this Saturday'
                : '🔥 Patisipe nan Gwo Defi ak Antrenman Kolektif Samdi a';
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
            ? '🎉 Remise spéciale sur les abonnements de 3 mois et plus'
            : isEn
                ? '🎉 Special discount on 3-month renewals and more'
                : '🎉 Rabè espesyal sou renouvèlman 3 mwa oswa plis';
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

    // 1. Lire d'abord dans la base locale Drift (SQLite) si disponible (Offline-first)
    if (runtime.database != null && gymId != null) {
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
          var query = client.from('members').select('id, first_name, last_name, email, phone, whatsapp, status');
          if (gymId != null) query = query.eq('gym_id', gymId);
          final membersRes = await query;
          for (final m in (membersRes as List)) {
            final p = m as Map<String, dynamic>;
            rawMembers.add({
              'member_id': p['id']?.toString() ?? '',
              'name': '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim(),
              'email': p['email']?.toString() ?? '',
              'phone': p['phone']?.toString() ?? '',
              'whatsapp': p['whatsapp']?.toString() ?? '',
              'status': p['status']?.toString() ?? 'active',
              'plan_name': 'Abonnement Gym',
            });
          }
        }
      } catch (_) {}
    }

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
        _previewRecipients = filtered;
        _selectedMemberIds.clear();
        for (final m in filtered) {
          final id = m['member_id']?.toString() ?? '';
          final email = m['email']?.toString() ?? '';
          if (id.isNotEmpty && email.contains('@')) {
            _selectedMemberIds.add(id);
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

  void _showBrevoDialog() {
    final s = AppStrings.of(context);
    final apiKeyController = TextEditingController(text: _brevoConfig.apiKey);
    final senderEmailController = TextEditingController(text: _brevoConfig.senderEmail);
    final senderNameController = TextEditingController(text: _brevoConfig.senderName);

    bool isTesting = false;
    String? testResult;
    bool testSuccess = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(LucideIcons.mail, color: Color(0xFF0F766E)),
                const SizedBox(width: 10),
                Text(s.text('brevo_settings_btn')),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: const Text(
                        'Pour envoyer les emails automatiquement (logo, relances, reçus), renseignez votre clé API Brevo (anciennement Sendinblue).',
                        style: TextStyle(fontSize: 13, color: Color(0xFF166534)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: apiKeyController,
                      decoration: InputDecoration(
                        labelText: s.text('brevo_api_key_label'),
                        hintText: 'xkeysib-xxxxxxxxxxxxxxxx',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(LucideIcons.key),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: senderEmailController,
                      decoration: InputDecoration(
                        labelText: s.text('brevo_sender_email_label'),
                        hintText: 'contact@votregym.com',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(LucideIcons.atSign),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: senderNameController,
                      decoration: InputDecoration(
                        labelText: s.text('brevo_sender_name_label'),
                        hintText: 'GymDesk Fitness Club',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(LucideIcons.building),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (testResult != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: testSuccess ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          testResult!,
                          style: TextStyle(
                            color: testSuccess ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: isTesting
                              ? null
                              : () async {
                                  setModalState(() {
                                    isTesting = true;
                                    testResult = null;
                                  });
                                  try {
                                    final res = await _brevoService.testConnection(apiKeyController.text);
                                    setModalState(() {
                                      testSuccess = true;
                                      testResult = '${s.text('brevo_connected_success')} (${res['company'] ?? res['email']})';
                                    });
                                  } catch (e) {
                                    setModalState(() {
                                      testSuccess = false;
                                      testResult = '${s.text('brevo_connection_failed')} $e';
                                    });
                                  } finally {
                                    setModalState(() => isTesting = false);
                                  }
                                },
                          icon: isTesting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(LucideIcons.activity, size: 16),
                          label: Text(s.text('test_brevo_btn')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Commande Supabase Secrets (Serveur)', style: TextStyle(fontSize: 13)),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            'npx supabase secrets set BREVO_API_KEY="${apiKeyController.text.trim()}" BREVO_SENDER_EMAIL="${senderEmailController.text.trim()}" BREVO_SENDER_NAME="${senderNameController.text.trim()}"',
                            style: const TextStyle(color: Color(0xFF38BDF8), fontFamily: 'monospace', fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('cancel'))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final newCfg = BrevoConfig(
                    apiKey: apiKeyController.text.trim(),
                    senderEmail: senderEmailController.text.trim(),
                    senderName: senderNameController.text.trim().isEmpty ? 'GymDesk' : senderNameController.text.trim(),
                  );
                  final messenger = ScaffoldMessenger.of(context);
                  final msg = s.text('brevo_saved_success');
                  await _brevoService.saveConfig(newCfg);
                  if (mounted) setState(() => _brevoConfig = newCfg);
                  if (ctx.mounted) Navigator.pop(ctx);
                  messenger.showSnackBar(
                    SnackBar(content: Text(msg), backgroundColor: const Color(0xFF059669)),
                  );
                },
                child: Text(s.text('save_brevo_settings')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _sendCampaign() async {
    final s = AppStrings.of(context);
    final title = _titleController.text.trim();
    final subject = _subjectController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || subject.isEmpty || body.isEmpty) {
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

    if (!_brevoConfig.isConfigured) {
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.text('brevo_not_configured')),
          content: const Text(
            'Pour envoyer vos emails aux membres, vous devez configurer votre clé API Brevo et votre adresse email expéditeur.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('cancel'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.text('brevo_settings_btn')),
            ),
          ],
        ),
      );
      if (openSettings == true) _showBrevoDialog();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('send_campaign_btn')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Êtes-vous sûr de vouloir envoyer cette campagne à ${targetRecipients.length} membre(s) sélectionné(s) ?'),
            const SizedBox(height: 12),
            Text('• Objet : $subject', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('• Expéditeur : ${_brevoConfig.senderName} (${_brevoConfig.senderEmail})'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.text('send_campaign_btn')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSending = true;
      _sendProgress = BrevoSendProgress(current: 0, total: targetRecipients.length, successCount: 0, failCount: 0);
    });

    final gymId = ref.read(appRuntimeProvider).session?.gymId;
    final gymName = _brevoConfig.senderName;

    try {
      // 1. Envoi direct via Brevo API avec Stream de progression
      await for (final progress in _brevoService.sendBatchCampaign(
        config: _brevoConfig,
        recipients: targetRecipients,
        title: title,
        subjectTemplate: subject,
        bodyTemplate: body,
        gymName: gymName,
      )) {
        if (mounted) setState(() => _sendProgress = progress);
      }

      // 2. Enregistrement dans Supabase pour l'historique
      if (gymId != null) {
        try {
          final client = Supabase.instance.client;
          await client.from('campaigns').insert({
            'gym_id': gymId,
            'title': title,
            'subject': subject,
            'body_text': body,
            'template_key': _templateKey,
            'filter': {'status': _filterStatus},
            'status': 'sent',
            'sent_at': DateTime.now().toIso8601String(),
            'recipient_count': _sendProgress?.successCount ?? targetRecipients.length,
          });
        } catch (_) {}
      }

      if (mounted) {
        final success = _sendProgress?.successCount ?? 0;
        final total = targetRecipients.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$success $total ${s.text('sent_count_summary')} $total'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
        _loadHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ActionChip(
              avatar: Icon(
                _brevoConfig.isConfigured ? LucideIcons.circleCheck : LucideIcons.key,
                size: 16,
                color: _brevoConfig.isConfigured ? const Color(0xFF047857) : const Color(0xFFB45309),
              ),
              label: Text(
                _brevoConfig.isConfigured ? s.text('brevo_configured') : s.text('brevo_not_configured'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: _brevoConfig.isConfigured ? const Color(0xFF047857) : const Color(0xFFB45309),
                ),
              ),
              backgroundColor: _brevoConfig.isConfigured ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
              onPressed: _showBrevoDialog,
            ),
          ),
        ],
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Barre de choix du Modèle Gym
              Card(
                elevation: 0,
                color: const Color(0xFFF8FAFC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade300),
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
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade300),
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
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          DropdownButton<String>(
                            value: _filterStatus,
                            underline: const SizedBox(),
                            icon: const Icon(LucideIcons.chevronDown, size: 16),
                            items: [
                              DropdownMenuItem(value: 'expired', child: Text(s.text('filter_inactive_members'))),
                              DropdownMenuItem(value: 'active', child: Text(s.text('filter_active_members'))),
                              DropdownMenuItem(value: 'expiring', child: Text(s.text('filter_expiring_soon'))),
                              DropdownMenuItem(value: 'all', child: Text(s.text('filter_all_members'))),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _filterStatus = val);
                                _runPreview();
                              }
                            },
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
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
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
                        height: 200,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _loadingPreview
                            ? const Center(child: CircularProgressIndicator())
                            : _filteredRecipients.isEmpty
                                ? Center(child: Text(s.text('no_recipients_found')))
                                : ListView.separated(
                                    itemCount: _filteredRecipients.length,
                                    separatorBuilder: (_, index) => const Divider(height: 1),
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
                                            Text(item['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isInactive ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                isInactive ? 'Inactif' : 'Actif',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isInactive ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
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
                                                  color: const Color(0xFFFEF3C7),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text('Sans email (WhatsApp)', style: TextStyle(fontSize: 10, color: Color(0xFFB45309), fontWeight: FontWeight.bold)),
                                              )
                                            else
                                              Text(item['email'].toString(), style: const TextStyle(fontSize: 12)),
                                            if (item['phone'] != null && item['phone'].toString().isNotEmpty)
                                              Text(' • ${item['phone']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                          ],
                                        ),
                                        secondary: CircleAvatar(
                                          backgroundColor: const Color(0xFFE2E8F0),
                                          child: Text(
                                            (item['name']?.toString() ?? 'M').substring(0, 1).toUpperCase(),
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569)),
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
                    labelText: '${s.text('campaign_title_field')} *',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _subjectController,
                  decoration: InputDecoration(
                    labelText: '${s.text('campaign_subject_field')} *',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Tags dynamiques : ', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    ActionChip(
                      label: Text(s.text('insert_tag_nom')),
                      onPressed: () => _insertTag('{nom}'),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      label: Text(s.text('insert_tag_gym')),
                      onPressed: () => _insertTag('{gym}'),
                    ),
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

              // 5. Progression d'envoi en direct si actif
              if (_isSending && _sendProgress != null) ...[
                Card(
                  color: const Color(0xFFF0FDF4),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              s.text('sending_to_members'),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                            ),
                            Text(
                              '${_sendProgress!.current} / ${_sendProgress!.total}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _sendProgress!.total > 0 ? _sendProgress!.current / _sendProgress!.total : 0,
                          backgroundColor: Colors.white,
                          color: const Color(0xFF0F766E),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _sendProgress!.currentRecipient,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF15803D)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

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
    final isSelected = _templateKey == key;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label),
      selectedColor: const Color(0xFFCCFBF1),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF0F766E) : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => _applyTemplate(key, s),
    );
  }

  Widget _buildVisualEmailPreview(AppStrings s) {
    final title = _titleController.text.trim().isEmpty ? 'Titre de la Campagne' : _titleController.text.trim();
    final body = _bodyController.text.trim().isEmpty ? 'Contenu de votre message...' : _bodyController.text.trim();
    final sampleName = _filteredRecipients.isNotEmpty ? _filteredRecipients.first['name'] : 'Jean Dupont';
    final gymName = _brevoConfig.senderName.isNotEmpty ? _brevoConfig.senderName : 'GymDesk';

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
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_history.isEmpty) {
      return Center(
        child: Text(s.text('campaign_history')),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _history.length,
      itemBuilder: (context, idx) {
        final item = _history[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE0F2FE),
              child: Icon(LucideIcons.mailCheck, color: Color(0xFF0369A1)),
            ),
            title: Text(item['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${item['subject']}\n${item['created_at']?.toString().substring(0, 16) ?? ''}'),
            isThreeLine: true,
            trailing: Chip(
              label: Text('${item['recipient_count'] ?? 0}'),
              backgroundColor: const Color(0xFFDCFCE7),
              labelStyle: const TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }
}
