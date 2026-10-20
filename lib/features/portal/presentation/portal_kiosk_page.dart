import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/biometrics/access_agent_client.dart';
import '../../../core/biometrics/biometric_service.dart';
import '../data/portal_repository.dart';

/// Paj Kiosque Libre-Accès pou Borne devan pòt la oswa nan resepsyon an.
/// Pa mande okenn modpas oswa login, li lye dirèkteman ak kòd gym lan.
class PortalKioskPage extends ConsumerStatefulWidget {
  const PortalKioskPage({super.key, required this.gymCode});

  final String gymCode;

  @override
  ConsumerState<PortalKioskPage> createState() => _PortalKioskPageState();
}

class _PortalKioskPageState extends ConsumerState<PortalKioskPage> with SingleTickerProviderStateMixin {
  late final PortalRepository _portalRepo;
  late final BiometricService _biometricService;
  final _agent = AccessAgentClient();

  Map<String, dynamic>? _gym;
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  String? _error;

  late final AnimationController _pulseController;
  Timer? _clockTimer;
  Timer? _doorScanTimer;
  DateTime _now = DateTime.now();

  Map<String, dynamic>? _detectedMember;
  Timer? _detectedDismissTimer;

  String get _cleanCode => widget.gymCode.replaceAll(RegExp(r'/+$'), '').trim();

  String _joinUrl({required bool isRenewal}) {
    final kind = isRenewal ? 'renewal' : 'new_membership';
    return 'https://securgym.com/join/$_cleanCode?kind=$kind';
  }

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _portalRepo = PortalRepository(runtime.client);
    _biometricService = BiometricService(agentClient: _agent);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _loadGym();
    _startDoorScanPolling();
  }

  Future<void> _loadGym() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _portalRepo.getPublicGym(_cleanCode);
      final gymMap = res['gym'] as Map<String, dynamic>?;
      final rawPlans = res['plans'] as List<dynamic>? ?? [];

      if (gymMap == null) {
        setState(() {
          _loading = false;
          _error = 'Gym introuvable ou inactif.';
        });
        return;
      }

      setState(() {
        _gym = gymMap;
        _plans = rawPlans.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Erreur : $e';
      });
    }
  }

  void _startDoorScanPolling() {
    _doorScanTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      final latest = await _portalRepo.getLatestDoorScan(_cleanCode);
      if (latest['found'] == true && mounted) {
        final memberId = latest['member_id']?.toString();
        if (memberId != null && memberId != _detectedMember?['member_id']) {
          setState(() {
            _detectedMember = latest;
          });
          _detectedDismissTimer?.cancel();
          _detectedDismissTimer = Timer(const Duration(seconds: 15), () {
            if (mounted) setState(() => _detectedMember = null);
          });
        }
      }
    });
  }

  void _copyLink(String url, String label) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copié : $url'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _doorScanTimer?.cancel();
    _detectedDismissTimer?.cancel();
    _pulseController.dispose();
    _biometricService.dispose();
    _agent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF0D9488)),
        ),
      );
    }

    if (_error != null || _gym == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.alertTriangle, size: 54, color: Colors.amber),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Gym introuvable',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadGym,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final gymName = _gym!['name'] as String? ?? 'SecurGYM';
    final logoUrl = _gym!['logo_url'] as String?;
    final timeStr = DateFormat('HH:mm:ss').format(_now);
    final dateStr = DateFormat('EEEE d MMMM yyyy', 'fr').format(_now);

    final newUrl = _joinUrl(isRenewal: false);
    final renewUrl = _joinUrl(isRenewal: true);

    return Scaffold(
      backgroundColor: const Color(0xFF0B132B),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar Kiosk
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2541),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              child: Row(
                children: [
                  if (logoUrl != null && logoUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        logoUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(LucideIcons.dumbbell, size: 36, color: Color(0xFF0D9488)),
                      ),
                    )
                  else
                    const Icon(LucideIcons.dumbbell, size: 36, color: Color(0xFF0D9488)),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gymName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Text(
                        'Borne d’Accueil & Libre-Accès',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeStr,
                        style: const TextStyle(
                          color: Color(0xFF5EEAD4),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        dateStr,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Pop-up Détection Empreinte en Direct à la Porte
            if (_detectedMember != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF065F46), Color(0xFF047857)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.fingerprint, color: Color(0xFF6EE7B7), size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bonjour ${_detectedMember!['first_name']} ${_detectedMember!['last_name']} !',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Formule : ${_detectedMember!['current_plan_name'] ?? 'Abonnement'} · Statut : ${_detectedMember!['status'] == 'active' ? "Actif (${_detectedMember!['days_left']} j restants)" : "Expiré"}',
                            style: const TextStyle(color: Color(0xFFD1FAE5), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF065F46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        context.push('/join/$_cleanCode?kind=renewal');
                      },
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Renouveler', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

            // Contenu Principal : Deux Grandes Colonnes (Inscription & Renouvellement)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 720;
                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildKioskCard(
                                  title: 'Nouvelle Inscription',
                                  subtitle: 'Pas encore membre ? Scannez avec votre téléphone pour choisir votre formule et vous inscrire en 1 minute.',
                                  url: newUrl,
                                  accentColor: const Color(0xFF0D9488),
                                  icon: LucideIcons.userPlus,
                                  buttonLabel: 'Ouvrir sur cet écran',
                                  onOpenLocal: () => context.push('/join/$_cleanCode?kind=new_membership'),
                                  isRenewal: false,
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: _buildKioskCard(
                                  title: 'Renouvellement d’Abonnement',
                                  subtitle: 'Déjà membre ? Scannez avec votre téléphone ou posez votre doigt sur le lecteur pour renouveler sans frais d’inscription.',
                                  url: renewUrl,
                                  accentColor: const Color(0xFF2563EB),
                                  icon: LucideIcons.refreshCw,
                                  buttonLabel: 'Renouveler sur cet écran',
                                  onOpenLocal: () => context.push('/join/$_cleanCode?kind=renewal'),
                                  isRenewal: true,
                                ),
                              ),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              _buildKioskCard(
                                title: 'Nouvelle Inscription',
                                subtitle: 'Pas encore membre ? Scannez pour vous inscrire.',
                                url: newUrl,
                                accentColor: const Color(0xFF0D9488),
                                icon: LucideIcons.userPlus,
                                buttonLabel: 'Ouvrir sur cet écran',
                                onOpenLocal: () => context.push('/join/$_cleanCode?kind=new_membership'),
                                isRenewal: false,
                              ),
                              const SizedBox(height: 24),
                              _buildKioskCard(
                                title: 'Renouvellement d’Abonnement',
                                subtitle: 'Déjà membre ? Scannez ou posez votre doigt sur le lecteur.',
                                url: renewUrl,
                                accentColor: const Color(0xFF2563EB),
                                icon: LucideIcons.refreshCw,
                                buttonLabel: 'Renouveler sur cet écran',
                                onOpenLocal: () => context.push('/join/$_cleanCode?kind=renewal'),
                                isRenewal: true,
                              ),
                            ],
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Bar: Zone Empreinte Interactif
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2541),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              child: Row(
                children: [
                  FadeTransition(
                    opacity: _pulseController,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(LucideIcons.fingerprint, color: Color(0xFF5EEAD4), size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Lecteur d’empreinte actif · Posez votre doigt sur le lecteur pour afficher votre profil et renouveler.',
                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copier les liens',
                    icon: const Icon(LucideIcons.share2, color: Colors.white70, size: 20),
                    onPressed: () {
                      _copyLink(renewUrl, 'Lien de renouvellement');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKioskCard({
    required String title,
    required String subtitle,
    required String url,
    required Color accentColor,
    required IconData icon,
    required String buttonLabel,
    required VoidCallback onOpenLocal,
    required bool isRenewal,
  }) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: accentColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // QR Code blanc net
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
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
            style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          if (_plans.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: _plans.take(4).map((p) {
                final name = p['name'] ?? '';
                final price = (p['price'] as num?)?.toDouble() ?? 0.0;
                final cur = p['currency'] ?? 'HTG';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$name · ${price.toStringAsFixed(0)} $cur',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: onOpenLocal,
                  icon: const Icon(LucideIcons.arrowRight, size: 18),
                  label: Text(
                    buttonLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: 'Copier le lien',
                style: IconButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _copyLink(url, title),
                icon: const Icon(LucideIcons.copy, size: 18, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
