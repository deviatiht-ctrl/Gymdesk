import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gymdesk_biometrics/gymdesk_biometrics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/access_control/terminal_access_service.dart';
import '../../../core/biometrics/access_agent_client.dart';
import '../../../core/biometrics/biometric_models.dart';
import '../../../core/biometrics/biometric_service.dart';
import '../../../core/sync/sync_models.dart';
import '../../../l10n/app_strings.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../members/data/members_repository.dart';
import '../../members/domain/member.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import 'access_display_page.dart';

enum AccessStatus { none, granted, deniedExpired, deniedNoSubscription, deniedUnrecognized }

class DoorAccessPage extends ConsumerStatefulWidget {
  const DoorAccessPage({super.key});

  @override
  ConsumerState<DoorAccessPage> createState() => _DoorAccessPageState();
}

class _DoorAccessPageState extends ConsumerState<DoorAccessPage> {
  late final BiometricService _biometricService;
  late final AttendanceRepository _attendanceRepo;
  late final MembersRepository _membersRepo;
  final _agent = AccessAgentClient();
  late final TerminalAccessService _terminalService;
  TerminalAccessConfig _cfg = const TerminalAccessConfig();

  StreamSubscription<BiometricEvent>? _biometricSub;
  StreamSubscription<Map<String, dynamic>>? _terminalSub;
  RealtimeChannel? _realtimeSub;
  Timer? _dismissTimer;

  bool _processing = false;
  bool _terminalOnline = false;
  bool _agentOnline = true;
  AccessStatus _status = AccessStatus.none;
  Member? _matchedMember;
  int? _daysLeft;

  final _searchController = TextEditingController();
  List<MemberListEntry> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _biometricService = BiometricService();
    final runtime = ref.read(appRuntimeProvider);
    _attendanceRepo = AttendanceRepository(runtime.database!, runtime.session!);
    _membersRepo = MembersRepository(runtime.client, runtime.database!, runtime.session!);
    _terminalService = TerminalAccessService(runtime.client, runtime.database!, runtime.session!, agent: _agent);

    _startBiometricListener();
    _biometricService.checkSensorConnection();
    _initTerminal();
  }

  Future<void> _initTerminal() async {
    final runtime = ref.read(appRuntimeProvider);
    try {
      _cfg = await TerminalAccessService.loadConfig(runtime.client, runtime.session!);
      _terminalOnline = await _agent.watchTerminal(terminalIp: _cfg.terminalIp);
      _terminalSub = _agent.terminalEvents().listen(_onTerminalEvent);

      final gymId = runtime.session?.gymId;
      if (gymId != null) {
        final client = Supabase.instance.client;
        _realtimeSub = client
            .channel('public:door_access:$gymId')
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
                _handleRealtimeAccessEvent(row);
              },
            )
            .subscribe();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _onTerminalEvent(Map<String, dynamic> event) async {
    final type = event['type'];
    if (type == 'agent_status') {
      final online = event['online'] == true;
      final term = event['terminal_watch'] == true;
      if (online != _agentOnline || term != _terminalOnline) {
        if (mounted) {
          setState(() {
            _agentOnline = online;
            _terminalOnline = term;
          });
        }
      }
      return;
    }
    if (type == 'terminal_watch') {
      if (mounted) setState(() => _terminalOnline = event['online'] == true);
      return;
    }

    final decision = await _terminalService.handleTerminalEvent(event, _cfg);
    if (decision == null || !mounted) return;

    final member = decision.person?.entry?.member;
    if (member != null) {
      await _evaluateMemberAccess(member);
    } else if (decision.outcome == AccessOutcome.legacy) {
      if (mounted) {
        setState(() {
          _status = AccessStatus.granted;
          _matchedMember = null;
          _daysLeft = null;
          _processing = false;
        });
        _scheduleDismiss(const Duration(seconds: 5));
      }
    } else if (decision.outcome == AccessOutcome.unrecognized) {
      if (mounted) {
        setState(() {
          _status = AccessStatus.deniedUnrecognized;
          _matchedMember = null;
          _daysLeft = null;
          _processing = false;
        });
        _scheduleDismiss(const Duration(seconds: 4));
      }
    }
  }

  Future<void> _handleRealtimeAccessEvent(Map<String, dynamic> row) async {
    final memberId = row['member_id']?.toString();
    if (memberId == null) return;
    try {
      final entries = await _membersRepo.watch().first;
      final entry = entries.where((e) => e.member.id == memberId).firstOrNull;
      if (entry != null && mounted) {
        await _evaluateMemberAccess(entry.member);
      }
    } catch (_) {}
  }

  void _startBiometricListener() {
    _biometricSub = _biometricService.events.listen((event) {
      if (event.type == 'fingerprint_captured' && !_processing) {
        final template = event.raw['template'] as String?;
        if (template != null) {
          _onFingerprintReceived(template);
        }
      }
    });
  }

  Future<void> _onFingerprintReceived(String probeTemplate) async {
    setState(() {
      _processing = true;
      _dismissTimer?.cancel();
    });

    try {
      final runtime = ref.read(appRuntimeProvider);
      final db = runtime.database;
      if (db == null) throw Exception('Database offline');

      // 1:N Identification dans la base locale via BiometricService
      final rows = await db.watchRecords(SyncEntity.members, limit: 50000).first;
      final members = <Member>[];
      for (final r in rows) {
        try {
          members.add(Member(Map<String, dynamic>.from(jsonDecode(r.payload) as Map)));
        } catch (_) {}
      }
      final matched = await _biometricService.match1toN(
        candidateTemplate: probeTemplate,
        members: members,
      );

      if (matched == null) {
        setState(() {
          _status = AccessStatus.deniedUnrecognized;
          _matchedMember = null;
          _processing = false;
        });
        _scheduleDismiss(const Duration(seconds: 4));
        return;
      }

      // Vérification du statut d'abonnement
      await _evaluateMemberAccess(matched);
    } catch (_) {
      setState(() {
        _status = AccessStatus.deniedUnrecognized;
        _processing = false;
      });
      _scheduleDismiss(const Duration(seconds: 4));
    }
  }

  Future<void> _evaluateMemberAccess(Member member) async {
    final now = DateTime.now();

    // Récupérer les abonnements de ce membre
    final entries = await _membersRepo.watch(query: member.memberNumber).first;
    final entry = entries.where((e) => e.member.id == member.id).firstOrNull;

    final validity = entry?.validity ?? const MemberValidity(valid: false, reason: 'no_subscription');
    final isAccessOk = validity.valid;
    final daysRemaining = validity.daysLeft ?? -1;

    if (isAccessOk) {
      setState(() {
        _status = AccessStatus.granted;
        _matchedMember = member;
        _daysLeft = daysRemaining;
        _processing = false;
      });

      // 1. Enregistre la présence biométrique
      try {
        await _attendanceRepo.verifyFingerprintAndGrant(
          member: member,
          fingerprintMatched: true,
          scannedAt: now,
          offline: false,
          suspectClock: false,
        );
      } catch (_) {}

      // 2. Envoie l'impulsion relais à la porte
      unawaited(_triggerDoorRelay());

      _scheduleDismiss(const Duration(seconds: 6));
    } else {
      setState(() {
        _status = validity.reason == 'expired'
            ? AccessStatus.deniedExpired
            : AccessStatus.deniedNoSubscription;
        _matchedMember = member;
        _daysLeft = daysRemaining;
        _processing = false;
      });
      _scheduleDismiss(const Duration(seconds: 7));
    }
  }

  Future<void> _triggerDoorRelay() async {
    try {
      final runtime = ref.read(appRuntimeProvider);
      final gymId = runtime.session?.gymId;
      if (gymId == null) return;

      final client = Supabase.instance.client;
      Map<String, dynamic> cfg = {};
      try {
        final gym = await client.from('gyms').select('settings').eq('id', gymId).maybeSingle();
        if (gym != null && gym['settings'] is Map) {
          final settings = Map<String, dynamic>.from(gym['settings'] as Map);
          if (settings['biometric_config'] is Map) {
            cfg = Map<String, dynamic>.from(settings['biometric_config'] as Map);
          }
        }
      } catch (_) {}
      if (cfg.isEmpty && runtime.session != null) {
        final localSettings = runtime.session!.settings;
        if (localSettings['biometric_config'] is Map) {
          cfg = Map<String, dynamic>.from(localSettings['biometric_config'] as Map);
        }
      }

      final relayMode = cfg['relay_mode'] as String? ?? 'usb_serial_relay';
      final port = cfg['relay_port'] as String? ?? 'COM3';
      final url = cfg['relay_url'] as String? ?? 'http://192.168.1.50/relay/0?turn=on';
      final terminalIp = cfg['terminal_ip'] as String? ?? '192.168.1.41';
      final dur = (cfg['pulse_duration_seconds'] as num?)?.toInt() ?? 3;

      if (relayMode == 'terminal_bew2') {
        await AccessAgentClient().pulseTerminalRelay(terminalIp: terminalIp);
        return;
      }

      DoorController controller;
      if (relayMode == 'usb_serial_relay') {
        controller = UsbSerialRelayDoorController(port: port);
      } else if (relayMode == 'http_relay') {
        controller = HttpRelayDoorController(endpointUrl: url);
      } else {
        controller = const NoopDoorController();
      }

      await controller.openDoor(pulseDuration: Duration(seconds: dur));
    } catch (_) {}
  }

  Future<void> _openDoorManually() async {
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('open_door_manual')),
        content: Text(s.locale.languageCode == 'fr'
            ? 'Voulez-vous envoyer une impulsion manuelle pour déverrouiller la porte ?'
            : 'Èske w vle louvri pòt la manyèlman kounye a ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.text('open_door_manual')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _triggerDoorRelay();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.text('door_pulse_sent')), backgroundColor: const Color(0xFF059669)),
        );
      }
    }
  }

  Future<void> _lockDoorManually() async {
    final s = AppStrings.of(context);
    final isFr = s.locale.languageCode == 'fr';
    try {
      final runtime = ref.read(appRuntimeProvider);
      final gymId = runtime.session?.gymId;
      if (gymId == null) return;
      final client = Supabase.instance.client;
      Map<String, dynamic> cfg = {};
      try {
        final gym = await client.from('gyms').select('settings').eq('id', gymId).maybeSingle();
        if (gym != null && gym['settings'] is Map) {
          final settings = Map<String, dynamic>.from(gym['settings'] as Map);
          if (settings['biometric_config'] is Map) {
            cfg = Map<String, dynamic>.from(settings['biometric_config'] as Map);
          }
        }
      } catch (_) {}
      if (cfg.isEmpty && runtime.session != null) {
        final localSettings = runtime.session!.settings;
        if (localSettings['biometric_config'] is Map) {
          cfg = Map<String, dynamic>.from(localSettings['biometric_config'] as Map);
        }
      }
      final terminalIp = cfg['terminal_ip'] as String? ?? '192.168.1.41';
      final ok = await AccessAgentClient().releaseTerminalDoor(terminalIp: terminalIp);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? (isFr ? 'Porte verrouillée.' : 'Pòt la fèmen kounye a.')
              : (isFr ? 'Échec du verrouillage de la porte.' : 'Pòt la pa fèmen.')),
          backgroundColor: ok ? const Color(0xFF059669) : Colors.red,
        ));
      }
    } catch (_) {}
  }

  void _scheduleDismiss(Duration duration) {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(duration, () {
      if (mounted) {
        setState(() {
          _status = AccessStatus.none;
          _matchedMember = null;
        });
      }
    });
  }

  Future<void> _searchMembers(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    try {
      final list = await _membersRepo.watch(query: query.trim()).first;
      if (mounted) {
        setState(() {
          _searchResults = list.take(8).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _biometricSub?.cancel();
    _terminalSub?.cancel();
    _realtimeSub?.unsubscribe();
    _dismissTimer?.cancel();
    _biometricService.dispose();
    _agent.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isFr = s.locale.languageCode == 'fr';
    final isEn = s.locale.languageCode == 'en';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        title: Text(s.text('door_access_kiosk')),
        actions: [
          IconButton(
            tooltip: s.text('open_access_display'),
            icon: const Icon(LucideIcons.monitor),
            onPressed: () => openAccessDisplayWindow(context),
          ),
          IconButton(
            tooltip: s.text('open_door_manual'),
            icon: const Icon(LucideIcons.doorOpen),
            onPressed: _openDoorManually,
          ),
          IconButton(
            tooltip: s.locale.languageCode == 'fr' ? 'Fermer la porte' : 'Fèmen pòt la',
            icon: const Icon(LucideIcons.doorClosed),
            onPressed: _lockDoorManually,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Bandeau d'état dynamique : Tèminal Pòt + Lektè USB
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              color: const Color(0xFF1E293B),
              child: Row(
                children: [
                  Icon(
                    _terminalOnline ? LucideIcons.shieldCheck : LucideIcons.circleAlert,
                    color: _terminalOnline ? const Color(0xFF10B981) : Colors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _terminalOnline
                          ? (isFr
                              ? 'Terminal de porte (${_cfg.terminalIp}) : Connecté & Prêt'
                              : 'Tèminal Pòt (${_cfg.terminalIp}) : Konekte & Pare')
                          : (isFr
                              ? 'Terminal de porte (${_cfg.terminalIp.isEmpty ? "192.168.1.41" : _cfg.terminalIp}) : Non connecté (vérifiez le réseau)'
                              : 'Tèminal Pòt (${_cfg.terminalIp.isEmpty ? "192.168.1.41" : _cfg.terminalIp}) : Pa konekte (verifye rezo a)'),
                      style: TextStyle(
                        color: _terminalOnline ? Colors.white70 : Colors.amber.shade200,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ValueListenableBuilder<BiometricSensorState>(
                    valueListenable: _biometricService.state,
                    builder: (context, sensorState, _) {
                      final usbReady = sensorState == BiometricSensorState.ready;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: usbReady ? const Color(0xFF10B981).withAlpha(40) : Colors.white.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: usbReady ? const Color(0xFF10B981) : Colors.white24,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.usb,
                              size: 13,
                              color: usbReady ? const Color(0xFF34D399) : Colors.white38,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              usbReady
                                  ? (isFr ? 'USB : Prêt' : 'USB : Pare')
                                  : (isFr ? 'USB : Débranché' : 'USB : Deploge'),
                              style: TextStyle(
                                fontSize: 11,
                                color: usbReady ? const Color(0xFF34D399) : Colors.white38,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: isFr ? 'Tester la connexion' : 'Teste koneksyon an',
                    icon: const Icon(LucideIcons.refreshCw, size: 16, color: Colors.white70),
                    onPressed: () async {
                      final termOk = await _agent.watchTerminal(terminalIp: _cfg.terminalIp);
                      await _biometricService.checkSensorConnection();
                      if (mounted) setState(() => _terminalOnline = termOk);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 2),
                            content: Text(
                              termOk
                                  ? (isFr ? 'Terminal connecté avec succès' : 'Tèminal konekte avèk siksè')
                                  : (isFr ? 'Échec de connexion au terminal (${_cfg.terminalIp})' : 'Tèminal la pa reponn nan ${_cfg.terminalIp}'),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/settings/biometrics'),
                    icon: const Icon(LucideIcons.settings, size: 16, color: Colors.white70),
                    label: Text(s.text('settings'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_status == AccessStatus.none) ...[
                          GestureDetector(
                            onTap: _processing
                                ? null
                                : () async {
                                    if (_biometricService.readerAvailable) {
                                      try {
                                        final sample = await _biometricService.captureFingerprintSample();
                                        await _onFingerprintReceived(sample);
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(e.toString()),
                                              backgroundColor: Colors.red.shade700,
                                            ),
                                          );
                                        }
                                      }
                                    } else {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            duration: const Duration(seconds: 3),
                                            content: Text(
                                              isFr
                                                  ? 'Posez directement votre doigt sur le terminal de porte (${_cfg.terminalIp})'
                                                  : 'Mete dwèt ou dirèkteman sou tèminal pòt la (${_cfg.terminalIp})',
                                            ),
                                            backgroundColor: const Color(0xFF0F766E),
                                          ),
                                        );
                                      }
                                    }
                                  },
                            child: Container(
                              width: 170,
                              height: 170,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF0F766E).withOpacity(0.2),
                                border: Border.all(color: const Color(0xFF14B8A6), width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF14B8A6).withOpacity(0.3),
                                    blurRadius: 30,
                                    spreadRadius: 8,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: _processing
                                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                                    : const Icon(LucideIcons.fingerprint, size: 84, color: Color(0xFF2DD4BF)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            isFr
                                ? 'Posez votre doigt sur le terminal de porte'
                                : 'Poze dwèt ou sou tèminal pòt la',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _terminalOnline
                                ? (isFr
                                    ? 'Terminal ${_cfg.terminalIp} actif · Détection automatique'
                                    : 'Tèminal ${_cfg.terminalIp} aktif · Deteksyon otomatik')
                                : (isFr
                                    ? 'Terminal non connecté · Vérifiez l’IP dans les paramètres'
                                    : 'Tèminal pa konekte · Verifye adrès IP a nan Paramèt'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _terminalOnline ? const Color(0xFF2DD4BF) : Colors.amber.shade200,
                              fontSize: 14,
                            ),
                          ),
                        ] else ...[
                          _buildAccessResultCard(s, isFr, isEn),
                        ],

                        const SizedBox(height: 48),

                        // Section Recherche Secours (Staff Fallback)
                        ExpansionTile(
                          iconColor: Colors.white70,
                          collapsedIconColor: Colors.white54,
                          title: Text(
                            s.text('manual_search_or_pin'),
                            style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          leading: const Icon(LucideIcons.search, color: Colors.white70, size: 20),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _searchController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: isFr ? 'Nom, prénom ou téléphone...' : 'Non, prenon oswa telefòn...',
                                      hintStyle: const TextStyle(color: Colors.white38),
                                      prefixIcon: const Icon(LucideIcons.search, color: Colors.white54),
                                      filled: true,
                                      fillColor: const Color(0xFF1E293B),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                    ),
                                    onChanged: _searchMembers,
                                  ),
                                  if (_searchResults.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      constraints: const BoxConstraints(maxHeight: 180),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: ListView.separated(
                                        shrinkWrap: true,
                                        itemCount: _searchResults.length,
                                        separatorBuilder: (_, index) => const Divider(color: Colors.white12, height: 1),
                                        itemBuilder: (context, idx) {
                                          final entry = _searchResults[idx];
                                          final m = entry.member;
                                          return ListTile(
                                            title: Text(m.fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            subtitle: Text(m.phone ?? '', style: const TextStyle(color: Colors.white60)),
                                            trailing: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF0F766E),
                                                foregroundColor: Colors.white,
                                              ),
                                              onPressed: () => _evaluateMemberAccess(m),
                                              child: Text(isFr ? 'Valider Accès' : 'Valide Aksè'),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessResultCard(AppStrings s, bool isFr, bool isEn) {
    final isGranted = _status == AccessStatus.granted;
    final color = isGranted ? const Color(0xFF059669) : const Color(0xFFDC2626);

    String title;
    String subtitle;

    if (isGranted) {
      title = s.text('access_granted');
      subtitle = _daysLeft != null && _daysLeft! <= 5
          ? (isFr ? 'Attention : fin dans $_daysLeft jour(s) !' : 'Atansyon : fini nan $_daysLeft jou !')
          : (isFr ? 'Porte ouverte. Bon entraînement !' : 'Pòt louvri. Bon antrenman !');
    } else if (_status == AccessStatus.deniedExpired) {
      title = s.text('access_denied');
      subtitle = s.text('subscription_expired');
    } else if (_status == AccessStatus.deniedNoSubscription) {
      title = s.text('access_denied');
      subtitle = s.text('payment_pending');
    } else {
      title = s.text('access_denied');
      subtitle = s.text('unrecognized_fingerprint');
    }

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: isGranted ? const Color(0xFF064E3B) : const Color(0xFF7F1D1D),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: color,
              child: Icon(
                isGranted ? LucideIcons.checkCheck : LucideIcons.shieldAlert,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            if (_matchedMember != null) ...[
              const SizedBox(height: 18),
              const Divider(color: Colors.white24),
              const SizedBox(height: 12),
              Text(
                _matchedMember!.fullName,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'S/N: ${_matchedMember!.id.substring(0, 8)}',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              if (!isGranted) ...[
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF7F1D1D),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: () => context.push('/members/${_matchedMember!.id}'),
                  icon: const Icon(LucideIcons.refreshCw, size: 18),
                  label: Text(s.text('renew_now'), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
