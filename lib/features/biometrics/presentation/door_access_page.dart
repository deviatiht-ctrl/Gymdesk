import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gymdesk_biometrics/gymdesk_biometrics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/access_control/access_monitor.dart';
import '../../../core/access_control/terminal_access_service.dart';
import '../../../core/biometrics/access_agent_client.dart';
import '../../../core/biometrics/biometric_models.dart';
import '../../../core/biometrics/biometric_service.dart';
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
  StreamSubscription<AccessDecision>? _terminalSub;
  RealtimeChannel? _realtimeSub;
  Timer? _dismissTimer;

  bool _processing = false;
  bool _terminalOnline = false;

  bool get _isTerminalReallyOnline => AccessMonitor.instance.active
      ? AccessMonitor.instance.terminalOnline.value
      : (_terminalOnline || _biometricService.terminalAvailable);
  AccessStatus _status = AccessStatus.none;
  Member? _matchedMember;
  String? _matchedName;
  bool _matchedIsEmployee = false;
  String? _matchedJobType;
  String? _matchedJobTitle;
  String? _matchedEmployeeNumber;
  int? _daysLeft;
  Uint8List? _matchedPhoto;

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
      // Siveyan global la (AccessMonitor) trete evènman W2 yo sou Desktop ak Web (PC resepsyon).
      final monitor = AccessMonitor.instance;
      unawaited(monitor.start(runtime));
      _terminalOnline = monitor.terminalOnline.value;
      monitor.terminalOnline.addListener(_onMonitorStatus);
      monitor.agentOnline.addListener(_onMonitorStatus);
      _biometricService.agent.status.addListener(_onMonitorStatus);
      _terminalSub = monitor.decisions.listen(_onTerminalDecision);
      unawaited(_checkTerminalLive());

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
                if (AccessMonitor.instance.active && row['source'] == 'terminal') return;
                _handleRealtimeAccessEvent(row);
              },
            )
            .subscribe();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _checkTerminalLive() async {
    try {
      final termOk = await _agent.watchTerminal(terminalIp: _cfg.terminalIp);
      if (mounted) setState(() => _terminalOnline = termOk);
    } catch (_) {}
  }

  void _onMonitorStatus() {
    if (!mounted) return;
    setState(() {
      _terminalOnline = AccessMonitor.instance.active
          ? AccessMonitor.instance.terminalOnline.value
          : (AccessMonitor.instance.terminalOnline.value || _biometricService.terminalAvailable);
    });
  }

  /// Desizyon tèminal la deja pran (pòt ouvri, evènman pibliye, prezans
  /// anrejistre) pa AccessMonitor: isit la nou jis montre l.
  Future<void> _loadMemberPhoto(Member member) async {
    try {
      final bytes = await _membersRepo.photoBytes(member).timeout(const Duration(seconds: 4));
      if (mounted && bytes != null && bytes.isNotEmpty) {
        setState(() => _matchedPhoto = bytes);
      }
    } catch (_) {}
  }

  Future<void> _loadMemberPhotoById(String memberId, [String? photoUrl]) async {
    try {
      final local = await _membersRepo.localPhoto(memberId);
      if (local != null && local.isNotEmpty) {
        if (mounted) setState(() => _matchedPhoto = local);
        return;
      }
      if (photoUrl != null && photoUrl.isNotEmpty && !photoUrl.startsWith('http')) {
        final runtime = ref.read(appRuntimeProvider);
        final bytes = await runtime.client.storage
            .from('member-photos')
            .download(photoUrl)
            .timeout(const Duration(seconds: 4));
        if (mounted && bytes.isNotEmpty) {
          setState(() => _matchedPhoto = bytes);
          return;
        }
      }
      final member = await _membersRepo.watchMember(memberId).first.timeout(const Duration(seconds: 3));
      if (member != null) await _loadMemberPhoto(member);
    } catch (_) {}
  }

  static IconData _jobIconFor(String? jobType) => switch (jobType) {
        'coach' => LucideIcons.dumbbell,
        'reception' => LucideIcons.conciergeBell,
        'cleaning' => LucideIcons.sparkles,
        'security' => LucideIcons.shieldCheck,
        'manager' => LucideIcons.briefcase,
        'maintenance' => LucideIcons.wrench,
        _ => LucideIcons.badgeCheck,
      };

  static String _jobLabelFor(String? jobType, AppStrings s) => switch (jobType) {
        'coach' => s.text('job_coach'),
        'reception' => s.text('job_reception'),
        'cleaning' => s.text('job_cleaning'),
        'security' => s.text('job_security'),
        'manager' => s.text('job_manager'),
        'maintenance' => s.text('job_maintenance'),
        _ => s.text('job_other'),
      };

  void _onTerminalDecision(AccessDecision decision) {
    if (!mounted) return;
    final person = decision.person;
    final granted = TerminalAccessService.isGrantedDecision(decision);
    setState(() {
      _processing = false;
      _matchedMember = person?.entry?.member;
      _matchedIsEmployee = person?.isEmployee == true;
      _matchedJobType = person?.jobType ?? person?.employee?.jobType;
      _matchedJobTitle = person?.jobTitle ?? person?.employee?.jobTitle ?? (person?.isEmployee == true ? person?.displayJob : null);
      _matchedEmployeeNumber = person?.employeeNumber ?? person?.employee?.employeeNumber;
      _matchedName = person?.name ??
          (decision.outcome == AccessOutcome.legacy
              ? (decision.uid != null && decision.uid!.isNotEmpty && decision.uid != '-'
                  ? 'BioStar #${decision.uid}'
                  : 'BioStar')
              : null);
      _daysLeft = person?.isEmployee == true ? null : person?.daysLeft;
      _status = granted
          ? AccessStatus.granted
          : decision.outcome == AccessOutcome.unrecognized || person == null
          ? AccessStatus.deniedUnrecognized
          : person.reason == 'expired'
          ? AccessStatus.deniedExpired
          : AccessStatus.deniedNoSubscription;
      _matchedPhoto = null;
    });
    final m = person?.entry?.member;
    final mId = person?.memberId ?? m?.id;
    final anyId = person?.id ?? mId;
    if (m != null) {
      _loadMemberPhoto(m);
    } else if (anyId != null) {
      _loadMemberPhotoById(anyId, person?.photoUrl);
    }
    _scheduleDismiss(Duration(seconds: granted ? 6 : 6));
  }

  Future<void> _handleRealtimeAccessEvent(Map<String, dynamic> row) async {
    final memberId = row['member_id']?.toString();
    final eventType = row['event_type']?.toString() ?? 'unknown';
    final isGranted = eventType == 'granted';
    final snapshot = Map<String, dynamic>.from(row['member_snapshot'] as Map? ?? {});

    Member? member;
    if (memberId != null) {
      try {
        final entries = await _membersRepo.watch().first;
        final entry = entries.where((e) => e.member.id == memberId).firstOrNull;
        member = entry?.member;
      } catch (_) {}
    }

    if (!mounted) return;

    final name = snapshot['name']?.toString() ?? member?.fullName ?? '';
    final days = (snapshot['days_left'] as num?)?.toInt();

    setState(() {
      _matchedMember = member;
      _matchedIsEmployee = snapshot['is_employee'] == true;
      _matchedJobType = snapshot['job_type']?.toString();
      _matchedJobTitle = snapshot['job_title']?.toString();
      _matchedEmployeeNumber = snapshot['employee_number']?.toString();
      _matchedName = name;
      _daysLeft = days;
      _processing = false;
      if (isGranted) {
        _status = AccessStatus.granted;
      } else if (eventType == 'denied_expired') {
        _status = AccessStatus.deniedExpired;
      } else if (eventType == 'denied_no_subscription') {
        _status = AccessStatus.deniedNoSubscription;
      } else {
        _status = AccessStatus.deniedUnrecognized;
      }
    });

    _scheduleDismiss(Duration(seconds: isGranted ? 6 : 5));
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
      final membersRepo = MembersRepository(runtime.client, db, runtime.session!);
      final members = await membersRepo.membersWithFingerprints();
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
        unawaited(_terminalService.recordAccessEvent(
          decision: const AccessDecision(AccessOutcome.unrecognized),
          source: 'app',
        ));
        _scheduleDismiss(const Duration(seconds: 4));
        return;
      }

      // Vérification du statut d'abonnement
      await _evaluateMemberAccess(matched, recordToCloud: true);
    } catch (_) {
      setState(() {
        _status = AccessStatus.deniedUnrecognized;
        _processing = false;
      });
      _scheduleDismiss(const Duration(seconds: 4));
    }
  }

  Future<void> _evaluateMemberAccess(Member member, {bool recordToCloud = true}) async {
    final now = DateTime.now();

    // Récupérer les abonnements de ce membre
    final entries = await _membersRepo.watch(query: member.memberNumber).first;
    final entry = entries.where((e) => e.member.id == member.id).firstOrNull;

    final validity = entry?.validity ?? const MemberValidity(valid: false, reason: 'no_subscription');
    final isAccessOk = validity.valid;
    final daysRemaining = validity.daysLeft ?? -1;

    if (recordToCloud) {
      final decision = AccessDecision(
        isAccessOk ? AccessOutcome.granted : AccessOutcome.denied,
        person: entry != null ? AccessPerson.member(entry) : null,
      );
      unawaited(_terminalService.recordAccessEvent(decision: decision, source: 'app'));
    }

    if (isAccessOk) {
      setState(() {
        _status = AccessStatus.granted;
        _matchedMember = member;
        _daysLeft = daysRemaining;
        _processing = false;
      });

      // Si recordToCloud se false (pa egzanp apèl lokal san recordAccessEvent), anrejistre prezans lan
      if (!recordToCloud) {
        try {
          await _attendanceRepo.verifyFingerprintAndGrant(
            member: member,
            fingerprintMatched: true,
            scannedAt: now,
            offline: false,
            suspectClock: false,
          );
        } catch (_) {}
      }

      // Envoie l'impulsion relais à la porte
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
          _matchedName = null;
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
    AccessMonitor.instance.terminalOnline.removeListener(_onMonitorStatus);
    AccessMonitor.instance.agentOnline.removeListener(_onMonitorStatus);
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
      backgroundColor: const Color(0xFF070D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A).withOpacity(0.92),
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(s.text('door_access_kiosk')),
        actions: [
          IconButton(
            tooltip: 'Mòd Tablèt Wi-Fi (Ekran devan pòt)',
            icon: const Icon(LucideIcons.tablet, color: Color(0xFF2DD4BF)),
            onPressed: () => openAccessDisplayWindow(context, true),
          ),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = constraints.maxWidth >= constraints.maxHeight;
          final bgAsset = isLandscape
              ? 'assets/brand/background_desktop.jpeg'
              : 'assets/brand/background_mobile.jpeg';
          return Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  bgAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF070D18).withOpacity(0.88),
                        const Color(0xFF0F172A).withOpacity(0.85),
                        const Color(0xFF064E3B).withOpacity(0.88),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    // Bandeau d'état dynamique : Tèminal Pòt + Lektè USB (Responsive)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 650;
                        return Container(
                          padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 24, vertical: isNarrow ? 8 : 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A).withOpacity(0.75),
                            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
                          ),
                  child: isNarrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _isTerminalReallyOnline ? LucideIcons.shieldCheck : LucideIcons.circleAlert,
                                  color: _isTerminalReallyOnline ? const Color(0xFF10B981) : Colors.amber,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _isTerminalReallyOnline
                                        ? (isFr
                                            ? 'Terminal (${_cfg.terminalIp}) : Connecté'
                                            : 'Tèminal (${_cfg.terminalIp}) : Konekte')
                                        : (isFr
                                            ? 'Terminal (${_cfg.terminalIp.isEmpty ? "192.168.1.41" : _cfg.terminalIp}) : Non connecté'
                                            : 'Tèminal (${_cfg.terminalIp.isEmpty ? "192.168.1.41" : _cfg.terminalIp}) : Pa konekte'),
                                    style: TextStyle(
                                      color: _isTerminalReallyOnline ? Colors.white70 : Colors.amber.shade200,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
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
                                          Icon(LucideIcons.usb, size: 12, color: usbReady ? const Color(0xFF34D399) : Colors.white38),
                                          const SizedBox(width: 4),
                                          Text(
                                            usbReady ? (isFr ? 'USB : Prêt' : 'USB : Pare') : (isFr ? 'USB : Débranché' : 'USB : Deploge'),
                                            style: TextStyle(fontSize: 10, color: usbReady ? const Color(0xFF34D399) : Colors.white38, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: isFr ? 'Tester' : 'Teste',
                                      icon: const Icon(LucideIcons.refreshCw, size: 15, color: Colors.white70),
                                      onPressed: () async {
                                        final termOk = await _agent.watchTerminal(terminalIp: _cfg.terminalIp);
                                        await _biometricService.checkSensorConnection();
                                        if (mounted) setState(() => _terminalOnline = termOk);
                                      },
                                    ),
                                    TextButton.icon(
                                      onPressed: () => context.push('/settings/biometrics'),
                                      icon: const Icon(LucideIcons.settings, size: 15, color: Colors.white70),
                                      label: Text(s.text('settings'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Icon(
                              _isTerminalReallyOnline ? LucideIcons.shieldCheck : LucideIcons.circleAlert,
                              color: _isTerminalReallyOnline ? const Color(0xFF10B981) : Colors.amber,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _isTerminalReallyOnline
                                    ? (isFr
                                        ? 'Terminal de porte (${_cfg.terminalIp}) : Connecté & Prêt'
                                        : 'Tèminal Pòt (${_cfg.terminalIp}) : Konekte & Pare')
                                    : (isFr
                                        ? 'Terminal de porte (${_cfg.terminalIp.isEmpty ? "192.168.1.41" : _cfg.terminalIp}) : Non connecté (vérifiez le réseau)'
                                        : 'Tèminal Pòt (${_cfg.terminalIp.isEmpty ? "192.168.1.41" : _cfg.terminalIp}) : Pa konekte (verifye rezo a)'),
                                style: TextStyle(
                                  color: _isTerminalReallyOnline ? Colors.white70 : Colors.amber.shade200,
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
                );
              },
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
                            _isTerminalReallyOnline
                                ? (isFr
                                    ? 'Terminal ${_cfg.terminalIp} actif · Détection automatique'
                                    : 'Tèminal ${_cfg.terminalIp} aktif · Deteksyon otomatik')
                                : (isFr
                                    ? 'Terminal non connecté · Vérifiez l’IP dans les paramètres'
                                    : 'Tèminal pa konekte · Verifye adrès IP a nan Paramèt'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _isTerminalReallyOnline ? const Color(0xFF2DD4BF) : Colors.amber.shade200,
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
            ],
          );
        },
      ),
    );
  }

  Widget _buildAccessResultCard(AppStrings s, bool isFr, bool isEn) {
    final isGranted = _status == AccessStatus.granted;
    final color = isGranted ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    String title;
    String subtitle;

    if (isGranted) {
      title = s.text('access_granted');
      subtitle = _matchedIsEmployee
          ? '${s.text('employee_access')} · ${s.text('employee_welcome')}'
          : _daysLeft == null
          ? s.text('door_pulse_sent')
          : _daysLeft! <= 0
          ? s.text('expires_today')
          : s.text('days_left_n').replaceAll('{n}', '$_daysLeft');
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

    final displayName = _matchedMember?.fullName ?? _matchedName;
    final initials = displayName?.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withOpacity(0.65),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.25),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Glowing Circle Avatar with Member Photo
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.45),
                        blurRadius: 22,
                        spreadRadius: 4,
                      ),
                    ],
                    color: color.withOpacity(0.15),
                    image: _matchedPhoto != null
                        ? DecorationImage(
                            image: MemoryImage(_matchedPhoto!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _matchedPhoto == null
                      ? Center(
                          child: (initials != null && initials.isNotEmpty)
                              ? Text(
                                  initials,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 44,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                              : Icon(
                                  isGranted ? LucideIcons.checkCheck : LucideIcons.shieldAlert,
                                  size: 54,
                                  color: color,
                                ),
                        )
                      : null,
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                if (displayName != null) ...[
                  const SizedBox(height: 18),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 12),
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_matchedIsEmployee) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
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
                            _jobIconFor(_matchedJobType),
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            (_matchedJobTitle?.isNotEmpty == true
                                    ? _matchedJobTitle!
                                    : _jobLabelFor(_matchedJobType, s))
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_matchedEmployeeNumber != null && _matchedEmployeeNumber!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Matricule : ',
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ] else ...[
                  if (_daysLeft != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: (_daysLeft! <= 5 ? Colors.amber : const Color(0xFF10B981)).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _daysLeft! <= 5 ? Colors.amber : const Color(0xFF10B981),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        s.text('days_left_n').replaceAll('{n}', '$_daysLeft'),
                        style: TextStyle(
                          color: _daysLeft! <= 5 ? Colors.amberAccent : const Color(0xFF34D399),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  if (_matchedMember != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'ID: ${_matchedMember!.memberNumber.isNotEmpty ? _matchedMember!.memberNumber : _matchedMember!.id.substring(0, 8)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    if (!isGranted) ...[
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF7F1D1D),
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => context.push('/members/${_matchedMember!.id}'),
                        icon: const Icon(LucideIcons.refreshCw, size: 18),
                        label: Text(s.text('renew_now'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
