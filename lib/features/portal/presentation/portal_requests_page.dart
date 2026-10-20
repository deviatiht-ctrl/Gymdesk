import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../l10n/app_strings.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../data/portal_repository.dart';
import '../domain/portal_request.dart';

class PortalRequestsPage extends ConsumerStatefulWidget {
  const PortalRequestsPage({super.key});

  @override
  ConsumerState<PortalRequestsPage> createState() => _PortalRequestsPageState();
}

class _PortalRequestsPageState extends ConsumerState<PortalRequestsPage> {
  late final PortalRepository _portalRepo;
  String _statusFilter = 'pending'; // 'pending', 'completed', 'all'
  bool _isLoading = true;
  String? _errorMessage;
  List<PortalRequest> _requests = [];

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _portalRepo = PortalRepository(runtime.client);
    _loadRequests();
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
          _requests = list;
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

  void _copyPortalLink(AppStrings s) {
    final gymId = ref.read(appRuntimeProvider).session?.gymId ?? '';
    final link = 'https://app.gymdesk.com/join/$gymId';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Lien copié dans le presse-papier : $link'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final gymId = ref.read(appRuntimeProvider).session?.gymId ?? '';

    final pendingCount = _requests.where((r) => r.status == 'pending').length;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('portal_requests')),
        actions: [
          TextButton.icon(
            onPressed: () => _copyPortalLink(s),
            icon: const Icon(LucideIcons.share2, size: 16),
            label: const Text('Partager lien d’adhésion'),
          ),
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
          // Barre de filtres
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
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
                const Spacer(),
                Text(
                  'Lien public : /join/$gymId',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
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
                    : _requests.isEmpty
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
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
                                    onPressed: () => _copyPortalLink(s),
                                    icon: const Icon(LucideIcons.copy, size: 16),
                                    label: const Text('Copier le lien public'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(20),
                            itemCount: _requests.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final req = _requests[index];
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
    final waUrl = 'https://wa.me/$digits?text=${Uri.encodeComponent('Bonjour ${req.firstName} ! Nous avons bien reçu votre demande d\'inscription pour notre salle de sport.')}';

    final isPending = req.status == 'pending';
    final isCompleted = req.status == 'completed';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isPending ? const Color(0xFF99F6E4) : Colors.grey.shade300,
          width: isPending ? 1.5 : 1,
        ),
      ),
      color: isPending ? const Color(0xFFF0FDFA).withOpacity(0.4) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isPending ? const Color(0xFF0F766E).withOpacity(0.1) : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCompleted ? LucideIcons.checkCheck : (isPending ? LucideIcons.userPlus : LucideIcons.user),
                color: isPending ? const Color(0xFF0F766E) : Colors.grey.shade600,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        req.fullName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isPending
                              ? const Color(0xFFFEF3C7)
                              : (isCompleted ? const Color(0xFFD1FAE5) : Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isPending ? 'En attente' : (isCompleted ? 'Inscrit' : req.status),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isPending
                                ? const Color(0xFF92400E)
                                : (isCompleted ? const Color(0xFF065F46) : Colors.black87),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        ymd(req.createdAt),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(LucideIcons.phone, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(req.phone, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      if (req.email != null && req.email!.isNotEmpty) ...[
                        const SizedBox(width: 14),
                        Icon(LucideIcons.mail, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(req.email!, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                      ],
                    ],
                  ),
                  if (req.planName != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Formule demandée : ${req.planName} (${req.planPrice?.toStringAsFixed(0) ?? ''} ${req.planCurrency ?? ''})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0369A1)),
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
              ),
            ),
            const SizedBox(width: 16),
            // Actions
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isPending) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      context.go(
                        '/members/new',
                        extra: {
                          'firstName': req.firstName,
                          'lastName': req.lastName,
                          'phone': req.phone,
                          'email': req.email,
                          'planId': req.planId,
                          'portalRequestId': req.id,
                        },
                      );
                    },
                    icon: const Icon(LucideIcons.checkCheck, size: 16),
                    label: Text(s.text('validate_and_enroll')),
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                ),
              ],
            ),
          ],
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
