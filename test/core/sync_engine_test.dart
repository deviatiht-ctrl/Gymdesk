import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/db/local_database.dart';
import 'package:gym_desk/core/sync/sync_engine.dart';
import 'package:gym_desk/core/sync/sync_models.dart';
import 'package:gym_desk/core/sync/sync_remote.dart';

const _gym = '10000000-0000-4000-8000-000000000001';
const _member = '20000000-0000-4000-8000-000000000001';

class TestRemote implements SyncRemote {
  Json staff = {
    'id': 'staff',
    'user_id': 'user',
    'gym_id': _gym,
    'role': 'owner',
    'active': true,
  };
  String gymStatus = 'active';
  final List<Json> pushes = [];
  final List<SyncEntity> pulls = [];
  final Map<String, Json> receipts = {};
  bool loseNextResponse = false;
  bool networkDown = false;
  Completer<void>? gate;
  int writes = 0;

  @override
  Future<Json> context() async {
    if (networkDown) throw const SyncRejected('network', permanent: false);
    await gate?.future;
    final now = DateTime.now().toUtc().toIso8601String();
    return {
      'server_time': now,
      'staff': staff,
      'gym': {
        'id': _gym,
        'status': gymStatus,
        'name': 'Test',
        'settings': <String, dynamic>{},
        'updated_at': now,
      },
    };
  }

  @override
  Future<Json> push(Json operation) async {
    pushes.add(operation);
    final id = operation['p_operation'] as String;
    if (receipts[id] == null) {
      writes++;
      receipts[id] = {
        'outcome': 'accepted',
        'row': {
          ...(operation['p_payload'] as Json),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      };
    }
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const SyncRejected('network', permanent: false);
    }
    return receipts[id]!;
  }

  @override
  Future<List<Json>> pull(
    SyncEntity entity,
    DateTime since,
    DateTime until, {
    String? afterTime,
    String? afterId,
  }) async {
    pulls.add(entity);
    return [];
  }

  @override
  Future<Json> reserveNumbers(String gymId) async => {
    'prefix': 'TST-',
    'seq_first': 1,
    'seq_last': 50,
  };
  @override
  Future<void> uploadPhoto(String path, Uint8List bytes) async {}
  @override
  void listen(String gymId, void Function() onChange) {}
  @override
  Future<void> close() async {}
}

void main() {
  late LocalDatabase db;
  late TestRemote remote;
  late SyncEngine engine;
  setUp(() {
    db = LocalDatabase.testing(NativeDatabase.memory(), gymId: _gym);
    remote = TestRemote();
    engine = SyncEngine(
      db: db,
      remote: remote,
      session: StaffSession(
        staff: remote.staff,
        gym: {'id': _gym, 'status': 'active'},
        verifiedAt: DateTime.now().toUtc(),
      ),
      onSession: (_) async {},
    );
  });
  tearDown(() async {
    await engine.close();
    await db.close();
  });

  Future<void> createOffline() => db.save(SyncEntity.members, {
    'id': _member,
    'gym_id': _gym,
    'first_name': 'Test',
    'member_number': 'TMP-$_member',
  }, changedAt: DateTime.now().toUtc());

  test(
    'offline registration is pushed before pull and initialization is committed',
    () async {
      await createOffline();
      await engine.synchronize();
      expect(remote.pushes, hasLength(1));
      expect(remote.pulls, contains(SyncEntity.members));
      expect(await db.pending(), isEmpty);
      expect(await db.metadata('initialized'), 'true');
      expect(engine.state.value.phase, SyncPhase.idle);
    },
  );

  test(
    'lost acknowledgement retries the same UUID without a second write',
    () async {
      await createOffline();
      remote.loseNextResponse = true;
      await engine.synchronize();
      expect(await db.pending(), hasLength(1));
      expect(engine.state.value.phase, SyncPhase.offline);
      await engine.synchronize(retry: true);
      expect(remote.pushes, hasLength(2));
      expect(
        remote.pushes.first['p_operation'],
        remote.pushes.last['p_operation'],
      );
      expect(remote.writes, 1);
      expect(await db.pending(), isEmpty);
    },
  );

  test('suspended gym cannot push local changes', () async {
    await createOffline();
    remote.gymStatus = 'suspended';
    await engine.synchronize();
    expect(remote.pushes, isEmpty);
    expect(engine.state.value.phase, SyncPhase.blocked);
    expect(engine.canWork, isFalse);
    expect(await db.pending(), hasLength(1));
  });

  test('overlapping synchronization requests share one flight', () async {
    remote.gate = Completer<void>();
    final a = engine.synchronize();
    final b = engine.synchronize();
    expect(identical(a, b), isTrue);
    remote.gate!.complete();
    await Future.wait([a, b]);
    expect(remote.pulls.where((e) => e == SyncEntity.members), hasLength(1));
  });

  test(
    'initial download is never marked complete on a network error',
    () async {
      remote.networkDown = true;
      await engine.synchronize();
      expect(await db.metadata('initialized'), isNull);
      expect(engine.canWork, isFalse);
      expect(engine.state.value.phase, SyncPhase.offline);
    },
  );

  test(
    'failed operation stops subsequent operations without losing either',
    () async {
      await createOffline();
      final first = (await db.pending()).single;
      await db.fail(first, 'invalid_record', permanent: true);
      await db.save(SyncEntity.plans, {
        'id': 'plan',
        'gym_id': _gym,
        'name': 'Plan',
      }, changedAt: DateTime.now().toUtc());
      await engine.synchronize();
      expect(remote.pushes, isEmpty);
      expect(await db.pending(), hasLength(2));
      expect(engine.state.value.errorCode, 'queue_blocked');
    },
  );

  test('a changed staff role blocks the old local workspace', () async {
    remote.staff = {...remote.staff, 'role': 'reception'};
    await engine.synchronize();
    expect(engine.state.value.errorCode, 'access_changed');
    expect(remote.pulls, isEmpty);
  });
}
