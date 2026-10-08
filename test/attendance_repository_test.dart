import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/db/local_database.dart';
import 'package:gym_desk/core/sync/sync_models.dart';
import 'package:gym_desk/features/attendance/data/attendance_repository.dart';
import 'package:gym_desk/features/attendance/domain/attendance_entry.dart';
import 'package:gym_desk/features/members/data/member_pin_service.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  const gymId = '10000000-0000-4000-8000-000000000001';
  const memberId = '20000000-0000-4000-8000-000000000001';
  const subscriptionId = '30000000-0000-4000-8000-000000000001';
  const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const pin = '4826';
  final now = DateTime.utc(2026, 1, 15, 12);
  final session = StaffSession(
    staff: {
      'id': 'staff-1',
      'user_id': 'user-1',
      'role': 'reception',
      'active': true,
    },
    gym: {
      'id': gymId,
      'code': 'PWR',
      'status': 'active',
      'timezone': 'America/Port-au-Prince',
      'settings': {'entry_duplicate_seconds': 3, 'allow_access_pending': false},
    },
    verifiedAt: now,
  );
  final qr = 'GD1|PWR|PWR-000001|$token';
  late LocalDatabase db;
  late AttendanceRepository repository;

  Json memberRow() => {
    'id': memberId,
    'gym_id': gymId,
    'member_number': 'PWR-000001',
    'qr_token': token,
    'first_name': 'Marie',
    'last_name': 'Jean',
    'status': 'active',
    'updated_at': now.toIso8601String(),
  };
  Json subscriptionRow({String status = 'active', String end = '2026-01-31'}) =>
      {
        'id': subscriptionId,
        'gym_id': gymId,
        'member_id': memberId,
        'start_date': '2026-01-01',
        'end_date': end,
        'price': 1000,
        'status': status,
        'updated_at': now.toIso8601String(),
      };

  Future<ScanOutcome> scan(
    String raw, {
    required DateTime scannedAt,
    bool offline = false,
  }) async {
    final lookup = await repository.resolveBadge(raw);
    if (lookup.requiresPin) {
      return repository.verifyPinAndGrant(
        badgeResult: lookup,
        pin: pin,
        scannedAt: scannedAt,
        offline: offline,
        suspectClock: false,
      );
    }
    return repository.logImmediateDenial(
      lookup,
      scannedAt: scannedAt,
      offline: offline,
      suspectClock: false,
    );
  }

  setUpAll(tz.initializeTimeZones);
  setUp(() async {
    db = LocalDatabase.testing(NativeDatabase.memory(), gymId: gymId);
    repository = AttendanceRepository(db, session);
    final pins = MemberPinService(db, now: () => now);
    await pins.savePinData(await pins.createPinData(memberId, gymId, pin));
  });
  tearDown(() => db.close());

  test(
    'valid QR grants entry and stores an append-only attendance row',
    () async {
      await db.save(SyncEntity.members, memberRow(), changedAt: now);
      await db.save(
        SyncEntity.subscriptions,
        subscriptionRow(),
        changedAt: now,
      );
      final outcome = await scan(qr, scannedAt: now, offline: true);
      expect(outcome.result, 'granted');
      expect(outcome.entry!.entryNumberToday, 1);
      final saved = AttendanceEntry(
        jsonDecode(
              (await db.record(
                SyncEntity.attendance,
                outcome.entry!.id,
              ))!.payload,
            )
            as Json,
      );
      expect(saved.memberId, memberId);
      expect(saved.subscriptionId, subscriptionId);
      expect(saved.wasOffline, isTrue);
      expect(
        (await db.pending()).where((entry) => entry.entity == 'attendance'),
        hasLength(1),
      );
    },
  );

  test(
    'duplicate window records a denied_duplicate observation without another granted entry',
    () async {
      await db.save(SyncEntity.members, memberRow(), changedAt: now);
      await db.save(
        SyncEntity.subscriptions,
        subscriptionRow(),
        changedAt: now,
      );
      await scan(qr, scannedAt: now);
      final second = await scan(
        qr,
        scannedAt: now.add(const Duration(seconds: 2)),
      );
      expect(second.result, 'duplicate');
      expect(second.entry!.result, 'denied_duplicate');
      expect(
        (await db.watchRecords(SyncEntity.attendance).first).where(
          (entry) => jsonDecode(entry.payload)['result'] == 'granted',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'pending and expired subscriptions produce the corresponding denial',
    () async {
      await db.save(SyncEntity.members, memberRow(), changedAt: now);
      await db.save(
        SyncEntity.subscriptions,
        subscriptionRow(status: 'pending'),
        changedAt: now,
      );
      final pending = await scan(qr, scannedAt: now);
      expect(pending.result, 'denied_pending_renewal');
      await db.save(
        SyncEntity.subscriptions,
        subscriptionRow(end: '2026-01-14'),
        changedAt: now,
      );
      final expired = await scan(
        qr,
        scannedAt: now.add(const Duration(days: 1)),
      );
      expect(expired.result, 'denied_expired');
    },
  );

  test(
    'wrong gym or token is stored as denied_unknown without a member link',
    () async {
      final outcome = await scan(
        'GD1|OTH|PWR-000001|$token',
        scannedAt: now,
      );
      expect(outcome.result, 'denied_unknown');
      expect(outcome.entry!.memberId, isNull);
      expect(outcome.entry!.denialReason, 'scan_denied_other_gym');
    },
  );

  test('bad PIN is denied and a wrong QR does not leak member info', () async {
    await db.save(SyncEntity.members, memberRow(), changedAt: now);
    await db.save(
      SyncEntity.subscriptions,
      subscriptionRow(),
      changedAt: now,
    );
    final lookup = await repository.resolveBadge(qr);
    expect(lookup.requiresPin, isTrue);
    final denied = await repository.verifyPinAndGrant(
      badgeResult: lookup,
      pin: '9050',
      scannedAt: now,
      offline: false,
      suspectClock: false,
    );
    expect(denied.result, 'denied_bad_pin');
    expect(denied.entry!.denialReason, isNotNull);
  });
}
