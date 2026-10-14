import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/access_control/terminal_access_service.dart';
import 'package:gym_desk/core/biometrics/access_agent_client.dart';
import 'package:gym_desk/core/db/local_database.dart';
import 'package:gym_desk/core/sync/sync_models.dart';
import 'package:gym_desk/features/employees/data/employees_repository.dart';
import 'package:gym_desk/features/employees/domain/employee.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;

class _FakeAgent extends AccessAgentClient {
  List<Map<String, dynamic>>? synced;
  List<String>? removed;
  int pulses = 0;

  @override
  Future<Map<String, dynamic>?> syncTerminalMembers(
    List<Map<String, dynamic>> members, {
    String? terminalIp,
    List<String> remove = const [],
  }) async {
    synced = members;
    removed = remove;
    return {'success': true, 'enrolled': members.length, 'removed': remove.length, 'skipped': <String>[], 'errors': <String>[]};
  }

  @override
  Future<bool> pulseTerminalRelay({String? terminalIp, int seconds = 3}) async {
    pulses++;
    return true;
  }
}

void main() {
  const gymId = '10000000-0000-4000-8000-000000000001';
  const valid = '20000000-0000-4000-8000-00000000000a';
  const expired = '20000000-0000-4000-8000-00000000000b';
  const noFinger = '20000000-0000-4000-8000-00000000000c';
  const coach = '50000000-0000-4000-8000-00000000000a';
  const cleaner = '50000000-0000-4000-8000-00000000000b';
  final today = DateTime.now().toUtc();
  String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
  final session = StaffSession(
    staff: {'id': 'staff-1', 'user_id': 'user-1', 'role': 'owner', 'active': true},
    gym: {
      'id': gymId,
      'name': 'PWR',
      'status': 'active',
      'timezone': 'America/Port-au-Prince',
      'settings': <String, dynamic>{'grace_days': 0},
    },
    verifiedAt: today,
  );
  late LocalDatabase db;
  late _FakeAgent agent;
  late TerminalAccessService service;

  Future<void> member(String id, String first, {String? fp, DateTime? end}) async {
    await db.putRemote(SyncEntity.members, {
      'id': id,
      'gym_id': gymId,
      'member_number': first,
      'first_name': first,
      'last_name': 'Test',
      'status': 'active',
      'fingerprint_template': fp,
      'updated_at': today.toIso8601String(),
    });
    if (end != null) {
      await db.putRemote(SyncEntity.subscriptions, {
        'id': '3${id.substring(1)}',
        'gym_id': gymId,
        'member_id': id,
        'plan_id': null,
        'start_date': ymd(end.subtract(const Duration(days: 29))),
        'end_date': ymd(end),
        'price': 1000,
        'status': 'active',
        'updated_at': today.toIso8601String(),
      });
    }
  }

  setUpAll(tz.initializeTimeZones);
  setUp(() async {
    db = LocalDatabase.testing(NativeDatabase.memory(), gymId: gymId);
    agent = _FakeAgent();
    service = TerminalAccessService(SupabaseClient('https://example.supabase.co', 'anon'), db, session, agent: agent);
    await member(valid, 'Valid', fp: 'TPL-A', end: today.add(const Duration(days: 10)));
    await member(expired, 'Late', fp: 'TPL-B', end: today.subtract(const Duration(days: 3)));
    await member(noFinger, 'NoFp', end: today.add(const Duration(days: 10)));
    await db.putRemote(SyncEntity.employees, {
      'id': coach, 'gym_id': gymId, 'first_name': 'Coach', 'last_name': 'One', 'job_type': 'coach', 'active': true,
      'fingerprint_templates': ['E1', 'E2'], 'updated_at': today.toIso8601String(),
    });
    await db.putRemote(SyncEntity.employees, {
      'id': cleaner, 'gym_id': gymId, 'first_name': 'Clean', 'last_name': 'Two', 'job_type': 'cleaning', 'active': false,
      'fingerprint_template': 'E3', 'updated_at': today.toIso8601String(),
    });
  });
  tearDown(() => db.close());

  Map<String, dynamic> sent(String id) => agent.synced!.firstWhere((m) => m['id'] == id);

  test('config: at least one mode is always on, terminal enforcement is the default', () {
    expect(TerminalAccessConfig.fromJson({}).terminalEnforces, isTrue);
    expect(TerminalAccessConfig.fromJson({}).appControls, isFalse);
    final appOnly = TerminalAccessConfig.fromJson({'terminal_enforces_expiry': false, 'app_controls_door': true});
    expect((appOnly.terminalEnforces, appOnly.appControls), (false, true));
    expect(TerminalAccessConfig.fromJson({'terminal_enforces_expiry': false}).terminalEnforces, isTrue);
  });

  test('terminal mode: W2 gets the real end date, unpaid and suspended people get an expired date', () async {
    final result = await service.syncToTerminal(const TerminalAccessConfig());
    expect(result.ok, isTrue);
    expect(result.withoutFingerprint, 1);
    expect(agent.synced!.map((m) => m['id']), unorderedEquals([valid, expired, coach, cleaner]));

    final end = sent(valid)['end'] as int;
    final expectedDay = today.add(const Duration(days: 10));
    final endUtc = DateTime.fromMillisecondsSinceEpoch(end * 1000, isUtc: true);
    // 23:59:59 Port-au-Prince = 03:59:59 / 04:59:59 UTC the next day
    expect(endUtc.difference(DateTime.utc(expectedDay.year, expectedDay.month, expectedDay.day)).inHours, inInclusiveRange(27, 28));
    expect(sent(expired)['end'], TerminalAccessService.expiredEnd);
    expect(sent(coach)['end'], TerminalAccessService.defaultEnd);
    expect(sent(cleaner)['end'], TerminalAccessService.expiredEnd);
    expect(sent(coach)['fingers'], [['E1', 'E2']]);
    expect(sent(valid)['fingers'], [['TPL-A']]);
    expect(sent(valid)['start'], TerminalAccessService.defaultStart);
  });

  test('app-only mode: the W2 only identifies, every person gets an expired date', () async {
    await service.syncToTerminal(const TerminalAccessConfig(terminalEnforces: false, appControls: true));
    expect(agent.synced!.every((m) => m['end'] == TerminalAccessService.expiredEnd), isTrue);
  });

  test('archived employees are removed from the terminal on the next sync', () async {
    await service.syncToTerminal(const TerminalAccessConfig());
    expect(agent.removed, isEmpty);
    final repo = EmployeesRepository(db, session);
    final employee = (await repo.all()).firstWhere((e) => e.id == coach);
    await repo.archive(employee);
    await service.syncToTerminal(const TerminalAccessConfig());
    expect(agent.removed, [terminalUid(coach)]);
    expect(agent.synced!.any((m) => m['id'] == coach), isFalse);
  });

  Map<String, dynamic> evt(int code, String? uid) =>
      {'type': 'terminal_event', 'code': code, 'main': code & 0xFF00, 'sub': code & 0xFF, 'uid': uid};

  test('terminal events: welcome, app override for renewals, refusals, legacy and unknown fingers', () async {
    const appMode = TerminalAccessConfig(appControls: true);
    final opened = await service.handleTerminalEvent(evt(0x1301, terminalUid(valid)), appMode);
    expect(opened!.outcome, AccessOutcome.granted);
    expect(opened.person!.firstName, 'Valid');
    expect(opened.openedByApp, isFalse);
    expect(agent.pulses, 0);

    // W2 refused (old date on the terminal) but the app knows the member paid
    final override = await service.handleTerminalEvent(evt(0x1903, terminalUid(coach)), appMode);
    expect(override!.outcome, AccessOutcome.granted);
    expect(override.openedByApp, isTrue);
    expect(agent.pulses, 1);

    final late = await service.handleTerminalEvent(evt(0x1903, terminalUid(expired)), appMode);
    expect(late!.outcome, AccessOutcome.denied);
    expect(late.person!.reason, 'expired');
    expect(agent.pulses, 1);

    final terminalOnly = await service.handleTerminalEvent(evt(0x1903, terminalUid(noFinger)), const TerminalAccessConfig());
    expect(terminalOnly!.outcome, AccessOutcome.denied);
    expect(agent.pulses, 1);

    expect((await service.handleTerminalEvent(evt(0x1301, '484224483'), appMode))!.outcome, AccessOutcome.legacy);
    expect((await service.handleTerminalEvent(evt(0x1404, null), appMode))!.outcome, AccessOutcome.unrecognized);
    expect(await service.handleTerminalEvent(evt(0x5000, null), appMode), isNull);
    // Same person within a few seconds: ignored (W2 can emit several events)
    expect(await service.handleTerminalEvent(evt(0x1301, terminalUid(valid)), appMode), isNull);
  });

  test('employee fingerprints keep two distinct captures for the W2', () async {
    final repo = EmployeesRepository(db, session);
    final cleanerRow = (await repo.all()).firstWhere((e) => e.id == cleaner);
    await repo.saveFingerprints(cleanerRow, ['C1', 'C2', 'C3']);
    final updated = (await repo.all()).firstWhere((e) => e.id == cleaner);
    expect(updated.fingerprintTemplates, ['C3', 'C1']);
    expect(Employee.jobTypes, contains(updated.jobType));
  });
}
