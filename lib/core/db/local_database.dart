import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import '../sync/sync_models.dart';

part 'local_database.g.dart';

@DriftDatabase(include: {'local_database.drift'})
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase({
    required this.gymId,
    required String userId,
    required String namespace,
  }) : super(
         driftDatabase(
           name:
               'gymdesk_${base64Url.encode(utf8.encode(namespace)).replaceAll('=', '')}_${gymId}_$userId',
           web: DriftWebOptions(
             sqlite3Wasm: Uri.parse('sqlite3.wasm'),
             driftWorker: Uri.parse('drift_worker.dart.js'),
             onResult: (result) {
               // Pèmèt navigatè a travay san li pa voye erè pou bloke aplikasyon an.
             },
           ),
         ),
       );

  LocalDatabase.testing(super.executor, {required this.gymId});
  final String gymId;
  static const _uuid = Uuid();

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await customStatement('CREATE INDEX IF NOT EXISTS badges_number ON records(entity, gym_id, json_extract(payload, \'\$.badge_number\'));');
        await customStatement('CREATE INDEX IF NOT EXISTS badges_token ON records(entity, gym_id, json_extract(payload, \'\$.qr_token\'));');
        await customStatement('CREATE INDEX IF NOT EXISTS badges_status ON records(entity, gym_id, json_extract(payload, \'\$.status\'));');
        await customStatement('CREATE INDEX IF NOT EXISTS member_pins_member ON records(entity, gym_id, json_extract(payload, \'\$.member_id\'));');
      }
    },
  );

  Future<Record?> badgeByToken(String token) async {
    final rows = await (select(records)..where(
      (t) => t.entity.equals(SyncEntity.badges.table) &
             t.gymId.equals(gymId) &
             t.deletedAt.isNull(),
    )).get();
    for (final row in rows) {
      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      if (payload['qr_token'] == token) return row;
    }
    return null;
  }

  Future<Record?> badgeByNumber(int number) async {
    final rows = await (select(records)..where(
      (t) => t.entity.equals(SyncEntity.badges.table) &
             t.gymId.equals(gymId) &
             t.deletedAt.isNull(),
    )).get();
    for (final row in rows) {
      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      if (payload['badge_number'] == number) return row;
    }
    return null;
  }

  Future<Record?> memberPinRecord(String memberId) async {
    final rows = await (select(records)..where(
      (t) => t.entity.equals(SyncEntity.memberPins.table) &
             t.gymId.equals(gymId) &
             t.deletedAt.isNull(),
    )).get();
    for (final row in rows) {
      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      if (payload['member_id'] == memberId) return row;
    }
    return null;
  }

  Future<String?> metadata(String key) async => (await (select(
    syncMetadata,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<int> setMetadata(String key, String value) =>
      into(syncMetadata).insertOnConflictUpdate(
        SyncMetadataCompanion.insert(key: key, value: value),
      );

  Future<String> deviceId() async {
    final existing = await metadata('device_id');
    if (existing != null && existing.isNotEmpty) return existing;
    final value = _uuid.v4();
    await setMetadata('device_id', value);
    return value;
  }

  Future<Record?> record(SyncEntity entity, String id) =>
      (select(records)..where(
            (t) =>
                t.entity.equals(entity.table) &
                t.id.equals(id) &
                t.gymId.equals(gymId),
          ))
          .getSingleOrNull();

  Stream<List<Record>> watchRecords(SyncEntity entity, {int limit = 100}) =>
      (select(records)
            ..where(
              (t) =>
                  t.entity.equals(entity.table) &
                  t.gymId.equals(gymId) &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.id)])
            ..limit(limit))
          .watch();

  Future<void> putRemote(SyncEntity entity, Json data) async {
    if (data['gym_id'] != gymId &&
        !(entity == SyncEntity.gyms && data['id'] == gymId)) {
      throw const SyncRejected('tenant_mismatch');
    }
    await into(records).insertOnConflictUpdate(
      RecordsCompanion.insert(
        entity: entity.table,
        id: data['id'] as String,
        gymId: gymId,
        payload: jsonEncode(data),
        serverVersion: Value(data[entity.cursorField] as String?),
        deletedAt: Value(data['deleted_at'] as String?),
      ),
    );
  }

  Future<void> saveGym(
    Json data, {
    required DateTime changedAt,
    String? baseVersion,
  }) => transaction(() async {
    if (data['id'] != gymId) throw const SyncRejected('tenant_mismatch');
    final previous = await record(SyncEntity.gyms, gymId);
    final serverVersion = previous?.serverVersion ??
        baseVersion ??
        (data['updated_at'] as String?) ??
        changedAt.toUtc().toIso8601String();
    final timestamp = changedAt.toUtc().toIso8601String();
    final row = {...data, 'updated_at': timestamp};
    await into(records).insertOnConflictUpdate(
      RecordsCompanion.insert(
        entity: SyncEntity.gyms.table,
        id: gymId,
        gymId: gymId,
        payload: jsonEncode(row),
        serverVersion: Value(serverVersion),
        deletedAt: Value(row['deleted_at'] as String?),
      ),
    );
    await into(outbox).insert(
      OutboxCompanion.insert(
        id: _uuid.v4(),
        entity: SyncEntity.gyms.table,
        entityId: gymId,
        operation: 'update',
        payload: jsonEncode(row),
        baseVersion: Value(serverVersion),
        changedAt: timestamp,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  });

  Future<void> save(
    SyncEntity entity,
    Json data, {
    required DateTime changedAt,
    bool deleting = false,
  }) => transaction(() async {
    if (!entity.writable || data['gym_id'] != gymId || data['id'] is! String) {
      throw const SyncRejected('invalid_record');
    }
    final previous = await record(entity, data['id'] as String);
    if (entity == SyncEntity.attendance && (previous != null || deleting)) {
      throw const SyncRejected('append_only');
    }
    final timestamp = changedAt.toUtc().toIso8601String();
    final row = {
      ...data,
      if (entity != SyncEntity.attendance) 'updated_at': timestamp,
      if (deleting) 'deleted_at': timestamp,
    };
    await into(records).insertOnConflictUpdate(
      RecordsCompanion.insert(
        entity: entity.table,
        id: data['id'] as String,
        gymId: gymId,
        payload: jsonEncode(row),
        serverVersion: Value(previous?.serverVersion),
        deletedAt: Value(row['deleted_at'] as String?),
      ),
    );
    await into(outbox).insert(
      OutboxCompanion.insert(
        id: _uuid.v4(),
        entity: entity.table,
        entityId: data['id'] as String,
        operation: deleting
            ? 'delete'
            : previous == null
            ? 'insert'
            : 'update',
        payload: jsonEncode(row),
        baseVersion: Value(previous?.serverVersion),
        changedAt: timestamp,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  });

  Future<List<OutboxData>> pending({int limit = 50}) =>
      (select(outbox)
            ..where((t) => t.status.isNotValue('synced'))
            ..orderBy([(t) => OrderingTerm.asc(t.sequence)])
            ..limit(limit))
          .get();

  Stream<List<OutboxData>> watchQueue() =>
      (select(outbox)
            ..where((t) => t.status.isNotValue('synced'))
            ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
          .watch();
  Stream<List<SyncConflict>> watchConflicts() =>
      (select(syncConflicts)..where((t) => t.reviewed.equals(0))).watch();

  Future<void> acknowledge(OutboxData operation, Json? remote, bool conflict) =>
      transaction(() async {
        final entity = SyncEntity.values.singleWhere(
          (e) => e.table == operation.entity,
        );
        if (conflict) {
          await into(syncConflicts).insertOnConflictUpdate(
            SyncConflictsCompanion.insert(
              id: operation.id,
              entity: operation.entity,
              entityId: operation.entityId,
              localPayload: operation.payload,
              serverPayload: jsonEncode(remote),
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );
        }
        await (update(outbox)..where((t) => t.id.equals(operation.id))).write(
          const OutboxCompanion(
            status: Value('synced'),
            lastError: Value(null),
          ),
        );
        final remaining =
            await (select(outbox)..where(
                  (t) =>
                      t.entity.equals(operation.entity) &
                      t.entityId.equals(operation.entityId) &
                      t.status.isNotValue('synced'),
                ))
                .get();
        if (remote != null && remaining.isEmpty) {
          await putRemote(entity, remote);
        } else if (remote != null) {
          for (final next in remaining) {
            final data = jsonDecode(next.payload) as Json;
            if (entity == SyncEntity.members) {
              data['member_number'] = remote['member_number'];
            }
            await (update(outbox)..where((t) => t.id.equals(next.id))).write(
              OutboxCompanion(
                payload: Value(jsonEncode(data)),
                baseVersion: conflict
                    ? const Value.absent()
                    : Value(remote['updated_at'] as String?),
              ),
            );
          }
          final local = await record(entity, operation.entityId);
          if (local != null) {
            final data = jsonDecode(local.payload) as Json;
            if (entity == SyncEntity.members) {
              data['member_number'] = remote['member_number'];
            }
            await (update(records)..where(
                  (t) =>
                      t.entity.equals(operation.entity) &
                      t.id.equals(operation.entityId),
                ))
                .write(
                  RecordsCompanion(
                    payload: Value(jsonEncode(data)),
                    serverVersion: Value(remote['updated_at'] as String?),
                  ),
                );
          }
        }
      });

  Future<void> mergePage(SyncEntity entity, List<Json> rows) =>
      transaction(() async {
        for (final row in rows) {
          final waiting =
              await (select(outbox)
                    ..where(
                      (t) =>
                          t.entity.equals(entity.table) &
                          t.entityId.equals(row['id'] as String) &
                          t.status.isNotValue('synced'),
                    )
                    ..limit(1))
                  .getSingleOrNull();
          if (waiting == null) await putRemote(entity, row);
        }
      });

  Future<int> fail(OutboxData op, String code, {required bool permanent}) =>
      (update(outbox)..where((t) => t.id.equals(op.id))).write(
        OutboxCompanion(
          attempts: Value(op.attempts + 1),
          lastError: Value(code),
          status: Value(permanent ? 'failed' : 'pending'),
          nextAttemptAt: Value(
            DateTime.now()
                .toUtc()
                .add(retryDelay(op.attempts + 1))
                .toIso8601String(),
          ),
        ),
      );

  Future<int> retryFailed() =>
      (update(outbox)..where((t) => t.status.isNotValue('synced'))).write(
        const OutboxCompanion(
          status: Value('pending'),
          nextAttemptAt: Value(null),
          lastError: Value(null),
        ),
      );

  Future<String> nextMemberNumber() async {
    final block =
        await (select(numberBlocks)
              ..where((t) => t.nextValue.isSmallerOrEqual(t.lastValue))
              ..orderBy([(t) => OrderingTerm.asc(t.nextValue)])
              ..limit(1))
            .getSingleOrNull();
    if (block == null) return 'TMP-${_uuid.v4()}';
    await (update(numberBlocks)..where((t) => t.id.equals(block.id))).write(
      NumberBlocksCompanion(nextValue: Value(block.nextValue + 1)),
    );
    return '${block.prefix}${block.nextValue.toString().padLeft(6, '0')}';
  }

  Future<String> consumeMemberNumber() => transaction(nextMemberNumber);

  Future<int> reserveBlock(Json row) => into(numberBlocks).insert(
    NumberBlocksCompanion.insert(
      id: _uuid.v4(),
      prefix: row['prefix'] as String,
      nextValue: row['seq_first'] as int,
      lastValue: row['seq_last'] as int,
    ),
  );

  Future<int> availableNumbers() async {
    final blocks = await select(numberBlocks).get();
    return blocks.fold<int>(
      0,
      (total, b) => total + (b.lastValue - b.nextValue + 1).clamp(0, 500),
    );
  }

  Future<void> enqueuePhoto(String memberId, Uint8List jpeg) async {
    if (jpeg.length > 5 * 1024 * 1024 ||
        jpeg.length < 3 ||
        jpeg[0] != 0xff ||
        jpeg[1] != 0xd8) {
      throw const SyncRejected('invalid_photo');
    }
    await (delete(
      photoUploads,
    )..where((t) => t.memberId.equals(memberId))).go();
    final id = _uuid.v4();
    await into(photoUploads).insert(
      PhotoUploadsCompanion.insert(
        id: id,
        memberId: memberId,
        objectPath: '$gymId/$memberId/$id.jpg',
        bytes: jpeg,
      ),
    );
  }

  Future<PhotoUpload?> photoForMember(String memberId) => (select(
    photoUploads,
  )..where((t) => t.memberId.equals(memberId))).getSingleOrNull();

  Future<void> purgeSyncedPayments() async {
    await customUpdate(
      "DELETE FROM records WHERE entity = 'payments' AND NOT EXISTS (SELECT 1 FROM outbox WHERE outbox.entity = records.entity AND outbox.entity_id = records.id AND outbox.status != 'synced')",
      updates: {records},
      updateKind: UpdateKind.delete,
    );
  }
}
