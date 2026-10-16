import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/attendance/data/attendance_repository.dart';
import '../../features/employees/data/employees_repository.dart';
import '../../features/employees/domain/employee.dart';
import '../../features/members/data/members_repository.dart';
import '../../features/plans/domain/plan.dart';
import '../biometrics/access_agent_client.dart';
import '../db/local_database.dart';
import '../sync/sync_models.dart';

/// Kiyès ki kontwole pòt la (chwazi pa pwopriyetè a nan Paramèt → Biyometri).
///  * [terminalEnforces]: W2 a resevwa dat fen abònman an. Li ouvri/refize li
///    menm, menm si laptop la etenn. Moun ki pa peye yo bloke otomatikman.
///  * [appControls]: app la tcheke peman an epi se li ki ouvri pòt la. Si app
///    la fèmen, pèsonn pa antre. Ak tou de: W2 a mache offline, epi app la
///    ouvri tou pou moun ki fenk renouvle (W2 a poko gen nouvo dat la).
class TerminalAccessConfig {
  const TerminalAccessConfig({
    this.terminalEnforces = true,
    this.appControls = false,
    this.terminalIp = '192.168.1.41',
    this.pulseSeconds = 3,
  });

  factory TerminalAccessConfig.fromJson(Json cfg) {
    final terminal = cfg['terminal_enforces_expiry'] != false;
    final app = cfg['app_controls_door'] == true;
    return TerminalAccessConfig(
      terminalEnforces: terminal || !app,
      appControls: app,
      terminalIp: (cfg['terminal_ip'] as String?)?.trim().isNotEmpty == true
          ? (cfg['terminal_ip'] as String).trim()
          : '192.168.1.41',
      pulseSeconds: ((cfg['pulse_duration_seconds'] as num?)?.round() ?? 3).clamp(1, 20),
    );
  }

  final bool terminalEnforces;
  final bool appControls;
  final String terminalIp;
  final int pulseSeconds;
}

enum AccessOutcome { granted, denied, unrecognized, legacy }

class AccessPerson {
  const AccessPerson.member(MemberListEntry this.entry, {this.planName})
      : employee = null,
        _snapshotId = null,
        _snapshotName = null,
        _snapshotFirstName = null,
        _snapshotIsEmployee = null,
        _snapshotAllowed = null,
        _snapshotReason = null,
        _snapshotDaysLeft = null,
        _snapshotEndDate = null,
        _snapshotPhotoUrl = null;

  const AccessPerson.employee(Employee this.employee)
      : entry = null,
        planName = null,
        _snapshotId = null,
        _snapshotName = null,
        _snapshotFirstName = null,
        _snapshotIsEmployee = null,
        _snapshotAllowed = null,
        _snapshotReason = null,
        _snapshotDaysLeft = null,
        _snapshotEndDate = null,
        _snapshotPhotoUrl = null;

  AccessPerson.fromSnapshot(Map<String, dynamic> snapshot)
      : entry = null,
        employee = null,
        planName = snapshot['plan_name']?.toString(),
        _snapshotId = snapshot['member_id']?.toString() ?? snapshot['id']?.toString(),
        _snapshotName = snapshot['name']?.toString(),
        _snapshotFirstName = snapshot['first_name']?.toString() ??
            (snapshot['name']?.toString().split(' ').firstOrNull),
        _snapshotIsEmployee = snapshot['is_employee'] == true,
        _snapshotAllowed = snapshot['allowed'] != false,
        _snapshotReason = snapshot['reason']?.toString() ?? 'ok',
        _snapshotDaysLeft = (snapshot['days_left'] as num?)?.toInt(),
        _snapshotEndDate = snapshot['end_date'] != null
            ? DateTime.tryParse(snapshot['end_date'].toString())
            : null,
        _snapshotPhotoUrl = snapshot['photo_url']?.toString();

  final MemberListEntry? entry;
  final Employee? employee;
  final String? planName;

  final String? _snapshotId;
  final String? _snapshotName;
  final String? _snapshotFirstName;
  final bool? _snapshotIsEmployee;
  final bool? _snapshotAllowed;
  final String? _snapshotReason;
  final int? _snapshotDaysLeft;
  final DateTime? _snapshotEndDate;
  final String? _snapshotPhotoUrl;

  bool get isEmployee => _snapshotIsEmployee ?? (employee != null);
  String get id => _snapshotId ?? (entry?.member.id ?? employee!.id);
  String get name => _snapshotName ?? (entry?.member.fullName ?? employee!.fullName);
  String get firstName => _snapshotFirstName ?? (entry?.member.firstName ?? employee!.firstName);
  bool get allowed => _snapshotAllowed ?? (isEmployee ? employee!.active : entry!.validity.valid);
  String get reason => _snapshotReason ?? (isEmployee ? (employee!.active ? 'ok' : 'suspended') : entry!.validity.reason);
  int? get daysLeft => _snapshotDaysLeft ?? entry?.validity.daysLeft;
  DateTime? get endDate => _snapshotEndDate ?? entry?.validity.endDate;
  String? get photoUrl => _snapshotPhotoUrl ?? entry?.member.photoUrl;
}

class AccessDecision {
  const AccessDecision(this.outcome, {this.person, this.openedByApp = false, this.uid, this.code = 0});
  final AccessOutcome outcome;
  final AccessPerson? person;
  final bool openedByApp;
  final String? uid;
  final int code;
}

class TerminalSyncResult {
  const TerminalSyncResult({
    required this.ok,
    this.enrolled = 0,
    this.removed = 0,
    this.skipped = 0,
    this.withoutFingerprint = 0,
    this.errors = const [],
  });
  final bool ok;
  final int enrolled;
  final int removed;
  final int skipped;
  final int withoutFingerprint;
  final List<String> errors;
}

/// ID tèminal la: UUID GymDesk san tiret (32 karaktè, limit BS2_USER_ID).
String terminalUid(String id) => id.replaceAll('-', '');

class TerminalAccessService {
  TerminalAccessService(this.client, this.db, this.session, {AccessAgentClient? agent})
      : agent = agent ?? AccessAgentClient();

  final SupabaseClient client;
  final LocalDatabase db;
  final StaffSession session;
  final AccessAgentClient agent;

  // BioStar: 2001-01-01 → 2030-12-31 23:59:59 (valè default yo).
  static const defaultStart = 978307200;
  static const defaultEnd = 1924991999;
  // Dat nan pase a: W2 a idantifye moun nan men li refize (ACCESS_DENIED
  // EXPIRED, ak uid la) — app la ka deside epi ouvri pòt la li menm.
  static const expiredEnd = 978393599;

  static const _authEvents = {0x1000, 0x1100, 0x1300, 0x1400, 0x1600, 0x1700, 0x1800, 0x1900};
  static const _successEvents = {0x1000, 0x1300, 0x1600};

  final Map<String, DateTime> _recent = {};
  Map<String, AccessPerson>? _people;
  DateTime? _peopleAt;

  static Future<TerminalAccessConfig> loadConfig(SupabaseClient client, StaffSession session) async {
    // 1. Priyorite konfigirasyon lokal la (enstantane, 0ms, mache 100% offline san bloke)
    final localSettings = session.settings;
    if (localSettings['biometric_config'] is Map) {
      return TerminalAccessConfig.fromJson(Map<String, dynamic>.from(localSettings['biometric_config'] as Map));
    }
    if (session.gym?['biometric_config'] is Map) {
      return TerminalAccessConfig.fromJson(Map<String, dynamic>.from(session.gym!['biometric_config'] as Map));
    }

    // 2. Si li pa nan sesyon an, chèche nan Supabase ak yon ti timeout rapid (1.5s)
    final gymId = session.gymId;
    if (gymId != null) {
      try {
        final gym = await client
            .from('gyms')
            .select('settings, biometric_config')
            .eq('id', gymId)
            .maybeSingle()
            .timeout(const Duration(milliseconds: 1500));
        if (gym != null) {
          if (gym['settings'] is Map) {
            final s = Map<String, dynamic>.from(gym['settings'] as Map);
            if (s['biometric_config'] is Map) {
              return TerminalAccessConfig.fromJson(Map<String, dynamic>.from(s['biometric_config'] as Map));
            }
          }
          if (gym['biometric_config'] is Map) {
            return TerminalAccessConfig.fromJson(Map<String, dynamic>.from(gym['biometric_config'] as Map));
          }
        }
      } catch (_) {}
    }

    return const TerminalAccessConfig();
  }

  Future<Map<String, AccessPerson>> _loadPeople({bool force = false}) async {
    final cached = _people;
    if (!force && cached != null && _peopleAt != null &&
        DateTime.now().difference(_peopleAt!) < const Duration(seconds: 30)) {
      return cached;
    }
    final entries = await MembersRepository(client, db, session).watch().first;
    final planRows = await db.watchRecords(SyncEntity.plans, limit: 5000).first;
    final plans = {
      for (final r in planRows)
        (jsonDecode(r.payload) as Map)['id'] as String:
            GymPlan(Map<String, dynamic>.from(jsonDecode(r.payload) as Map)).name,
    };
    final employees = await EmployeesRepository(db, session).all();
    final people = <String, AccessPerson>{};

    for (final e in entries) {
      final person = AccessPerson.member(e, planName: plans[e.subscription?.planId]);
      people[terminalUid(e.member.id)] = person;
      people[e.member.id] = person;
      final num = e.member.memberNumber.trim();
      if (num.isNotEmpty) {
        people[num] = person;
        people[num.toLowerCase()] = person;
        final digits = num.replaceAll(RegExp(r'\D'), '');
        if (digits.isNotEmpty) {
          people[digits] = person;
          final intVal = int.tryParse(digits);
          if (intVal != null) {
            people['$intVal'] = person;
          }
        }
      }
      final phone = e.member.phone?.replaceAll(RegExp(r'\D'), '');
      if (phone != null && phone.isNotEmpty) {
        people[phone] = person;
      }
    }

    for (final e in employees) {
      final person = AccessPerson.employee(e);
      people[terminalUid(e.id)] = person;
      people[e.id] = person;
      final phone = e.phone?.replaceAll(RegExp(r'\D'), '');
      if (phone != null && phone.isNotEmpty) {
        people[phone] = person;
      }
    }

    _people = people;
    _peopleAt = DateTime.now();
    return people;
  }

  void invalidate() => _people = null;

  Future<AccessPerson?> resolve(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty || clean == '-') return null;
    final map = await _loadPeople();
    final direct = map[clean] ?? map[clean.toLowerCase()] ?? map[clean.replaceAll('-', '')];
    if (direct != null) return direct;

    // Fallback sou chif sèlman (egz: W2 voye "1" oswa "0001")
    final digits = clean.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty) {
      final byDigits = map[digits];
      if (byDigits != null) return byDigits;
      final intVal = int.tryParse(digits);
      if (intVal != null && map['$intVal'] != null) {
        return map['$intVal'];
      }
    }
    return null;
  }

  int _endOfDayEpoch(DateTime date, int extraDays) {
    final d = date.add(Duration(days: extraDays));
    try {
      final local = tz.TZDateTime(tz.getLocation(session.timezone), d.year, d.month, d.day, 23, 59, 59);
      return local.millisecondsSinceEpoch ~/ 1000;
    } catch (_) {
      return DateTime.utc(d.year, d.month, d.day, 23, 59, 59).millisecondsSinceEpoch ~/ 1000 + 5 * 3600;
    }
  }

  /// Pouse manm + anplwaye ki gen anprent sou W2 a, ak dat aksè yo selon
  /// mòd la. Retire sou tèminal la moun ki pa la ankò (achive, anprent efase).
  Future<TerminalSyncResult> syncToTerminal(TerminalAccessConfig cfg) async {
    final people = await _loadPeople(force: true);
    final grace = ((session.settings['grace_days'] as num?)?.toInt() ?? 0).clamp(0, 365);
    final payload = <Map<String, dynamic>>[];
    var withoutFingerprint = 0;
    for (final entry in people.entries) {
      final person = entry.value;
      final List<List<String>> fingers;
      if (person.isEmployee) {
        final t = person.employee!.fingerprintTemplates;
        fingers = t.isEmpty ? const [] : [t.take(2).toList()];
      } else {
        final row = person.entry!.member.row;
        fingers = [
          for (final key in ['fingerprint_template', 'fingerprint_backup_template'])
            if ((row[key] as String?)?.isNotEmpty == true) [row[key] as String],
        ];
      }
      if (fingers.isEmpty) {
        withoutFingerprint++;
        continue;
      }
      int end;
      if (!cfg.terminalEnforces || !person.allowed) {
        end = expiredEnd;
      } else if (person.isEmployee) {
        end = defaultEnd;
      } else {
        final endDate = person.endDate;
        end = endDate == null ? expiredEnd : _endOfDayEpoch(endDate, grace).clamp(defaultStart + 1, defaultEnd);
      }
      payload.add({
        'id': person.id,
        'name': person.name.length > 48 ? person.name.substring(0, 48) : person.name,
        'start': defaultStart,
        'end': end,
        'fingers': fingers,
      });
    }

    final metaKey = 'terminal_uids:${cfg.terminalIp}';
    final previous = <String>{
      for (final v in (jsonDecode(await db.metadata(metaKey) ?? '[]') as List)) v.toString(),
    };
    final current = {for (final p in payload) terminalUid(p['id'] as String)};
    final remove = previous.difference(current).toList();
    if (payload.isEmpty && remove.isEmpty) {
      return TerminalSyncResult(ok: true, withoutFingerprint: withoutFingerprint);
    }

    final result = await agent.syncTerminalMembers(payload, terminalIp: cfg.terminalIp, remove: remove);
    final ok = result?['success'] == true;
    final skipped = [for (final s in (result?['skipped'] as List? ?? const [])) s.toString()];
    if (ok) {
      await db.setMetadata(metaKey, jsonEncode(current.difference(skipped.toSet()).toList()..sort()));
    }
    return TerminalSyncResult(
      ok: ok,
      enrolled: (result?['enrolled'] as num?)?.toInt() ?? 0,
      removed: (result?['removed'] as num?)?.toInt() ?? 0,
      skipped: skipped.length,
      withoutFingerprint: withoutFingerprint,
      errors: [
        for (final e in (result?['errors'] as List? ?? const [])) e.toString(),
        if (result == null) 'agent_offline',
      ],
    );
  }

  /// Pibliye evènman aksè a sou Supabase Realtime (tablo `access_events`)
  /// pou tout aparèy (tablèt Wi-Fi, lòt ekran) resevwa l an tan reyèl.
  Future<void> recordAccessEvent({
    required AccessDecision decision,
    String source = 'terminal',
  }) async {
    final gymId = session.gymId;
    if (gymId == null) return;
    try {
      final isGranted = decision.outcome == AccessOutcome.granted || decision.outcome == AccessOutcome.legacy;
      final person = decision.person;
      final member = person?.entry?.member;

      String eventType;
      if (isGranted) {
        eventType = 'granted';
      } else {
        final reason = person?.reason ?? '';
        if (reason == 'expired') {
          eventType = 'denied_expired';
        } else if (reason == 'suspended') {
          eventType = 'denied_suspended';
        } else if (reason == 'no_subscription') {
          eventType = 'denied_no_subscription';
        } else {
          eventType = 'denied_unknown';
        }
      }

      final snapshot = <String, dynamic>{
        'name': person?.name ??
            (decision.outcome == AccessOutcome.legacy
                ? (decision.uid != null && decision.uid!.isNotEmpty && decision.uid != '-'
                    ? 'Manm BioStar #${decision.uid}'
                    : 'Itilizatè BioStar (Ansyen)')
                : 'Anprent pa rekonèt'),
        'is_employee': person?.isEmployee ?? false,
        'allowed': person?.allowed ?? isGranted,
        'reason': person?.reason ??
            (isGranted
                ? 'ok'
                : (decision.outcome == AccessOutcome.legacy ? 'legacy_biostar' : 'unrecognized')),
        if (person?.firstName != null) 'first_name': person!.firstName,
        if (person?.planName != null) 'plan_name': person!.planName,
        if (person?.endDate != null) 'end_date': person!.endDate!.toIso8601String(),
        if (person?.daysLeft != null) 'days_left': person!.daysLeft,
        if (person?.photoUrl != null) 'photo_url': person!.photoUrl,
        if (member?.memberNumber != null) 'member_number': member!.memberNumber,
        if (member?.phone != null) 'phone': member!.phone,
        if (member?.id != null) 'member_id': member!.id,
      };

      // 1. Enskri prezans lan nan SQLite lokal si aksè akòde pou yon manm (mache 100% offline)
      if (member != null && isGranted) {
        try {
          final attendanceRepo = AttendanceRepository(db, session);
          await attendanceRepo.verifyFingerprintAndGrant(
            member: member,
            fingerprintMatched: true,
            scannedAt: DateTime.now(),
            offline: true,
            suspectClock: false,
          );
        } catch (_) {}
      }

      // 2. Voye evènman an sou Supabase Realtime (tablèt Wi-Fi) ak yon kout timeout
      try {
        await client.from('access_events').insert({
          'gym_id': gymId,
          if (member != null) 'member_id': member.id,
          'event_type': eventType,
          'source': source,
          'reason': snapshot['reason'],
          'member_snapshot': snapshot,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
        }).timeout(const Duration(seconds: 3));
      } catch (_) {
        // Pa bloke operasyon aksè si rezo a ralanti oswa offline
      }
    } catch (_) {
      // Pa bloke operasyon aksè si rezo a ralanti
    }
  }

  /// Deside sa pou fè ak yon evènman W2 (via agent la). Retounen null pou
  /// evènman ki pa konsène aksè (pòt, sistèm) oswa doublon.
  Future<AccessDecision?> handleTerminalEvent(Json event, TerminalAccessConfig cfg) async {
    if (event['type'] != 'terminal_event') return null;
    final main = (event['main'] as num?)?.toInt() ?? 0;
    final code = (event['code'] as num?)?.toInt() ?? 0;
    if (!_authEvents.contains(main)) return null;
    final uid = event['uid'] as String?;
    if (uid == null || uid.isEmpty) {
      if (main == 0x1400 || main == 0x1100) {
        final d = AccessDecision(AccessOutcome.unrecognized, code: code);
        unawaited(recordAccessEvent(decision: d, source: 'terminal'));
        return d;
      }
      return null;
    }
    final now = DateTime.now();
    final last = _recent[uid];
    if (last != null && now.difference(last) < const Duration(seconds: 4)) return null;
    _recent[uid] = now;
    _recent.removeWhere((_, t) => now.difference(t) > const Duration(minutes: 1));

    final person = await resolve(uid);
    final terminalOpened = _successEvents.contains(main);
    AccessDecision decision;
    if (person == null) {
      // Ansyen itilizatè BioStar (pa nan GymDesk).
      decision = AccessDecision(terminalOpened ? AccessOutcome.legacy : AccessOutcome.denied, uid: uid, code: code);
    } else if (terminalOpened) {
      decision = AccessDecision(AccessOutcome.granted, person: person, uid: uid, code: code);
    } else if (cfg.appControls && person.allowed) {
      final opened = await agent.pulseTerminalRelay(terminalIp: cfg.terminalIp, seconds: cfg.pulseSeconds);
      decision = AccessDecision(
        opened ? AccessOutcome.granted : AccessOutcome.denied,
        person: person,
        openedByApp: opened,
        uid: uid,
        code: code,
      );
    } else {
      decision = AccessDecision(AccessOutcome.denied, person: person, uid: uid, code: code);
    }

    unawaited(recordAccessEvent(decision: decision, source: 'terminal'));
    return decision;
  }
}
