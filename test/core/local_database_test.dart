import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/db/local_database.dart';
import 'package:gym_desk/core/sync/sync_models.dart';

void main() {
  const gym = '10000000-0000-4000-8000-000000000001';
  const member = '20000000-0000-4000-8000-000000000001';
  final now = DateTime.utc(2026, 10, 5, 12);
  Json memberRow({String name = 'Marie'}) => {
    'id': member,
    'gym_id': gym,
    'first_name': name,
    'last_name': 'Test',
    'member_number': 'TMP-$member',
    'qr_token': 'a' * 32,
    'status': 'active',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  };
  late LocalDatabase db;

  setUp(() => db = LocalDatabase.testing(NativeDatabase.memory(), gymId: gym));
  tearDown(() => db.close());

  test('local record and outbox are committed together', () async {
    await db.save(SyncEntity.members, memberRow(), changedAt: now);
    expect(await db.record(SyncEntity.members, member), isNotNull);
    final queue = await db.pending();
    expect(queue.single.operation, 'insert');
    expect(queue.single.status, 'pending');
    expect(queue.single.baseVersion, isNull);
  });

  test('outer registration transaction rolls all operations back', () async {
    await expectLater(
      db.transaction(() async {
        await db.save(SyncEntity.members, memberRow(), changedAt: now);
        throw const SyncRejected('invalid_record');
      }),
      throwsA(isA<SyncRejected>()),
    );
    expect(await db.record(SyncEntity.members, member), isNull);
    expect(await db.pending(), isEmpty);
  });

  test('local tenant mismatch is rejected without mutation', () async {
    await expectLater(
      db.save(SyncEntity.members, {
        ...memberRow(),
        'gym_id': 'other',
      }, changedAt: now),
      throwsA(isA<SyncRejected>()),
    );
    expect(await db.pending(), isEmpty);
  });

  test('gym settings keep server version as optimistic base', () async {
    final gymRow = {
      'id': gym,
      'name': 'SQL Gym',
      'code': 'SQL',
      'status': 'active',
      'timezone': 'America/Port-au-Prince',
      'currency': 'HTG',
      'accent_color': '#1F6F4A',
      'settings': <String, dynamic>{},
      'updated_at': now.toIso8601String(),
    };
    await db.putRemote(SyncEntity.gyms, gymRow);
    await db.saveGym({
      ...gymRow,
      'name': 'Updated Gym',
    }, changedAt: now.add(const Duration(minutes: 1)));
    final op = (await db.pending()).single;
    expect(op.entity, 'gyms');
    expect(op.operation, 'update');
    expect(op.baseVersion, gymRow['updated_at']);
    expect((jsonDecode(op.payload) as Json)['name'], 'Updated Gym');
  });

  test(
    'reserved numbers are consumed once and then fall back to TMP',
    () async {
      await db.reserveBlock({
        'prefix': 'PWR-',
        'seq_first': 124,
        'seq_last': 125,
      });
      expect(await db.consumeMemberNumber(), 'PWR-000124');
      expect(await db.consumeMemberNumber(), 'PWR-000125');
      final provisional = await db.consumeMemberNumber();
      expect(provisional, startsWith('TMP-'));
      expect(await db.consumeMemberNumber(), isNot(provisional));
      expect(await db.availableNumbers(), 0);
    },
  );

  test('numbers beyond six digits are never truncated', () async {
    await db.reserveBlock({
      'prefix': 'PWR-',
      'seq_first': 1000000,
      'seq_last': 1000000,
    });
    expect(await db.consumeMemberNumber(), 'PWR-1000000');
  });

  test('attendance is locally append-only', () async {
    final row = {
      'id': member,
      'gym_id': gym,
      'scanned_at': now.toIso8601String(),
      'result': 'granted',
    };
    await db.save(SyncEntity.attendance, row, changedAt: now);
    await expectLater(
      db.save(SyncEntity.attendance, row, changedAt: now),
      throwsA(isA<SyncRejected>()),
    );
    expect(await db.pending(), hasLength(1));
  });

  test('pull preserves an unsent local edit', () async {
    await db.save(SyncEntity.members, memberRow(name: 'Local'), changedAt: now);
    await db.mergePage(SyncEntity.members, [memberRow(name: 'Server')]);
    final saved = await db.record(SyncEntity.members, member);
    expect((jsonDecode(saved!.payload) as Json)['first_name'], 'Local');
  });

  test('ack does not overwrite an edit made during the request', () async {
    await db.save(SyncEntity.members, memberRow(name: 'First'), changedAt: now);
    final first = (await db.pending()).single;
    await db.save(
      SyncEntity.members,
      memberRow(name: 'Second'),
      changedAt: now.add(const Duration(seconds: 1)),
    );
    final server = {
      ...memberRow(name: 'First'),
      'member_number': 'PWR-000124',
      'updated_at': now.add(const Duration(seconds: 2)).toIso8601String(),
    };
    await db.acknowledge(first, server, false);
    final local =
        jsonDecode((await db.record(SyncEntity.members, member))!.payload)
            as Json;
    expect(local['first_name'], 'Second');
    expect(local['member_number'], 'PWR-000124');
    final pending = (await db.pending()).single;
    expect(pending.baseVersion, server['updated_at']);
    expect(
      (jsonDecode(pending.payload) as Json)['member_number'],
      'PWR-000124',
    );
  });

  test(
    'server winner is stored and the rejected local payload retained',
    () async {
      await db.save(
        SyncEntity.members,
        memberRow(name: 'Local'),
        changedAt: now,
      );
      final op = (await db.pending()).single;
      await db.acknowledge(op, memberRow(name: 'Server'), true);
      expect(await db.pending(), isEmpty);
      expect(
        (jsonDecode((await db.record(SyncEntity.members, member))!.payload)
            as Json)['first_name'],
        'Server',
      );
      final conflict = (await db.select(db.syncConflicts).get()).single;
      expect(
        (jsonDecode(conflict.localPayload) as Json)['first_name'],
        'Local',
      );
    },
  );

  test('conflict does not rebase a second stale operation', () async {
    await db.save(SyncEntity.members, memberRow(), changedAt: now);
    final first = (await db.pending()).single;
    await db.save(
      SyncEntity.members,
      memberRow(name: 'Second'),
      changedAt: now,
    );
    await db.acknowledge(first, memberRow(name: 'Server'), true);
    expect((await db.pending()).single.baseVersion, isNull);
  });

  test('tombstones remain in the mirror but not in visible records', () async {
    await db.mergePage(SyncEntity.members, [
      {...memberRow(), 'deleted_at': now.toIso8601String()},
    ]);
    expect(await db.record(SyncEntity.members, member), isNotNull);
    expect(await db.watchRecords(SyncEntity.members).first, isEmpty);
  });

  test('retry preserves operation identity and payload', () async {
    await db.save(SyncEntity.members, memberRow(), changedAt: now);
    final op = (await db.pending()).single;
    await db.fail(op, 'duplicate', permanent: true);
    expect((await db.pending()).single.status, 'failed');
    await db.retryFailed();
    final retry = (await db.pending()).single;
    expect(retry.id, op.id);
    expect(retry.payload, op.payload);
    expect(retry.status, 'pending');
    expect(retry.attempts, 1);
  });
}
