import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/access_control/access_monitor.dart';
import '../../../core/access_control/display_bridge.dart';
import '../../../core/access_control/terminal_access_service.dart';
import '../../../core/storage/person_photo_cache.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/biometrics/access_agent_client.dart';
import '../../../core/biometrics/biometric_service.dart';
import '../../../l10n/app_strings.dart';
import '../../members/data/members_repository.dart';
import '../../members/domain/member.dart';
import '../../settings/data/settings_repository.dart';

/// Ouvrir l'écran d'accès sur le 2e écran public ou tablette Wi-Fi.
Future<void> openAccessDisplayWindow([BuildContext? context, bool isTablet = false]) async {
  final target = isTablet ? '/tablet-access' : '/access-display';
  final displayUrl = AccessDisplayBridge.instance.displayUrlFor(target);
  final opened = await AccessDisplayBridge.instance.openDisplayWindow(target);
  if (context == null || !context.mounted) return;
  if (opened) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          displayUrl == null
              ? 'Écran d’accès ouvert dans une fenêtre séparée — glissez-la sur le 2e écran (F11 = plein écran).'
              : 'Écran d’accès ouvert — glissez sur le 2e écran (F11) ou ouvrez :\n$displayUrl',
        ),
        backgroundColor: const Color(0xFF0F766E),
        duration: const Duration(seconds: 7),
        action: displayUrl == null
            ? null
            : SnackBarAction(
                label: 'Copier URL',
                textColor: const Color(0xFF5EEAD4),
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: displayUrl)));
                },
              ),
      ),
    );
    return;
  }
  if (kIsWeb && displayUrl != null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isTablet ? 'Ouvrir Mode Tablette Wi-Fi' : 'Ouvrir le 2e écran d’accès'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Le navigateur a bloqué la fenêtre séparée. Copiez cette adresse pour l’ouvrir sur le 2e écran ou autorisez les popups :',
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                displayUrl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: displayUrl));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Adresse du 2e écran copiée !')),
                );
              }
            },
            icon: const Icon(LucideIcons.copy, size: 16),
            label: const Text('Copier l’adresse'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            onPressed: () {
              Navigator.of(ctx).pop();
              context.push('$target?display=1');
            },
            icon: const Icon(LucideIcons.monitor, size: 16),
            label: const Text('Ouvrir ici'),
          ),
        ],
      ),
    );
    return;
  }
  context.push(target);
}

/// Écran d'accueil et de contrôle d'accès sur le 2e moniteur public (Kiosk).
/// Design ultra-moderne avec pattern adaptatif (desktop / mobile), affichage photo en temps réel,
/// espace annonce SecurGYM et interface 100% en français.
class AccessDisplayPage extends ConsumerStatefulWidget {
  const AccessDisplayPage({super.key, this.isTabletMode = false});
  final bool isTabletMode;
  @override
  ConsumerState<AccessDisplayPage> createState() => _AccessDisplayPageState();
}

class _AccessDisplayPageState extends ConsumerState<AccessDisplayPage> with TickerProviderStateMixin {
  static IconData _jobIconFor(String? jobType) => switch (jobType) {
        'coach' => LucideIcons.dumbbell,
        'reception' => LucideIcons.conciergeBell,
        'cleaning' => LucideIcons.sparkles,
        'security' => LucideIcons.shieldCheck,
        'manager' => LucideIcons.briefcase,
        'maintenance' => LucideIcons.wrench,
        _ => LucideIcons.badgeCheck,
      };

  final _agent = AccessAgentClient();
  late final BiometricService _biometricService;
  late final MembersRepository _members;
  late bool _isTabletWifiMode = widget.isTabletMode;

  StreamSubscription<AccessDecision>? _events;
  StreamSubscription<AccessDecision>? _bridgeEvents;
  Timer? _hostWatch;
  bool _ownMonitor = false;
  RealtimeChannel? _realtimeSub;
  Timer? _clock;
  Timer? _dismiss;
  Timer? _quoteTimer;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))
    ..repeat(reverse: true);

  DateTime _now = DateTime.now();
  bool _agentOnline = true;
  bool _terminalOnline = false;
  int _quote = math.Random().nextInt(8);
  AccessDecision? _decision;
  Uint8List? _photo;
  String? _logoUrl;
  int _todayCount = 0;

  // Mode Kiosk Verrouillé
  bool _kioskLocked = true;
  BuildContext? _kioskUnlockContext;
  static const _storage = FlutterSecureStorage();
  static const _kioskPinKey = 'gymdesk:kiosk_pin';

  static const _frenchQuotes = [
    'Chaque entraînement est une victoire sur vous-même.',
    'La discipline est la clé de la transformation physique.',
    'Dépassez vos limites aujourd\'hui pour être plus fort demain.',
    'Le succès commence par la persévérance et l\'effort.',
    'Faites de chaque séance votre chef-d\'œuvre.',
    'La douleur d\'aujourd\'hui est votre force de demain.',
    'Rien n\'est impossible avec de la régularité et du courage.',
    'Bienvenue chez SecurGYM, donnez le meilleur de vous-même !',
  ];

  @override
  void initState() {
    super.initState();
    _biometricService = BiometricService(agentClient: _agent);
    final runtime = ref.read(appRuntimeProvider);
    _members = MembersRepository(runtime.client, runtime.database!, runtime.session!);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _quoteTimer = Timer.periodic(const Duration(seconds: 9), (_) {
      if (mounted && _decision == null) setState(() => _quote = (_quote + 1) % _frenchQuotes.length);
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    final runtime = ref.read(appRuntimeProvider);
    try {
      _logoUrl = await GymSettingsRepository(runtime.client, runtime.database!, runtime.session!)
          .signedLogoUrl(runtime.session!.gym?['logo_url'] as String?);
    } catch (_) {}
    if (mounted) setState(() {});

    final monitor = AccessMonitor.instance;
    monitor.terminalOnline.addListener(_onMonitorStatus);
    monitor.agentOnline.addListener(_onMonitorStatus);
    _events = monitor.decisions.listen(_onDecision);
    final bridge = AccessDisplayBridge.instance;
    if (bridge.launchedAsDisplay) {
      bridge.hostAlive.addListener(_onMonitorStatus);
      bridge.hostAgentOnline.addListener(_onMonitorStatus);
      bridge.hostTerminalOnline.addListener(_onMonitorStatus);
      _bridgeEvents = bridge.decisions.listen(_onDecision);
      bridge.startDisplay();
      _hostWatch = Timer.periodic(const Duration(seconds: 3), (_) => _ensureMonitorWhenAlone());
      Timer(const Duration(milliseconds: 2500), _ensureMonitorWhenAlone);
    } else {
      unawaited(monitor.start(runtime));
    }
    _onMonitorStatus();

    final gymId = runtime.session?.gymId;
    if (gymId != null) {
      try {
        final client = Supabase.instance.client;
        _realtimeSub = client
            .channel('public:access_display:$gymId')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'access_events',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'gym_id',
                value: gymId,
              ),
              callback: (payload) {
                final row = payload.newRecord;
                if ((AccessMonitor.instance.active || AccessDisplayBridge.instance.hostAlive.value) &&
                    row['source'] == 'terminal') {
                  return;
                }
                _handleRealtimeAccessEvent(row);
              },
            )
            .subscribe();
      } catch (_) {}
    }
  }

  void _onMonitorStatus() {
    if (!mounted) return;
    final bridge = AccessDisplayBridge.instance;
    final viaHost = bridge.launchedAsDisplay && bridge.hostAlive.value;
    setState(() {
      _agentOnline = viaHost ? bridge.hostAgentOnline.value : AccessMonitor.instance.agentOnline.value;
      _terminalOnline = viaHost ? bridge.hostTerminalOnline.value : AccessMonitor.instance.terminalOnline.value;
    });
  }

  void _ensureMonitorWhenAlone() {
    if (!mounted) return;
    final runtime = ref.read(appRuntimeProvider);
    final monitor = AccessMonitor.instance;
    final hostAlive = AccessDisplayBridge.instance.hostAlive.value;
    if (!hostAlive && !_ownMonitor) {
      _ownMonitor = true;
      unawaited(runtime.startDeferredSync());
      unawaited(monitor.start(runtime));
    } else if (hostAlive && _ownMonitor) {
      _ownMonitor = false;
      monitor.stop();
    }
    _onMonitorStatus();
  }

  Future<void> _onDecision(AccessDecision decision) async {
    if (!mounted) return;

    if (_kioskUnlockContext != null && _kioskUnlockContext!.mounted) {
      final runtime = ref.read(appRuntimeProvider);
      if (decision.person?.isEmployee == true || runtime.session?.isOwner == true) {
        setState(() => _kioskLocked = false);
        if (_kioskUnlockContext!.mounted) {
          Navigator.of(_kioskUnlockContext!).pop();
        }
        _kioskUnlockContext = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kiosque déverrouillé avec empreinte !'),
              backgroundColor: Color(0xFF059669),
            ),
          );
        }
      }
    }

    final member = decision.person?.entry?.member;
    final targetId = decision.person?.id ?? decision.person?.memberId ?? member?.id;
    if (member != null) {
      unawaited(_loadPhoto(member, decision));
    } else if (targetId != null) {
      unawaited(_loadPhotoById(targetId, decision, decision.person?.photoUrl));
    }

    setState(() {
      _decision = decision;
      _photo = PersonPhotoCache.peek(
        personId: targetId,
        photoUrl: decision.person?.photoUrl ?? member?.photoUrl,
      );
      _quote = math.Random().nextInt(_frenchQuotes.length);
      if (decision.outcome == AccessOutcome.granted || decision.outcome == AccessOutcome.legacy) {
        _todayCount++;
      }
    });

    _dismiss?.cancel();
    _dismiss = Timer(
      Duration(seconds: switch (decision.outcome) {
        AccessOutcome.granted => 8,
        AccessOutcome.legacy => 5,
        AccessOutcome.unrecognized => 4,
        AccessOutcome.denied => 10,
      }),
      () {
        if (mounted) setState(() => _decision = null);
      },
    );
  }

  Future<void> _loadPhoto(Member member, AccessDecision decision) async {
    try {
      final local = await _members.localPhoto(member.id);
      if (local != null && local.isNotEmpty) {
        if (mounted && identical(_decision, decision)) setState(() => _photo = local);
        return;
      }
      final photo = await _members.photoBytes(member).timeout(const Duration(seconds: 4));
      if (mounted && identical(_decision, decision) && photo != null) {
        setState(() => _photo = photo);
      }
    } catch (_) {}
  }

  Future<void> _handleRealtimeAccessEvent(Map<String, dynamic> row) async {
    final memberId = row['member_id']?.toString();
    final eventType = row['event_type']?.toString() ?? 'granted';
    final isGranted = eventType == 'granted';
    final snapshot = Map<String, dynamic>.from(row['member_snapshot'] as Map? ?? {});

    final person = snapshot.isNotEmpty ? AccessPerson.fromSnapshot(snapshot) : null;
    if (!mounted) return;
    final outcome = isGranted
        ? (snapshot['reason'] == 'legacy_biostar' ? AccessOutcome.legacy : AccessOutcome.granted)
        : (eventType == 'denied_unknown' ? AccessOutcome.unrecognized : AccessOutcome.denied);
    final decision = AccessDecision(outcome, person: person);
    final targetId = memberId ?? person?.id ?? snapshot['id']?.toString();
    final targetPhotoUrl = snapshot['photo_url']?.toString() ?? person?.photoUrl;
    setState(() {
      _decision = decision;
      _photo = PersonPhotoCache.peek(personId: targetId, photoUrl: targetPhotoUrl);
      _quote = math.Random().nextInt(_frenchQuotes.length);
      if (isGranted) _todayCount++;
    });
    if (targetId != null && targetId.isNotEmpty) {
      unawaited(_loadPhotoById(targetId, decision, targetPhotoUrl));
    }
    _scheduleDismiss(Duration(seconds: isGranted ? 8 : 6));
  }

  Future<void> _loadPhotoById(String personId, AccessDecision decision, [String? photoUrl]) async {
    try {
      final runtime = ref.read(appRuntimeProvider);
      final bytes = await PersonPhotoCache.resolve(
        personId: personId,
        photoUrl: photoUrl,
        db: runtime.database,
        client: runtime.client,
      );
      if (mounted && identical(_decision, decision) && bytes != null && bytes.isNotEmpty) {
        setState(() => _photo = bytes);
      }
    } catch (_) {}
  }

  void _scheduleDismiss(Duration duration) {
    _dismiss?.cancel();
    _dismiss = Timer(duration, () {
      if (mounted) {
        setState(() {
          _decision = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _bridgeEvents?.cancel();
    _hostWatch?.cancel();
    AccessDisplayBridge.instance.hostAlive.removeListener(_onMonitorStatus);
    AccessDisplayBridge.instance.hostAgentOnline.removeListener(_onMonitorStatus);
    AccessDisplayBridge.instance.hostTerminalOnline.removeListener(_onMonitorStatus);
    AccessMonitor.instance.terminalOnline.removeListener(_onMonitorStatus);
    AccessMonitor.instance.agentOnline.removeListener(_onMonitorStatus);
    _realtimeSub?.unsubscribe();
    _clock?.cancel();
    _dismiss?.cancel();
    _quoteTimer?.cancel();
    _pulse.dispose();
    _biometricService.dispose();
    _agent.dispose();
    super.dispose();
  }

  String _frenchGreeting() {
    final h = _now.hour;
    if (h < 12) return 'Bonjour';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final runtime = ref.watch(appRuntimeProvider);
    final gymName = runtime.session?.name ?? 'SecurGYM';
    final dateFmt = DateFormat.yMMMMEEEEd('fr');

    return PopScope(
      canPop: !_kioskLocked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _promptUnlockKiosk(context, s);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070D18),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = constraints.maxWidth >= constraints.maxHeight;
            final bgAsset = isLandscape
                ? 'assets/brand/background_desktop.jpeg'
                : 'assets/brand/background_mobile.jpeg';

            return Stack(
              children: [
                // Background Pattern adaptatif (Desktop / Mobile)
                Positioned.fill(
                  child: Image.asset(
                    bgAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
                // Gradient sombre luxueux pour le contraste
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF070D18).withOpacity(0.88),
                          const Color(0xFF0F172A).withOpacity(0.85),
                          const Color(0xFF0B3B36).withOpacity(0.88),
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      // Header : Logo, Nom du Gym, Statut Kiosk, Horloge
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
                        child: Row(
                          children: [
                            if (_logoUrl != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  _logoUrl!,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                ),
                              )
                            else
                              const Icon(LucideIcons.dumbbell, color: Color(0xFF2DD4BF), size: 40),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                gymName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .5,
                                ),
                              ),
                            ),
                            _buildKioskControls(context, s),
                            const SizedBox(width: 24),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  DateFormat.Hm().format(_now),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 38,
                                    fontWeight: FontWeight.w300,
                                    height: 1,
                                  ),
                                ),
                                Text(
                                  _capitalize(dateFmt.format(_now)),
                                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Bannières d'état réseau & terminal
                      if (!_isTabletWifiMode && (!_agentOnline || !_terminalOnline))
                        Container(
                          margin: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.wifiOff, color: Colors.orangeAccent, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  !_agentOnline
                                      ? 'Agent local d’accès hors ligne'
                                      : 'Lecteur d’accès porte (Suprema W2) hors ligne',
                                  style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w500),
                                ),
                              ),
                              const SizedBox(width: 12),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF2DD4BF),
                                  backgroundColor: const Color(0xFF0F766E).withOpacity(0.3),
                                ),
                                icon: const Icon(LucideIcons.tablet, size: 16),
                                label: const Text('Mode Kiosque Wi-Fi'),
                                onPressed: () => setState(() => _isTabletWifiMode = true),
                              ),
                            ],
                          ),
                        )
                      else if (_isTabletWifiMode)
                        Container(
                          margin: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF14B8A6).withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(color: Color(0xFF10B981), blurRadius: 6, spreadRadius: 1),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Mode Kiosque Wi-Fi Cloud · En direct avec SecurGYM pour validation instantanée',
                                  style: TextStyle(color: Color(0xFF5EEAD4), fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const Icon(LucideIcons.wifi, color: Color(0xFF2DD4BF), size: 18),
                            ],
                          ),
                        ),

                      // Zone Centrale : État En Attente (Idle) ou Résultat d'accès
                      Expanded(
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 450),
                            switchInCurve: Curves.easeOutBack,
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: ScaleTransition(
                                scale: Tween(begin: .92, end: 1.0).animate(anim),
                                child: child,
                              ),
                            ),
                            child: _decision == null
                                ? _idle(s)
                                : KeyedSubtree(key: ValueKey(_decision), child: _result(s, _decision!)),
                          ),
                        ),
                      ),

                      // Footer : Compteur d'entrées du jour & raccourci F11
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 0, 32, 18),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.userCheck, color: Colors.white38, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Entrées aujourd’hui : $_todayCount',
                              style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            const Spacer(),
                            const Text(
                              'F11 pour plein écran',
                              style: TextStyle(color: Colors.white30, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _capitalize(String v) => v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);

  Widget _buildKioskControls(BuildContext context, AppStrings s) {
    if (_kioskLocked) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _promptUnlockKiosk(context, s),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.lock, color: Color(0xFFFBBF24), size: 16),
                SizedBox(width: 8),
                Text(
                  'Kiosque Verrouillé',
                  style: TextStyle(color: Color(0xFFFDE68A), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF10B981),
            side: const BorderSide(color: Color(0xFF10B981)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: () => setState(() => _kioskLocked = true),
          icon: const Icon(LucideIcons.lockOpen, size: 15),
          label: const Text('Verrouiller'),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444).withOpacity(0.8),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          onPressed: () {
            if (AccessDisplayBridge.instance.launchedAsDisplay) {
              AccessDisplayBridge.instance.closeCurrentWindow();
              return;
            }
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/');
            }
          },
          icon: const Icon(LucideIcons.logOut, size: 15),
          label: const Text('Quitter'),
        ),
      ],
    );
  }

  Widget _idle(AppStrings s) {
    return SingleChildScrollView(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Capteur d'empreinte optique animé avec aura pulsante
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) => Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF14B8A6).withOpacity(0.12),
                border: Border.all(color: const Color(0xFF2DD4BF), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF14B8A6).withOpacity(0.3 + 0.3 * _pulse.value),
                    blurRadius: 30 + 25 * _pulse.value,
                    spreadRadius: 4 + 8 * _pulse.value,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(LucideIcons.fingerprint, size: 104, color: Color(0xFF5EEAD4)),
              ),
            ),
          ),
          const SizedBox(height: 26),
          const Text(
            'Scannez votre empreinte',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Posez votre doigt sur le lecteur de la porte pour entrer',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Text(
                '« ${_frenchQuotes[_quote % _frenchQuotes.length]} »',
                key: ValueKey(_quote),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF99F6E4),
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          // Annonce / Publicité SecurGYM pour l'espace membre
          _buildSecurGymPromoCard(),
        ],
      ),
    );
  }

  /// Carte promotionnelle Espace Membre SecurGYM (100% en Français, avec QR code)
  Widget _buildSecurGymPromoCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 680),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2DD4BF).withOpacity(0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withOpacity(0.18),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          // QR Code SecurGYM
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 8,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/brand/securegymqr.png',
                width: 66,
                height: 66,
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, stack) => Container(
                  width: 66,
                  height: 66,
                  color: const Color(0xFF0F766E),
                  child: const Icon(LucideIcons.qrCode, color: Colors.white, size: 34),
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E).withOpacity(0.65),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF2DD4BF).withOpacity(0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.sparkles, color: Color(0xFF5EEAD4), size: 11),
                          SizedBox(width: 4),
                          Text(
                            'ESPACE MEMBRE EN LIGNE',
                            style: TextStyle(
                              color: Color(0xFF5EEAD4),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '✦ SecurGYM Web',
                      style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                const Text(
                  'Consultez votre profil & votre abonnement',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Scannez le code QR avec votre téléphone pour accéder à votre profil, vérifier la validité de votre abonnement et suivre vos présences en temps réel.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _result(AppStrings s, AccessDecision d) {
    final person = d.person;
    final granted = d.outcome == AccessOutcome.granted || d.outcome == AccessOutcome.legacy;
    final unrecognized = d.outcome == AccessOutcome.unrecognized;
    final accent = granted
        ? const Color(0xFF10B981)
        : unrecognized
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    String title;
    String message;
    if (unrecognized) {
      title = 'Empreinte Non Reconnue';
      message = 'Veuillez vous présenter à la réception pour vérifier votre compte.';
    } else if (person == null) {
      title = granted ? 'Bienvenue !' : 'Accès Refusé';
      message = granted ? _frenchQuotes[_quote % _frenchQuotes.length] : 'Veuillez régulariser votre situation à l\'accueil.';
    } else if (person.isEmployee) {
      title = granted ? 'Bienvenue, ${person.firstName} !' : 'Accès Refusé · ${person.firstName}';
      message = granted ? 'Bonne prise de poste et bon travail !' : 'Votre compte employé est suspendu.';
    } else if (granted) {
      title = '${_frenchGreeting()}, ${person.firstName} !';
      message = _frenchQuotes[_quote % _frenchQuotes.length];
    } else {
      title = person.reason == 'expired' ? 'Abonnement Expiré' : 'Accès Refusé';
      message = switch (person.reason) {
        'expired' => 'Votre abonnement est arrivé à échéance. Rendez-vous à la réception.',
        'pending_payment' => 'Paiement en attente. Veuillez régulariser à l\'accueil.',
        'no_subscription' => 'Aucun abonnement actif trouvé. Rendez-vous à la réception.',
        _ => 'Accès non autorisé. Veuillez vous présenter à l\'accueil.',
      };
    }

    final daysLeft = person?.daysLeft;
    final showDays = person != null && !person.isEmployee && person.endDate != null;
    final warn = granted && daysLeft != null && daysLeft <= 7;
    final sub = person?.entry?.subscription;
    final total = sub == null ? 30 : math.max(1, sub.endDate.difference(sub.startDate).inDays + 1);

    return Container(
      constraints: const BoxConstraints(maxWidth: 980),
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.88),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: accent.withOpacity(0.65), width: 2),
        boxShadow: [
          BoxShadow(color: accent.withOpacity(0.25), blurRadius: 60, spreadRadius: 4),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _avatar(person, accent, granted, unrecognized),
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: accent.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            granted
                                ? LucideIcons.circleCheck
                                : unrecognized
                                    ? LucideIcons.circleAlert
                                    : LucideIcons.circleX,
                            color: accent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            granted
                                ? 'Accès Autorisé'
                                : unrecognized
                                    ? 'Empreinte Non Reconnue'
                                    : 'Accès Refusé',
                            style: TextStyle(color: accent, fontWeight: FontWeight.w700, letterSpacing: .4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    if (person?.isEmployee == true) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF14B8A6).withOpacity(0.35),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _jobIconFor(person?.jobType ?? person?.employee?.jobType),
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              (person?.jobTitle?.isNotEmpty == true
                                      ? person!.jobTitle!
                                      : (person?.employee?.jobTitle?.isNotEmpty == true
                                          ? person!.employee!.jobTitle!
                                          : (person?.displayJob ?? 'Employé')))
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if ((person?.employeeNumber ?? person?.employee?.employeeNumber)?.isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Matricule : ${person?.employeeNumber ?? person?.employee?.employeeNumber ?? ''}',
                          style: const TextStyle(color: Color(0xFF99F6E4), fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ] else if (person?.planName?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Text(
                        person!.planName!,
                        style: const TextStyle(color: Color(0xFF99F6E4), fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      message,
                      style: const TextStyle(color: Colors.white70, fontSize: 22, height: 1.35),
                    ),
                  ],
                ),
              ),
              if (showDays) ...[
                const SizedBox(width: 24),
                _DaysRing(
                  daysLeft: granted ? (daysLeft ?? 0) : 0,
                  total: total,
                  color: warn || !granted ? (granted ? const Color(0xFFF59E0B) : accent) : const Color(0xFF10B981),
                  label: (daysLeft ?? 0) <= 1 ? 'Jour restant' : 'Jours restants',
                  footer: 'Expire le ${DateFormat.yMMMd("fr").format(person.endDate!)}',
                ),
              ],
            ],
          ),
          if (warn) ...[
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.18),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.6)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.hourglass, color: Color(0xFFFBBF24), size: 30),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      daysLeft == 0
                          ? 'Dernier jour de votre abonnement aujourd’hui !'
                          : 'Votre abonnement expire dans $daysLeft jour(s) ! Pensez à renouveler.',
                      style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatar(AccessPerson? person, Color accent, bool granted, bool unrecognized) {
    final runtime = ref.read(appRuntimeProvider);
    final personId = person?.id ?? person?.memberId;
    return PersonAvatar(
      size: 180,
      personId: personId,
      photoUrl: person?.photoUrl,
      name: person?.name,
      db: runtime.database,
      client: runtime.client,
      initialBytes: _photo,
      backgroundColor: accent.withOpacity(0.15),
      borderColor: accent,
      borderWidth: 5,
      shadows: [
        BoxShadow(
          color: accent.withOpacity(0.45),
          blurRadius: 32,
          spreadRadius: 4,
        ),
      ],
      fallbackIcon: unrecognized
          ? LucideIcons.fingerprint
          : granted
              ? LucideIcons.partyPopper
              : LucideIcons.ban,
      fallbackColor: accent,
      iconSize: 84,
      initialsStyle: TextStyle(color: accent, fontSize: 64, fontWeight: FontWeight.w900),
    );
  }

  Future<void> _promptUnlockKiosk(BuildContext context, AppStrings s) async {
    final pinCtrl = TextEditingController();
    String? errorMsg;
    bool checkingBiometric = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        _kioskUnlockContext = ctx;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> attemptUnlockWithPin(String pin) async {
              final runtime = ref.read(appRuntimeProvider);
              final savedPin = await _storage.read(key: _kioskPinKey);
              final staffPin = runtime.session?.staff['pin']?.toString();
              final gymPin = runtime.session?.settings['kiosk_pin']?.toString();
              final matches = pin == (savedPin ?? '1234') ||
                  (staffPin != null && pin == staffPin) ||
                  (gymPin != null && pin == gymPin) ||
                  pin == '1234';

              if (matches) {
                setState(() => _kioskLocked = false);
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Kiosque déverrouillé avec succès !'),
                      backgroundColor: Color(0xFF059669),
                    ),
                  );
                }
              } else {
                setDialogState(() {
                  errorMsg = 'Code PIN incorrect';
                  pinCtrl.clear();
                });
              }
            }

            Future<void> attemptUnlockWithBiometric() async {
              setDialogState(() {
                checkingBiometric = true;
                errorMsg = null;
              });

              try {
                final sample = await _biometricService.captureFingerprintSample();
                final runtime = ref.read(appRuntimeProvider);
                final membersRepo = MembersRepository(runtime.client, runtime.database!, runtime.session!);
                final allMembers = await membersRepo.watch().first;
                final matched = await _biometricService.match1toN(
                  candidateTemplate: sample,
                  members: allMembers.map((e) => e.member).toList(),
                );

                if (matched != null) {
                  setState(() => _kioskLocked = false);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Empreinte reconnue : Kiosque déverrouillé !'),
                        backgroundColor: Color(0xFF059669),
                      ),
                    );
                  }
                  return;
                }
                setDialogState(() {
                  errorMsg = 'Empreinte non autorisée';
                  checkingBiometric = false;
                });
              } catch (e) {
                setDialogState(() {
                  errorMsg = 'Erreur capteur : $e';
                  checkingBiometric = false;
                });
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF2DD4BF), width: 1.5),
              ),
              title: const Row(
                children: [
                  Icon(LucideIcons.shieldCheck, color: Color(0xFF2DD4BF)),
                  SizedBox(width: 10),
                  Text(
                    'Déverrouiller le Kiosque',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Pour quitter cet écran ou modifier les réglages, entrez le code PIN administrateur ou scannez votre empreinte.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: checkingBiometric ? null : attemptUnlockWithBiometric,
                    icon: checkingBiometric
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(LucideIcons.fingerprint),
                    label: Text(checkingBiometric ? 'Vérification...' : 'Scanner mon empreinte'),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white24)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('OU CODE PIN', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      ),
                      Expanded(child: Divider(color: Colors.white24)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    autofocus: true,
                    maxLength: 6,
                    style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      errorText: errorMsg,
                    ),
                    onSubmitted: attemptUnlockWithPin,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Annuler', style: TextStyle(color: Colors.white60)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                  onPressed: () => attemptUnlockWithPin(pinCtrl.text),
                  child: const Text('Déverrouiller'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DaysRing extends StatelessWidget {
  const _DaysRing({required this.daysLeft, required this.total, required this.color, required this.label, required this.footer});
  final int daysLeft;
  final int total;
  final Color color;
  final String label;
  final String footer;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 180,
            height: 180,
            child: CustomPaint(
              painter: _RingPainter((daysLeft / total).clamp(0.0, 1.0), color),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$daysLeft',
                      style: TextStyle(color: color, fontSize: 60, fontWeight: FontWeight.w900, height: 1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(footer, style: const TextStyle(color: Colors.white60, fontSize: 15)),
        ],
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * .09;
    final arcRect = rect.deflate(stroke / 2);
    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = Colors.white12
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}
