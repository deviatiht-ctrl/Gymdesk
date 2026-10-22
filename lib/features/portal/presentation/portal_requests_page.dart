import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/biometrics/biometric_service.dart';
import '../../../l10n/app_strings.dart';
import '../../members/domain/member.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../data/portal_repository.dart';
import '../domain/portal_request.dart';
import 'portal_process_dialog.dart';

class PortalRequestsPage extends ConsumerStatefulWidget {
  const PortalRequestsPage({super.key});

  @override
  ConsumerState<PortalRequestsPage> createState() => _PortalRequestsPageState();
}

class _PortalRequestsPageState extends ConsumerState<PortalRequestsPage> {
  late final PortalRepository _portalRepo;
  late final BiometricService _biometricService;
  String _statusFilter = 'pending'; // 'pending', 'completed', 'all'
  String _kindFilter = 'all'; // 'all', 'new_membership', 'renewal'
  bool _isLoading = true;
  String? _errorMessage;
  List<PortalRequest> _allRequests = [];
  bool _isScanningFingerprint = false;
  Timer? _autoSyncTimer;
  bool _isSilentPolling = false;

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _portalRepo = PortalRepository(runtime.client);
    _biometricService = BiometricService();
    _loadRequests();
    // Synchronisation automatique temps réel chaque 1 seconde
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _silentPollRequests();
      }
    });
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _biometricService.dispose();
    super.dispose();
  }

  Future<void> _silentPollRequests() async {
    if (_isSilentPolling || _isLoading) return;
    _isSilentPolling = true;
    try {
      final gymId = ref.read(appRuntimeProvider).session?.gymId;
      if (gymId == null) return;
      final list = await _portalRepo.fetchRequests(
        gymId,
        status: _statusFilter == 'all' ? null : _statusFilter,
      );
      if (!mounted) return;
      final changed = list.length != _allRequests.length ||
          list.asMap().entries.any((entry) {
            final prev = _allRequests[entry.key];
            final curr = entry.value;
            return prev.id != curr.id ||
                prev.status != curr.status ||
                prev.updatedAt != curr.updatedAt ||
                prev.notes != curr.notes;
          });
      if (changed) {
        setState(() {
          _allRequests = list;
          _errorMessage = null;
        });
      }
    } catch (_) {
    } finally {
      _isSilentPolling = false;
    }
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final gymId = ref.read(appRuntimeProvider).session?.gymId;
      if (gymId == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Aucun gym sélectionné';
        });
        return;
      }

      final list = await _portalRepo.fetchRequests(
        gymId,
        status: _statusFilter == 'all' ? null : _statusFilter,
      );

      if (mounted) {
        setState(() {
          _allRequests = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Erreur de chargement : $e';
        });
      }
    }
  }

  List<PortalRequest> get _filteredRequests {
    if (_kindFilter == 'all') return _allRequests;
    return _allRequests.where((r) => r.kind == _kindFilter).toList();
  }

  Future<void> _updateStatus(String requestId, String newStatus) async {
    try {
      await _portalRepo.updateStatus(requestId, newStatus);
      _loadRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  String _portalUrl({bool isRenewal = false}) {
    final gymId = ref.read(appRuntimeProvider).session?.gymId ?? '';
    if (isRenewal) {
      return 'https://securgym.com/join/$gymId?kind=renewal';
    }
    return 'https://securgym.com/join/$gymId?kind=new_membership';
  }

  void _copyLink(String url, String label) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copié : $url'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showQrCodeDialog(AppStrings s) {
    final isRenewalNotifier = ValueNotifier<bool>(false);

    showDialog<void>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<bool>(
        valueListenable: isRenewalNotifier,
        builder: (context, isRenewal, _) {
          final url = _portalUrl(isRenewal: isRenewal);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(LucideIcons.qrCode, color: Color(0xFF0F766E), size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.text('qr_modal_title'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.text('qr_modal_subtitle'),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(s.text('request_kind_new')),
                        icon: const Icon(LucideIcons.userPlus, size: 16),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(s.text('request_kind_renewal')),
                        icon: const Icon(LucideIcons.refreshCw, size: 16),
                      ),
                    ],
                    selected: {isRenewal},
                    onSelectionChanged: (set) => isRenewalNotifier.value = set.first,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: url,
                      version: QrVersions.auto,
                      size: 210,
                      gapless: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    url,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(LucideIcons.copy, size: 16),
                label: Text(isRenewal ? s.text('copy_renewal_link') : s.text('copy_join_link')),
                onPressed: () {
                  _copyLink(url, isRenewal ? 'Lien de renouvellement' : 'Lien d’inscription');
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(LucideIcons.externalLink, size: 16),
                label: const Text('Ouvrir'),
                onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Member?> _findMemberByPhone(String phone) async {
    final db = ref.read(appRuntimeProvider).database;
    if (db == null) return null;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) return null;

    final rows = await db.customSelect(
      "SELECT payload FROM records WHERE entity = 'members' AND deleted_at IS NULL",
      readsFrom: {db.records},
    ).get();

    for (final r in rows) {
      try {
        final payload = jsonDecode(r.read<String>('payload')) as Map<String, dynamic>;
        final m = Member(payload);
        final mDigits = (m.phone ?? m.whatsapp ?? '').replaceAll(RegExp(r'\D'), '');
        if (mDigits.contains(digits) || digits.contains(mDigits)) {
          return m;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _identifyByFingerprint(PortalRequest req) async {
    if (_isScanningFingerprint) return;
    setState(() => _isScanningFingerprint = true);

    try {
      final sample = await _biometricService.captureFingerprintSample().timeout(const Duration(seconds: 15));
      if (sample.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Empreinte non reconnue. Réessayez.')),
          );
        }
        return;
      }

      final db = ref.read(appRuntimeProvider).database;
      if (db == null) return;

      final rows = await db.customSelect(
        "SELECT payload FROM records WHERE entity = 'members' AND deleted_at IS NULL",
        readsFrom: {db.records},
      ).get();

      final memberList = <Member>[];
      for (final r in rows) {
        try {
          final payload = jsonDecode(r.read<String>('payload')) as Map<String, dynamic>;
          final m = Member(payload);
          if (m.fingerprintRegistered) {
            memberList.add(m);
          }
        } catch (_) {}
      }

      if (memberList.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aucune empreinte enregistrée dans la base locale.')),
          );
        }
        return;
      }

      final matched = await _biometricService.match1toN(
        candidateTemplate: sample,
        members: memberList,
      );

      if (matched != null) {
        if (mounted) {
          _showMemberMatchedDialog(req, matched);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aucun membre correspondant trouvé pour cette empreinte.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur biométrique : $e')));
      }
    } finally {
      if (mounted) setState(() => _isScanningFingerprint = false);
    }
  }

  void _showMemberMatchedDialog(PortalRequest req, Member member) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(LucideIcons.userCheck, color: Color(0xFF059669), size: 26),
            SizedBox(width: 10),
            Text('Membre identifié !'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${member.fullName} (${member.memberNumber})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text('Téléphone : ${member.phone ?? member.whatsapp ?? '-'}'),
            if (req.planName != null) ...[
              const SizedBox(height: 6),
              Text(
                'Formule demandée : ${req.planName} (${req.planPrice?.toStringAsFixed(0) ?? ''} ${req.planCurrency ?? ''})',
                style: const TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(LucideIcons.wallet, size: 16),
            label: const Text('Ouvrir profil & Encaisser'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref.read(appRuntimeProvider).client.from('portal_requests').update({
                  'status': 'completed',
                  'member_id': member.id,
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                }).eq('id', req.id);
              } catch (_) {
                _updateStatus(req.id, 'completed');
              }
              _loadRequests();
              if (mounted) context.go('/members/${member.id}');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleRenewalValidation(PortalRequest req) async {
    final member = await _findMemberByPhone(req.phone);
    if (!mounted) return;

    if (member != null) {
      _showMemberMatchedDialog(req, member);
    } else {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Membre non trouvé par téléphone'),
          content: Text(
            'Aucun membre n’a été trouvé avec le numéro "${req.phone}".\n'
            'Vous pouvez poser son doigt sur le lecteur USB pour l’identifier, ou le rechercher dans la liste des membres.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.fingerprint, size: 16),
              label: const Text('Scanner empreinte (USB)'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _identifyByFingerprint(req);
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(LucideIcons.search, size: 16),
              label: const Text('Voir liste membres'),
              onPressed: () {
                Navigator.of(ctx).pop();
                context.go('/members');
              },
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    final pendingCount = _allRequests.where((r) => r.status == 'pending').length;
    final displayRequests = _filteredRequests;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('portal_requests')),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            onPressed: () => _showQrCodeDialog(s),
            icon: const Icon(LucideIcons.qrCode, size: 18),
            label: Text(s.text('qr_code_join')),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'Liens du portail',
            icon: const Icon(LucideIcons.share2, size: 20),
            onSelected: (val) {
              if (val == 'copy_new') {
                _copyLink(_portalUrl(isRenewal: false), "Lien d'inscription");
              } else if (val == 'copy_renew') {
                _copyLink(_portalUrl(isRenewal: true), "Lien de renouvellement");
              } else if (val == 'open_new') {
                launchUrl(Uri.parse(_portalUrl(isRenewal: false)), mode: LaunchMode.externalApplication);
              } else if (val == 'open_renew') {
                launchUrl(Uri.parse(_portalUrl(isRenewal: true)), mode: LaunchMode.externalApplication);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'copy_new',
                child: Row(
                  children: [
                    Icon(LucideIcons.copy, size: 16, color: Color(0xFF0F766E)),
                    SizedBox(width: 8),
                    Text("Copier lien Inscription"),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'copy_renew',
                child: Row(
                  children: [
                    Icon(LucideIcons.refreshCw, size: 16, color: Color(0xFF2563EB)),
                    SizedBox(width: 8),
                    Text("Copier lien Renouvellement"),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'open_new',
                child: Row(
                  children: [
                    Icon(LucideIcons.externalLink, size: 16),
                    SizedBox(width: 8),
                    Text("Ouvrir page Inscription"),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'open_renew',
                child: Row(
                  children: [
                    Icon(LucideIcons.externalLink, size: 16),
                    SizedBox(width: 8),
                    Text("Ouvrir page Renouvellement"),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loadRequests,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barre de filtres (Statut & Type)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Filtre Statut
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'pending',
                      label: Text(
                        _statusFilter == 'pending' && pendingCount > 0
                            ? 'En attente ($pendingCount)'
                            : 'En attente',
                      ),
                      icon: const Icon(LucideIcons.clock, size: 16),
                    ),
                    const ButtonSegment(
                      value: 'completed',
                      label: Text('Finalisées'),
                      icon: Icon(LucideIcons.checkCircle2, size: 16),
                    ),
                    const ButtonSegment(
                      value: 'all',
                      label: Text('Toutes'),
                      icon: Icon(LucideIcons.listFilter, size: 16),
                    ),
                  ],
                  selected: {_statusFilter},
                  onSelectionChanged: (set) {
                    setState(() => _statusFilter = set.first);
                    _loadRequests();
                  },
                ),

                // Filtre Type (Nouvelle adhésion vs Renouvellement)
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'all',
                      label: Text(s.text('all_kinds')),
                      icon: const Icon(LucideIcons.layers, size: 16),
                    ),
                    ButtonSegment(
                      value: 'new_membership',
                      label: Text(s.text('request_kind_new')),
                      icon: const Icon(LucideIcons.userPlus, size: 16),
                    ),
                    ButtonSegment(
                      value: 'renewal',
                      label: Text(s.text('request_kind_renewal')),
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                    ),
                  ],
                  selected: {_kindFilter},
                  onSelectionChanged: (set) => setState(() => _kindFilter = set.first),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.radio, size: 14, color: Color(0xFF15803D)),
                      SizedBox(width: 6),
                      Text(
                        'Temps réel (Sync 1s)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Liste des demandes
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.alertTriangle, size: 40, color: Colors.orange),
                            const SizedBox(height: 8),
                            Text(_errorMessage!),
                            const SizedBox(height: 12),
                            ElevatedButton(onPressed: _loadRequests, child: const Text('Réessayer')),
                          ],
                        ),
                      )
                    : displayRequests.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.inbox, size: 54, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(
                                    s.text('portal_no_requests'),
                                    style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey.shade700),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    s.text('portal_requests_hint'),
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F766E),
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => _showQrCodeDialog(s),
                                    icon: const Icon(LucideIcons.qrCode, size: 16),
                                    label: Text(s.text('qr_code_join')),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(20),
                            itemCount: displayRequests.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final req = displayRequests[index];
                              return _buildRequestCard(s, req);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(AppStrings s, PortalRequest req) {
    final digits = req.phone.replaceAll(RegExp(r'\D'), '');
    final isRenewal = req.kind == 'renewal';
    final waText = isRenewal
        ? 'Bonjour ${req.firstName} ! Nous avons bien reçu votre demande de renouvellement pour notre salle de sport.'
        : 'Bonjour ${req.firstName} ! Nous avons bien reçu votre demande d\'inscription pour notre salle de sport.';
    final waUrl = 'https://wa.me/$digits?text=${Uri.encodeComponent(waText)}';

    final isPending = req.status == 'pending';
    final isCompleted = req.status == 'completed';

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isPending
              ? (isRenewal ? const Color(0xFFC7D2FE) : const Color(0xFF99F6E4))
              : Colors.grey.shade300,
          width: isPending ? 1.5 : 1,
        ),
      ),
      color: isPending
          ? (isRenewal ? const Color(0xFFF5F3FF) : const Color(0xFFF0FDFA).withOpacity(0.4))
          : Colors.white,
      child: InkWell(
        onTap: isPending
            ? () => PortalProcessDialog.show(
                  context,
                  request: req,
                  onCompleted: _loadRequests,
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 680;
              final infoSection = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        req.fullName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      // Badge Type
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isRenewal ? const Color(0xFFEDE9FE) : const Color(0xFFCCFBF1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isRenewal ? LucideIcons.refreshCw : LucideIcons.userPlus,
                              size: 11,
                              color: isRenewal ? const Color(0xFF6D28D9) : const Color(0xFF0F766E),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isRenewal ? s.text('request_kind_renewal') : s.text('request_kind_new'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isRenewal ? const Color(0xFF6D28D9) : const Color(0xFF0F766E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Badge Statut
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isPending
                              ? const Color(0xFFFEF3C7)
                              : (isCompleted ? const Color(0xFFD1FAE5) : Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isPending ? 'En attente' : (isCompleted ? 'Finalisé' : req.status),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isPending
                                ? const Color(0xFF92400E)
                                : (isCompleted ? const Color(0xFF065F46) : Colors.black87),
                          ),
                        ),
                      ),
                      Text(
                        ymd(req.createdAt),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.phone, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(req.phone, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      if (req.email != null && req.email!.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.mail, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(req.email!, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                          ],
                        ),
                    ],
                  ),
                  if (req.planName != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isRenewal ? const Color(0xFFF3E8FF) : const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Formule demandée : ${req.planName} (${req.planPrice?.toStringAsFixed(0) ?? ''} ${req.planCurrency ?? ''})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isRenewal ? const Color(0xFF7E22CE) : const Color(0xFF0369A1),
                        ),
                      ),
                    ),
                  ],
                  if (req.notes != null && req.notes!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Note : ${req.notes}',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                    ),
                  ],
                ],
              );

              final actionsSection = Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: isCompact ? WrapAlignment.start : WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isPending) ...[
                    if (isRenewal) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6D28D9),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => PortalProcessDialog.show(
                          context,
                          request: req,
                          onCompleted: _loadRequests,
                        ),
                        icon: const Icon(LucideIcons.refreshCw, size: 16),
                        label: Text(s.text('collect_renewal')),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6D28D9),
                          side: const BorderSide(color: Color(0xFFC7D2FE)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () => _handleRenewalValidation(req),
                        icon: _isScanningFingerprint
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(LucideIcons.fingerprint, size: 16),
                        label: Text(s.text('identify_member_fingerprint')),
                      ),
                    ] else ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => PortalProcessDialog.show(
                          context,
                          request: req,
                          onCompleted: _loadRequests,
                        ),
                        icon: const Icon(LucideIcons.checkCheck, size: 16),
                        label: Text(s.text('validate_and_enroll')),
                      ),
                    ],
                  ],
                  if (digits.length >= 8)
                    IconButton(
                      tooltip: 'Écrire sur WhatsApp',
                      icon: const Icon(LucideIcons.messageCircle, color: Color(0xFF25D366), size: 20),
                      onPressed: () => launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication),
                    ),
                  if (isPending)
                    IconButton(
                      tooltip: 'Rejeter la demande',
                      icon: const Icon(LucideIcons.xCircle, color: Colors.red, size: 20),
                      onPressed: () => _confirmReject(req),
                    ),
                ],
              );

              final avatar = Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isPending
                      ? (isRenewal ? const Color(0xFFEDE9FE) : const Color(0xFF0F766E).withOpacity(0.1))
                      : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCompleted
                      ? LucideIcons.checkCheck
                      : (isRenewal ? LucideIcons.refreshCw : (isPending ? LucideIcons.userPlus : LucideIcons.user)),
                  color: isRenewal
                      ? const Color(0xFF6D28D9)
                      : (isPending ? const Color(0xFF0F766E) : Colors.grey.shade600),
                  size: 20,
                ),
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        avatar,
                        const SizedBox(width: 12),
                        Expanded(child: infoSection),
                      ],
                    ),
                    const SizedBox(height: 12),
                    actionsSection,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  const SizedBox(width: 16),
                  Expanded(child: infoSection),
                  const SizedBox(width: 16),
                  actionsSection,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _confirmReject(PortalRequest req) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeter la demande'),
        content: Text('Voulez-vous marquer la demande de ${req.fullName} comme rejetée ?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(ctx).pop();
              _updateStatus(req.id, 'rejected');
            },
            child: const Text('Rejeter'),
          ),
        ],
      ),
    );
  }
}
