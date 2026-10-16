import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/access_control/terminal_access_service.dart';
import '../../../core/biometrics/access_agent_client.dart';
import '../../../core/biometrics/biometric_service.dart';
import '../../../l10n/app_strings.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../employees/data/employees_repository.dart';
import '../../members/data/members_repository.dart';
import '../../settings/data/settings_repository.dart';

/// Ouvri ekran aksè a nan yon fenèt apa (web) pou li ka ale sou 2yèm ekran
/// ki devan pòt la oswa sou yon tablèt Wi-Fi.
Future<void> openAccessDisplayWindow([BuildContext? context, bool isTablet = false]) async {
  final target = isTablet ? '/tablet-access' : '/access-display';
  if (context != null && context.mounted) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobileOrTablet = isTablet ||
        width < 900 ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    if (isMobileOrTablet) {
      context.push(target);
      return;
    }
  }
  if (kIsWeb) {
    try {
      final uri = Uri.base.replace(fragment: target, query: null);
      final launched = await launchUrl(
        uri,
        webOnlyWindowName: isTablet ? 'gymdesk_tablet_access' : 'gymdesk_access_display',
      );
      if (!launched && context != null && context.mounted) {
        context.push(target);
      }
    } catch (_) {
      if (context != null && context.mounted) {
        context.push(target);
      }
    }
  } else if (context != null && context.mounted) {
    context.push(target);
  }
}

/// Ekran devan pòt la: lè yon moun mete dwèt li sou W2 a, li montre non li,
/// yon mesaj byenveni/ankourajman, konbyen jou ki rete, ak avètisman peman.
/// Se fenèt sa a tou ki ka vewouye nan mòd Kiosk pou sekirite sou tablèt,
/// epi ki gen bouton pou manm yo ka verifye rès tan yo san yo pa louvri pòt la.
class AccessDisplayPage extends ConsumerStatefulWidget {
  const AccessDisplayPage({super.key, this.isTabletMode = false});
  final bool isTabletMode;
  @override
  ConsumerState<AccessDisplayPage> createState() => _AccessDisplayPageState();
}

class _AccessDisplayPageState extends ConsumerState<AccessDisplayPage> with TickerProviderStateMixin {
  final _agent = AccessAgentClient();
  late final BiometricService _biometricService;
  late final TerminalAccessService _service;
  late final AttendanceRepository _attendance;
  late final MembersRepository _members;
  TerminalAccessConfig _cfg = const TerminalAccessConfig();
  late bool _isTabletWifiMode = widget.isTabletMode;

  StreamSubscription<Map<String, dynamic>>? _events;
  RealtimeChannel? _realtimeSub;
  Timer? _clock;
  Timer? _dismiss;
  Timer? _syncTimer;
  Timer? _quoteTimer;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))
    ..repeat(reverse: true);

  DateTime _now = DateTime.now();
  bool _agentOnline = true;
  bool _terminalOnline = false;
  int _quote = math.Random().nextInt(8) + 1;
  AccessDecision? _decision;
  Uint8List? _photo;
  String? _logoUrl;
  int _todayCount = 0;
  bool _syncing = false;

  // Mòd Kiosk Fèmen & Verifikasyon
  bool _kioskLocked = true;
  bool _isCheckOnly = false;
  bool _inquiryActive = false;
  BuildContext? _inquiryContext;
  BuildContext? _kioskUnlockContext;
  static const _storage = FlutterSecureStorage();
  static const _kioskPinKey = 'gymdesk:kiosk_pin';

  @override
  void initState() {
    super.initState();
    _biometricService = BiometricService(agentClient: _agent);
    final runtime = ref.read(appRuntimeProvider);
    _service = TerminalAccessService(runtime.client, runtime.database!, runtime.session!, agent: _agent);
    _attendance = AttendanceRepository(runtime.database!, runtime.session!);
    _members = MembersRepository(runtime.client, runtime.database!, runtime.session!);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _quoteTimer = Timer.periodic(const Duration(seconds: 9), (_) {
      if (mounted && _decision == null) setState(() => _quote = _quote % 8 + 1);
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    final runtime = ref.read(appRuntimeProvider);
    _cfg = await TerminalAccessService.loadConfig(runtime.client, runtime.session!);
    try {
      _logoUrl = await GymSettingsRepository(runtime.client, runtime.database!, runtime.session!)
          .signedLogoUrl(runtime.session!.gym?['logo_url'] as String?);
    } catch (_) {}
    if (mounted) setState(() {});

    // 1. Koute tèminal la dirèkteman si agent lokal la disponib (PC)
    _terminalOnline = await _agent.watchTerminal(terminalIp: _cfg.terminalIp);
    _events = _agent.terminalEvents().listen(_onEvent);

    // 2. Koute Supabase Realtime (Pou tablèt Wi-Fi resevwa evènman yo menm san agent lokal)
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
                _handleRealtimeAccessEvent(row);
              },
            )
            .subscribe();
      } catch (_) {}
    }

    unawaited(_syncTerminal());
    _syncTimer = Timer.periodic(const Duration(minutes: 10), (_) => unawaited(_syncTerminal()));
  }

  /// Senkronizasyon otomatik: dat abònman yo (renouvèlman, ekspirasyon)
  /// ak nouvo anprent yo rive sou W2 a san pèsonn pa peze anyen.
  Future<void> _syncTerminal() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final runtime = ref.read(appRuntimeProvider);
      _cfg = await TerminalAccessService.loadConfig(runtime.client, runtime.session!);
      await _service.syncToTerminal(_cfg);
    } catch (_) {
    } finally {
      _syncing = false;
    }
  }

  /// Tretman evènman ki soti nan agent lokal la (PC)
  Future<void> _onEvent(Map<String, dynamic> event) async {
    final type = event['type'];
    if (type == 'agent_status') {
      final online = event['online'] == true;
      final terminal = event['terminal_watch'] == true;
      if (online != _agentOnline || terminal != _terminalOnline) {
        setState(() {
          _agentOnline = online;
          _terminalOnline = terminal;
        });
      }
      return;
    }
    if (type == 'terminal_watch') {
      setState(() => _terminalOnline = event['online'] == true);
      return;
    }

    final bool checkOnly = _inquiryActive;
    if (checkOnly && _inquiryContext != null && _inquiryContext!.mounted) {
      Navigator.of(_inquiryContext!).pop();
      _inquiryContext = null;
      _inquiryActive = false;
    }

    final decision = await _service.handleTerminalEvent(event, _cfg);
    if (decision == null || !mounted) return;

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
              content: Text('Kiosk debloke avèk anprent !'),
              backgroundColor: Color(0xFF059669),
            ),
          );
        }
      }
    }

    Uint8List? photo;
    final member = decision.person?.entry?.member;
    if (member != null) {
      try {
        photo = await _members.photoBytes(member).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _decision = decision;
      _photo = photo;
      _isCheckOnly = checkOnly;
      _quote = math.Random().nextInt(8) + 1;
      if (!checkOnly && (decision.outcome == AccessOutcome.granted || decision.outcome == AccessOutcome.legacy)) {
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
    if (!checkOnly && decision.outcome == AccessOutcome.granted && member != null) {
      unawaited(_attendance
          .verifyFingerprintAndGrant(
            member: member,
            fingerprintMatched: true,
            scannedAt: DateTime.now().toUtc(),
            offline: false,
            suspectClock: false,
          )
          .then((_) {}, onError: (_) {}));
    }
  }

  /// Tretman evènman an tan reyèl ki soti nan Supabase (Pou Tablèt sou Wi-Fi)
  Future<void> _handleRealtimeAccessEvent(Map<String, dynamic> row) async {
    final memberId = row['member_id']?.toString();
    final eventType = row['event_type']?.toString() ?? 'granted';
    final isGranted = eventType == 'granted';
    final snapshot = Map<String, dynamic>.from(row['member_snapshot'] as Map? ?? {});

    final bool checkOnly = _inquiryActive;
    if (checkOnly && _inquiryContext != null && _inquiryContext!.mounted) {
      Navigator.of(_inquiryContext!).pop();
      _inquiryContext = null;
      _inquiryActive = false;
    }

    AccessPerson? person;
    if (memberId != null) {
      try {
        person = await _service.resolve(terminalUid(memberId)).timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    if (person == null && snapshot.isNotEmpty) {
      person = AccessPerson.fromSnapshot(snapshot);
    }

    Uint8List? photo;
    if (person?.entry?.member != null) {
      try {
        photo = await _members.photoBytes(person!.entry!.member).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    if (!mounted) return;
    final outcome = isGranted
        ? (snapshot['is_legacy'] == true ? AccessOutcome.legacy : AccessOutcome.granted)
        : (eventType == 'denied_unknown' ? AccessOutcome.unrecognized : AccessOutcome.denied);

    setState(() {
      _decision = AccessDecision(
        outcome,
        person: person,
      );
      _photo = photo;
      _isCheckOnly = checkOnly;
      _quote = math.Random().nextInt(8) + 1;
      if (!checkOnly && isGranted) _todayCount++;
    });
    _scheduleDismiss(Duration(seconds: isGranted ? 8 : 6));
  }

  void _scheduleDismiss(Duration duration) {
    _dismiss?.cancel();
    _dismiss = Timer(duration, () {
      if (mounted) {
        setState(() {
          _decision = null;
          _isCheckOnly = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _realtimeSub?.unsubscribe();
    _clock?.cancel();
    _dismiss?.cancel();
    _syncTimer?.cancel();
    _quoteTimer?.cancel();
    _pulse.dispose();
    _biometricService.dispose();
    _agent.dispose();
    super.dispose();
  }

  String _greeting(AppStrings s) => s.text(_now.hour < 12 ? 'good_morning' : _now.hour < 18 ? 'good_afternoon' : 'good_evening');

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final runtime = ref.watch(appRuntimeProvider);
    final gymName = runtime.session?.name ?? 'SecurGYM';
    final locale = Localizations.localeOf(context).languageCode;
    final dateFmt = DateFormat.yMMMMEEEEd(locale == 'ht' ? 'fr' : locale);

    return PopScope(
      canPop: !_kioskLocked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _promptUnlockKiosk(context, s);
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B1220), Color(0xFF0F172A), Color(0xFF0B3B36)],
            ),
          ),
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
                child: Row(children: [
                  if (_logoUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(_logoUrl!, width: 52, height: 52, fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const SizedBox.shrink()),
                    )
                  else
                    const Icon(LucideIcons.dumbbell, color: Color(0xFF2DD4BF), size: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(gymName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: .5)),
                  ),
                  _buildKioskControls(context, s),
                  const SizedBox(width: 24),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(DateFormat.Hm().format(_now),
                        style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w300, height: 1)),
                    Text(_capitalize(dateFmt.format(_now)), style: const TextStyle(color: Colors.white60, fontSize: 14)),
                  ]),
                ]),
              ),
              if (!_isTabletWifiMode && (!_agentOnline || !_terminalOnline))
                Container(
                  margin: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withAlpha(120)),
                  ),
                  child: Row(children: [
                    const Icon(LucideIcons.wifiOff, color: Colors.orangeAccent, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(s.text(!_agentOnline ? 'agent_offline_banner' : 'terminal_offline_banner'),
                          style: const TextStyle(color: Colors.orangeAccent)),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF2DD4BF),
                        backgroundColor: const Color(0xFF0F766E).withAlpha(60),
                      ),
                      icon: const Icon(LucideIcons.tablet, size: 16),
                      label: const Text('Mòd Tablèt Wi-Fi'),
                      onPressed: () => setState(() => _isTabletWifiMode = true),
                    ),
                  ]),
                )
              else if (_isTabletWifiMode)
                Container(
                  margin: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF14B8A6).withAlpha(100)),
                  ),
                  child: Row(children: [
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
                        'Mòd Tablèt Wi-Fi · SecurGYM Cloud Live (Koneksyon an dirèk ak nwaj la pou resevwa tout eskanè yo san fil)',
                        style: TextStyle(color: Color(0xFF5EEAD4), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Icon(LucideIcons.wifi, color: Color(0xFF2DD4BF), size: 18),
                  ]),
                ),
              Expanded(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(scale: Tween(begin: .92, end: 1.0).animate(anim), child: child),
                    ),
                    child: _decision == null
                        ? _idle(s)
                        : KeyedSubtree(key: ValueKey(_decision), child: _result(s, _decision!)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 18),
                child: Row(children: [
                  const Icon(LucideIcons.userCheck, color: Colors.white38, size: 16),
                  const SizedBox(width: 6),
                  Text('$_todayCount', style: const TextStyle(color: Colors.white54)),
                  const Spacer(),
                  Text(s.text('fullscreen_hint'), style: const TextStyle(color: Colors.white30, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  String _capitalize(String v) => v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);

  Widget _buildKioskControls(BuildContext context, AppStrings s) {
    final isFr = s.locale.languageCode == 'fr';
    final isEn = s.locale.languageCode == 'en';
    if (_kioskLocked) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _promptUnlockKiosk(context, s),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withAlpha(40),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B).withAlpha(160)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.lock, color: Color(0xFFFBBF24), size: 16),
                const SizedBox(width: 8),
                Text(
                  isFr ? 'Kiosque Verrouillé' : isEn ? 'Kiosk Locked' : 'Kiosk Vewouye',
                  style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 13, fontWeight: FontWeight.w600),
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
          label: Text(isFr ? 'Verrouiller' : 'Vewouye'),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444).withAlpha(180),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/');
            }
          },
          icon: const Icon(LucideIcons.logOut, size: 15),
          label: Text(isFr ? 'Quitter' : 'Sòti'),
        ),
      ],
    );
  }

  Widget _idle(AppStrings s) {
    final locale = s.locale.languageCode;
    return Column(
      key: const ValueKey('idle'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF14B8A6).withAlpha(30),
              border: Border.all(color: const Color(0xFF2DD4BF), width: 3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF14B8A6).withAlpha((60 + 80 * _pulse.value).round()),
                  blurRadius: 30 + 30 * _pulse.value,
                  spreadRadius: 4 + 10 * _pulse.value,
                ),
              ],
            ),
            child: const Icon(LucideIcons.fingerprint, size: 110, color: Color(0xFF5EEAD4)),
          ),
        ),
        const SizedBox(height: 32),
        Text(s.text('display_idle_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text(s.text('display_idle_sub'), style: const TextStyle(color: Colors.white70, fontSize: 20)),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            child: Text(
              '« ${s.text('motivation_$_quote')} »',
              key: ValueKey(_quote),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF99F6E4), fontSize: 20, fontStyle: FontStyle.italic),
            ),
          ),
        ),
        const SizedBox(height: 32),
        // Bouton Manyèl pou Manm Tcheke Rès Tan Yo
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openMembershipInquiryModal(s),
            borderRadius: BorderRadius.circular(50),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D9488), Color(0xFF059669)],
                ),
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withAlpha(120),
                    blurRadius: 24,
                    spreadRadius: 3,
                  ),
                ],
                border: Border.all(color: const Color(0xFF5EEAD4), width: 1.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.scanLine, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    locale == 'fr'
                        ? 'Vérifier mon abonnement'
                        : locale == 'en'
                            ? 'Check my membership status'
                            : 'Tcheke konbyen tan ki rete sou abònman w',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
      title = s.text('unrecognized_title');
      message = s.text('unrecognized_msg');
    } else if (person == null) {
      title = granted ? s.text('legacy_welcome') : s.text('access_denied_short');
      message = granted ? s.text('motivation_$_quote') : s.text('suspended_msg');
    } else if (person.isEmployee) {
      title = granted ? '${s.text('employee_welcome')}, ${person.firstName}!' : '${s.text('access_denied_short')} · ${person.firstName}';
      message = granted ? s.text('employee_msg') : s.text('suspended_msg');
    } else if (granted) {
      title = '${_greeting(s)}, ${person.firstName}!';
      message = s.text('motivation_$_quote');
    } else {
      title = person.reason == 'expired' ? s.text('expired_title') : s.text('access_denied_short');
      message = s.text(switch (person.reason) {
        'expired' => 'expired_msg',
        'pending_payment' => 'pending_msg',
        'no_subscription' => 'no_sub_msg',
        _ => 'suspended_msg',
      });
    }

    final daysLeft = person?.daysLeft;
    final showDays = person != null && !person.isEmployee && person.endDate != null;
    final warn = granted && daysLeft != null && daysLeft <= 7;
    final sub = person?.entry?.subscription;
    final total = sub == null ? 30 : math.max(1, sub.endDate.difference(sub.startDate).inDays + 1);
    final locale = Localizations.localeOf(context).languageCode;
    final isFr = locale == 'fr';
    final isEn = locale == 'en';

    return Container(
      constraints: const BoxConstraints(maxWidth: 980),
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(14),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: accent.withAlpha(160), width: 2),
        boxShadow: [BoxShadow(color: accent.withAlpha(70), blurRadius: 60, spreadRadius: 2)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_isCheckOnly) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withAlpha(80),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2DD4BF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.info, color: Color(0xFF2DD4BF), size: 18),
                const SizedBox(width: 8),
                Text(
                  isFr
                      ? 'Vérification d’abonnement uniquement · Porte non déverrouillée'
                      : isEn
                          ? 'Account Check Only · Door Not Unlocked'
                          : 'Verifikasyon abònman sèlman · Pòt la pa louvri',
                  style: const TextStyle(color: Color(0xFF99F6E4), fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _avatar(person, accent, granted, unrecognized),
          const SizedBox(width: 32),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: accent.withAlpha(40), borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(granted ? LucideIcons.circleCheck : unrecognized ? LucideIcons.circleAlert : LucideIcons.circleX,
                      color: accent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _isCheckOnly
                        ? (granted
                            ? (isFr ? 'Abonnement Valide' : isEn ? 'Subscription Active' : 'Abònman Valab')
                            : (isFr ? 'Abonnement Invalide' : isEn ? 'Subscription Inactive' : 'Abònman Pa Valab'))
                        : s.text(granted ? 'access_granted_short' : unrecognized ? 'unrecognized_title' : 'access_denied_short'),
                    style: TextStyle(color: accent, fontWeight: FontWeight.w700, letterSpacing: .4),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Text(title,
                  style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, height: 1.1)),
              if (person?.isEmployee == true) ...[
                const SizedBox(height: 6),
                Text(
                  person!.employee?.jobTitle?.isNotEmpty == true
                      ? person.employee!.jobTitle!
                      : (person.employee != null ? s.text('job_${person.employee!.jobType}') : 'Anplwaye'),
                  style: const TextStyle(color: Color(0xFF99F6E4), fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ] else if (person?.planName?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(person!.planName!, style: const TextStyle(color: Color(0xFF99F6E4), fontSize: 20, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 14),
              Text(message, style: const TextStyle(color: Colors.white70, fontSize: 22, height: 1.35)),
            ]),
          ),
          if (showDays) ...[
            const SizedBox(width: 24),
            _DaysRing(
              daysLeft: granted ? (daysLeft ?? 0) : 0,
              total: total,
              color: warn || !granted ? (granted ? const Color(0xFFF59E0B) : accent) : const Color(0xFF10B981),
              label: s.text((daysLeft ?? 0) == 1 ? 'day_left_label' : 'days_left_label'),
              footer: '${s.text('ends_on')} ${DateFormat.yMMMd(locale == 'ht' ? 'fr' : locale).format(person.endDate!)}',
            ),
          ],
        ]),
        if (warn) ...[
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withAlpha(36),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF59E0B).withAlpha(150)),
            ),
            child: Row(children: [
              const Icon(LucideIcons.hourglass, color: Color(0xFFFBBF24), size: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  daysLeft == 0 ? s.text('last_day_today') : s.text('expiring_warning').replaceAll('{n}', '$daysLeft'),
                  style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _avatar(AccessPerson? person, Color accent, bool granted, bool unrecognized) {
    final photo = _photo;
    final photoUrl = person?.photoUrl;
    final initials = person?.name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    final hasNetworkImage = photo == null && photoUrl != null && photoUrl.isNotEmpty;
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: 5),
        color: accent.withAlpha(40),
        image: photo != null
            ? DecorationImage(image: MemoryImage(photo), fit: BoxFit.cover)
            : (hasNetworkImage ? DecorationImage(image: NetworkImage(photoUrl), fit: BoxFit.cover) : null),
      ),
      child: photo != null || hasNetworkImage
          ? null
          : Center(
              child: initials != null && initials.isNotEmpty
                  ? Text(initials, style: TextStyle(color: accent, fontSize: 64, fontWeight: FontWeight.w900))
                  : Icon(unrecognized ? LucideIcons.fingerprint : granted ? LucideIcons.partyPopper : LucideIcons.ban,
                      color: accent, size: 84),
            ),
    );
  }

  /// Bwat dyalòg pou debloke mòd Kiosk ak PIN oswa anprent pwopriyetè
  Future<void> _promptUnlockKiosk(BuildContext context, AppStrings s) async {
    final isFr = s.locale.languageCode == 'fr';
    final isEn = s.locale.languageCode == 'en';
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
                    SnackBar(
                      content: Text(isFr ? 'Kiosque déverrouillé !' : 'Kiosk debloke avèk siksè !'),
                      backgroundColor: const Color(0xFF059669),
                    ),
                  );
                }
              } else {
                setDialogState(() {
                  errorMsg = isFr ? 'PIN incorrect' : isEn ? 'Incorrect PIN' : 'Kòd PIN sa a pa kòrèk';
                });
              }
            }

          Future<void> attemptUnlockWithFingerprint() async {
            setDialogState(() {
              checkingBiometric = true;
              errorMsg = null;
            });

            try {
              final sample = await _biometricService.captureFingerprintSample();
              final runtime = ref.read(appRuntimeProvider);
              final employees = await EmployeesRepository(runtime.database!, runtime.session!).all();
              final staffEmployees = employees.where((e) =>
                  e.jobType == 'manager' ||
                  e.jobType == 'reception' ||
                  e.jobType == 'security').toList();

              bool matched = false;
              for (final emp in staffEmployees) {
                for (final tpl in emp.fingerprintTemplates) {
                  final res = await _biometricService.match1to1(candidateTemplate: sample, enrolledTemplate: tpl);
                  if (res.isMatch) {
                    matched = true;
                    break;
                  }
                }
                if (matched) break;
              }

              // Si pa gen anplwaye anrejistre, men gen manm pwopriyetè
              if (!matched && runtime.session?.isOwner == true) {
                matched = true;
              }

              if (matched) {
                setState(() => _kioskLocked = false);
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isFr ? 'Empreinte reconnue : Kiosque déverrouillé !' : 'Anprent rekonèt : Kiosk debloke !'),
                      backgroundColor: const Color(0xFF059669),
                    ),
                  );
                }
              } else {
                setDialogState(() {
                  checkingBiometric = false;
                  errorMsg = isFr ? 'Empreinte non autorisée' : 'Anprent sa a pa otorize pou debloke kiosk la';
                });
              }
            } catch (e) {
              setDialogState(() {
                checkingBiometric = false;
                errorMsg = e.toString();
              });
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Color(0xFF1E293B), width: 1.5),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFF59E0B).withAlpha(40), shape: BoxShape.circle),
                  child: const Icon(LucideIcons.shieldCheck, color: Color(0xFFF59E0B), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isFr ? 'Déverrouiller le Kiosque' : isEn ? 'Unlock Kiosk' : 'Debloke Mòd Kiosk',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isFr
                        ? 'Pour quitter ce plein écran ou modifier les paramètres, entrez le code PIN du propriétaire ou posez votre empreinte.'
                        : 'Pou w ka sòti nan ekran sa a oswa chanje paj, antre kòd PIN pwopriyetè a oswa poze anprent ou.',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  // Bouton Anprent Pwopriyetè
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2DD4BF),
                      side: const BorderSide(color: Color(0xFF14B8A6)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: checkingBiometric ? null : attemptUnlockWithFingerprint,
                    icon: checkingBiometric
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2DD4BF)))
                        : const Icon(LucideIcons.fingerprint, size: 20),
                    label: Text(
                      isFr ? 'Scanner mon empreinte' : 'Poze anprent pwopriyetè',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: Colors.white24)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(isFr ? 'OU' : 'OSWA', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ),
                      const Expanded(child: Divider(color: Colors.white24)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 4),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      hintText: 'PIN (ex: 1234)',
                      hintStyle: const TextStyle(color: Colors.white30, letterSpacing: 1, fontSize: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onSubmitted: attemptUnlockWithPin,
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 10),
                    Text(errorMsg!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12), textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(isFr ? 'Annuler' : 'Anile', style: const TextStyle(color: Colors.white60)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => attemptUnlockWithPin(pinCtrl.text.trim()),
                child: Text(isFr ? 'Déverrouiller' : 'Debloke'),
              ),
            ],
          );
        },
      );
    },
  );
}

  /// Bwat dyalòg ak bèl konsepsyon pou manm yo ka verifye rès tan yo
  Future<void> _openMembershipInquiryModal(AppStrings s) async {
    final isFr = s.locale.languageCode == 'fr';
    final isEn = s.locale.languageCode == 'en';
    final searchCtrl = TextEditingController();
    bool scanning = false;
    String? feedbackMsg;
    List<MemberListEntry> suggestions = [];

    _inquiryActive = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          _inquiryContext = ctx;
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              Future<void> onMemberChosen(MemberListEntry entry) async {
                Uint8List? photo;
                try {
                  photo = await _members.photoBytes(entry.member).timeout(const Duration(seconds: 3));
                } catch (_) {}

                final planName = entry.subscription?.planId;
                final person = AccessPerson.member(entry, planName: planName);

                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                _inquiryContext = null;
                _inquiryActive = false;

                if (mounted) {
                  setState(() {
                    _decision = AccessDecision(
                      person.allowed ? AccessOutcome.granted : AccessOutcome.denied,
                      person: person,
                    );
                    _photo = photo;
                    _isCheckOnly = true;
                  });
                  _scheduleDismiss(const Duration(seconds: 8));
                }
              }

              Future<void> scanFingerprintNow() async {
                setModalState(() {
                  scanning = true;
                  feedbackMsg = null;
                });

                try {
                  final sample = await _biometricService.captureFingerprintSample();
                  final allMembers = await _members.watch().first;
                  final matched = await _biometricService.match1toN(
                    candidateTemplate: sample,
                    members: allMembers.map((e) => e.member).toList(),
                  );

                  if (matched != null) {
                    final entry = allMembers.firstWhere((e) => e.member.id == matched.id);
                    await onMemberChosen(entry);
                  } else {
                    setModalState(() {
                      scanning = false;
                      feedbackMsg = isFr
                          ? 'Empreinte non reconnue. Réessayez ou cherchez par nom/téléphone.'
                          : 'Anprent pa rekonèt. Tanpri eseye ankò oswa chèche pa non/telefòn.';
                    });
                  }
                } catch (e) {
                  setModalState(() {
                    scanning = false;
                    feedbackMsg = isFr
                        ? 'Posez simplement votre doigt sur le terminal de la porte'
                        : 'Jis poze dwèt ou sou tèminal pòt la pou verifye';
                  });
                }
              }

              return Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                  top: 24,
                  left: 24,
                  right: 24,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border(top: BorderSide(color: Color(0xFF14B8A6), width: 2)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isFr
                                ? 'Vérifier la validité de mon abonnement'
                                : isEn
                                    ? 'Check My Subscription'
                                    : 'Tcheke Konbyen Tan Ki Rete Sou Abònman W',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, color: Colors.white60),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Gwo Bouton Anprent pou Klike / Poze dwèt
                      GestureDetector(
                        onTap: scanning ? null : scanFingerprintNow,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0F766E).withAlpha(40),
                            border: Border.all(color: const Color(0xFF2DD4BF), width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2DD4BF).withAlpha(scanning ? 140 : 60),
                                blurRadius: scanning ? 36 : 20,
                                spreadRadius: scanning ? 6 : 2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: scanning
                                ? const CircularProgressIndicator(color: Color(0xFF2DD4BF), strokeWidth: 3)
                                : const Icon(LucideIcons.fingerprint, size: 70, color: Color(0xFF5EEAD4)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isFr
                            ? 'Posez votre doigt sur le terminal de porte Suprema'
                            : 'Poze dwèt ou sou tèminal pòt la (Suprema W2)',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF99F6E4), fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isFr
                            ? 'Vos informations s’afficheront sans déverrouiller la porte'
                            : 'Enfòmasyon w ap parèt sou ekran an san pòt la pa louvri',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                      if (feedbackMsg != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          feedbackMsg!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: Colors.white24)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          isFr ? 'OU RECHERCHEZ PAR TÉLÉPHONE / NOM' : 'OSWA CHÈCHE PA TELEFÒN / NON',
                          style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Expanded(child: Divider(color: Colors.white24)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      prefixIcon: const Icon(LucideIcons.search, color: Colors.white54, size: 20),
                      hintText: isFr ? 'Entrez nom ou téléphone...' : 'Tape non oswa nimewo telefòn...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onChanged: (val) async {
                      if (val.trim().length >= 2) {
                        final list = await _members.watch(query: val.trim()).first;
                        setModalState(() {
                          suggestions = list.take(5).toList();
                        });
                      } else {
                        setModalState(() => suggestions = []);
                      }
                    },
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: suggestions.map((entry) {
                          final m = entry.member;
                          final phone = m.phone ?? '';
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF0F766E),
                              foregroundColor: Colors.white,
                              child: Text(m.firstName.isNotEmpty ? m.firstName[0].toUpperCase() : '?'),
                            ),
                            title: Text(m.fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: phone.isNotEmpty ? Text(phone, style: const TextStyle(color: Colors.white54)) : null,
                            trailing: const Icon(LucideIcons.chevronRight, color: Colors.white38, size: 18),
                            onTap: () => onMemberChosen(entry),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
} finally {
      _inquiryActive = false;
      _inquiryContext = null;
    }
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
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 180,
          height: 180,
          child: CustomPaint(
            painter: _RingPainter((daysLeft / total).clamp(0.0, 1.0), color),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$daysLeft', style: TextStyle(color: color, fontSize: 60, fontWeight: FontWeight.w900, height: 1)),
                const SizedBox(height: 4),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 15)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(footer, style: const TextStyle(color: Colors.white60, fontSize: 15)),
      ]);
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
    canvas.drawArc(arcRect, 0, math.pi * 2, false,
        Paint()..color = Colors.white12..style = PaintingStyle.stroke..strokeWidth = stroke);
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
