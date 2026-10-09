import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/local_database.dart';
import 'clock_guard.dart';
import 'sync_models.dart';
import 'sync_remote.dart';

class SyncEngine {
  SyncEngine({
    required this.db,
    required this.remote,
    required this.session,
    required this.onSession,
    ClockGuard? clock,
  }) : clock = clock ?? ClockGuard();

  final LocalDatabase db;
  final SyncRemote remote;
  final ClockGuard clock;
  final Future<void> Function(StaffSession) onSession;
  StaffSession session;
  final state = ValueNotifier(const SyncState());
  StreamSubscription<List<ConnectivityResult>>? _network;
  StreamSubscription<List<OutboxData>>? _queue;
  StreamSubscription<List<SyncConflict>>? _conflicts;
  StreamSubscription<List<PhotoUpload>>? _photos;
  int _photoCount = 0;
  Timer? _timer;
  Timer? _debounce;
  Future<void>? _inFlight;
  bool _closed = false;
  bool _initialized = false;
  bool _connected = true;
  int _pending = 0;
  int _failed = 0;
  int _conflictCount = 0;
  double _progress = 0;
  DateTime? _lastSync;

  bool get canWork =>
      !_closed &&
      _initialized &&
      session.offlineAllowed(clock.correctedNow) &&
      state.value.phase != SyncPhase.blocked;

  void _emit(SyncPhase phase, [String? code]) {
    if (_closed) return;
    state.value = SyncState(
      phase: phase,
      pending: _pending + _photoCount,
      failed: _failed,
      conflicts: _conflictCount,
      initialized: _initialized,
      progress: _progress,
      lastSync: _lastSync,
      clockSuspect: clock.suspect,
      errorCode: code,
    );
  }

  Future<void> start() async {
    _initialized = await db.metadata('initialized') == 'true';
    _lastSync = DateTime.tryParse(await db.metadata('last_sync') ?? '');
    final offset =
        int.tryParse(await db.metadata('clock_offset_ms') ?? '') ?? 0;
    clock.restore(
      Duration(milliseconds: offset),
      DateTime.tryParse(await db.metadata('last_wall') ?? '') ??
          DateTime.now().toUtc(),
    );
    _queue = db.watchQueue().listen((rows) {
      _pending = rows.where((r) => r.status == 'pending').length;
      _failed = rows.where((r) => r.status == 'failed').length;
      _emit(state.value.phase, state.value.errorCode);
    });
    _conflicts = db.watchConflicts().listen((rows) {
      _conflictCount = rows.length;
      _emit(state.value.phase, state.value.errorCode);
    });
    _photos = db.select(db.photoUploads).watch().listen((rows) {
      _photoCount = rows.length;
      _emit(state.value.phase, state.value.errorCode);
    });
    _network = Connectivity().onConnectivityChanged.listen((results) {
      _connected = !results.contains(ConnectivityResult.none);
      if (_connected) {
        unawaited(synchronize());
      } else {
        _emit(SyncPhase.offline);
      }
    });
    remote.listen(db.gymId, () {
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 500),
        () => unawaited(synchronize()),
      );
    });
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!session.offlineAllowed(clock.correctedNow)) {
        _emit(SyncPhase.blocked, 'offline_expired');
      }
      if (_connected) unawaited(synchronize());
    });
    // Si baz lokal la deja inisyalize (nou gen done), nou pa bezwen bloke UI a
    // pandan sync la ap fèt; nou lanse l nan background imedyatman.
    // Si se premye fwa nèt, nou fè l rapidman.
    final hasData = (await db.metadata('initialized')) == 'true';
    if (hasData) {
      unawaited(synchronize(full: false));
    } else {
      await synchronize(full: true);
    }
  }

  Future<void> synchronize({bool full = false, bool retry = false}) {
    if (_closed) return Future.value();
    return _inFlight ??= _run(
      full: full,
      retry: retry,
    ).whenComplete(() => _inFlight = null);
  }

  Future<void> _run({required bool full, required bool retry}) async {
    _emit(SyncPhase.running);
    try {
      final started = DateTime.now().toUtc();
      final context = await remote.context();
      final ended = DateTime.now().toUtc();
      final serverTime = DateTime.parse(context['server_time'] as String);
      clock.calibrate(serverTime, started, ended);
      final fresh = StaffSession(
        staff: Map<String, dynamic>.from(context['staff'] as Map),
        gym: context['gym'] == null
            ? null
            : Map<String, dynamic>.from(context['gym'] as Map),
        verifiedAt: serverTime,
      );
      if (fresh.userId != session.userId ||
          fresh.gymId != db.gymId ||
          fresh.role != session.role) {
        throw const SyncRejected('access_changed');
      }
      session = fresh;
      await onSession(fresh);
      if (!fresh.active) throw const SyncRejected('gym_suspended');
      await db.putRemote(SyncEntity.gyms, fresh.gym!);
      await db.setMetadata(
        'clock_offset_ms',
        clock.offset.inMilliseconds.toString(),
      );
      await db.setMetadata('last_wall', ended.toIso8601String());
      if (retry) await db.retryFailed();
      SyncRejected? pushError;
      try {
        pushError = await _push(retry: retry);
        await _uploadPhotos();
        final secondPushError = await _push(retry: retry);
        pushError ??= secondPushError;
      } on SyncRejected catch (e) {
        if ({
          'access_changed',
          'session_expired',
          'gym_suspended',
        }.contains(e.code)) {
          rethrow;
        }
        pushError = e;
      }
      if (pushError?.code == 'network') {
        _emit(SyncPhase.offline, 'network');
        return;
      }
      final lastFull = DateTime.tryParse(await db.metadata('last_full') ?? '');
      final reconcile =
          full ||
          lastFull == null ||
          serverTime.difference(lastFull) > const Duration(days: 1);
      final entities = SyncEntity.values
          .where(
            (e) =>
                e != SyncEntity.gyms &&
                (e != SyncEntity.auditLog || fresh.role == 'owner') &&
                (e != SyncEntity.paymentDeclarations || fresh.isOwner) &&
                (e != SyncEntity.platformInvoices || fresh.isOwner),
          )
          .toList();
      for (var i = 0; i < entities.length && !_closed; i++) {
        final entity = entities[i];
        final paymentSnapshot =
            entity == SyncEntity.payments && fresh.role == 'reception';
        if (paymentSnapshot) await db.purgeSyncedPayments();
        await _pull(entity, serverTime, full: reconcile || paymentSnapshot);
        _progress = (i + 1) / entities.length;
        _emit(SyncPhase.running);
      }
      if (_closed) return;
      try {
        if (await db.availableNumbers() < 10) {
          await db.reserveBlock(await remote.reserveNumbers(db.gymId));
        }
      } catch (_) {}
      await db.setMetadata('initialized', 'true');
      await db.setMetadata('last_sync', serverTime.toIso8601String());
      if (reconcile) {
        await db.setMetadata('last_full', serverTime.toIso8601String());
      }
      _initialized = true;
      _lastSync = serverTime;
      _connected = true;
      _emit(
        pushError == null
            ? SyncPhase.idle
            : pushError.code == 'network'
            ? SyncPhase.offline
            : SyncPhase.error,
        pushError?.code,
      );
    } on SyncRejected catch (e) {
      if (_closed) return;
      final blocked = {
        'access_changed',
        'gym_suspended',
      }.contains(e.code);
      if (blocked) {
        await db.setMetadata('initialized', 'false');
        _initialized = false;
      }
      _emit(
        blocked
            ? SyncPhase.blocked
            : e.code == 'network'
            ? SyncPhase.offline
            : SyncPhase.error,
        e.code,
      );
    } catch (_) {
      _emit(SyncPhase.error, 'local_storage');
    }
  }

  Future<SyncRejected?> _push({bool retry = false}) async {
    SyncRejected? firstError;
    final failedEntityIds = <String>{};

    while (!_closed) {
      final batch = await db.pending();
      if (batch.isEmpty) break;

      var processedCount = 0;
      for (final snapshot in batch) {
        if (_closed) return firstError;
        final op = await (db.select(
          db.outbox,
        )..where((t) => t.id.equals(snapshot.id))).getSingleOrNull();

        if (op == null) continue;
        if (op.status == 'failed') {
          return const SyncRejected('queue_blocked');
        }
        if (op.status != 'pending') continue;

        // Si yon operasyon paran sou menm antite a te deja echwe nan pase sa a, sote li pou kounye a
        if (failedEntityIds.contains(op.entityId)) continue;

        final next = DateTime.tryParse(op.nextAttemptAt ?? '');
        if (!retry && next != null && next.isAfter(DateTime.now().toUtc())) {
          // Nan delè backoff: sote operasyon sa a pou kounye a
          continue;
        }

        try {
          final result = await remote.push({
            'p_operation': op.id,
            'p_entity': op.entity,
            'p_payload': jsonDecode(op.payload),
            'p_changed_at': op.changedAt,
            'p_base_version': op.baseVersion,
          });
          await db.acknowledge(
            op,
            result['row'] == null
                ? null
                : Map<String, dynamic>.from(result['row'] as Map),
            result['outcome'] == 'conflict',
          );
          processedCount++;
        } on SyncRejected catch (e) {
          if (e.code == 'network') {
            await db.fail(op, e.code, permanent: false);
            return e;
          }
          if (e.code == 'session_expired') {
            await db.fail(op, e.code, permanent: false);
            rethrow;
          }

          // Echèk sou yon sèl liy (doublon, fòma, pèmisyon): izole li nan Dead-Letter Queue san bloke rès la!
          await db.fail(op, e.code, permanent: e.permanent || op.attempts >= 5);
          failedEntityIds.add(op.entityId);
          firstError ??= e;
          processedCount++;
        } catch (_) {
          await db.fail(op, 'invalid_record', permanent: true);
          failedEntityIds.add(op.entityId);
          firstError ??= const SyncRejected('invalid_record');
          processedCount++;
        }
      }

      // Si okenn operasyon pa trete (tout sa ki rete yo nan backoff oswa depandans), kanpe bouk la
      if (processedCount == 0) break;
    }

    return firstError;
  }

  Future<void> _pull(
    SyncEntity entity,
    DateTime until, {
    required bool full,
  }) async {
    final saved = full
        ? null
        : DateTime.tryParse(await db.metadata('cursor:${entity.table}') ?? '');
    final since =
        saved?.subtract(const Duration(minutes: 10)) ?? DateTime.utc(1970);
    String? afterTime;
    String? afterId;
    while (!_closed) {
      final rows = await remote.pull(
        entity,
        since,
        until,
        afterTime: afterTime,
        afterId: afterId,
      );
      await db.mergePage(entity, rows);
      if (rows.length < 250) break;
      afterTime = rows.last[entity.cursorField] as String;
      afterId = rows.last['id'] as String;
    }
    if (!_closed) {
      await db.setMetadata('cursor:${entity.table}', until.toIso8601String());
    }
  }

  Future<void> _uploadPhotos() async {
    final uploads = await db.select(db.photoUploads).get();
    for (final photo in uploads) {
      if (_closed) return;
      final next = DateTime.tryParse(photo.nextAttemptAt ?? '');
      if (next != null && next.isAfter(DateTime.now().toUtc())) continue;
      try {
        final member = await db.record(SyncEntity.members, photo.memberId);
        if (member == null) continue;
        await remote.uploadPhoto(photo.objectPath, photo.bytes);
        await db.transaction(() async {
          final current = await db.record(SyncEntity.members, photo.memberId);
          if (current != null) {
            await db.save(SyncEntity.members, {
              ...(jsonDecode(current.payload) as Json),
              'photo_url': photo.objectPath,
            }, changedAt: clock.correctedNow);
          }
          await (db.delete(
            db.photoUploads,
          )..where((t) => t.id.equals(photo.id))).go();
        });
      } on SyncRejected catch (e) {
        await (db.update(
          db.photoUploads,
        )..where((t) => t.id.equals(photo.id))).write(
          PhotoUploadsCompanion(
            attempts: Value(photo.attempts + 1),
            lastError: Value(e.code),
            nextAttemptAt: Value(
              DateTime.now()
                  .toUtc()
                  .add(retryDelay(photo.attempts + 1))
                  .toIso8601String(),
            ),
          ),
        );
        if (e.code == 'network') break;
      } catch (_) {
        // Erè inatandi sou foto a: pase sou lòt foto san crashe tout sync la
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    _debounce?.cancel();
    await _network?.cancel();
    await _queue?.cancel();
    await _conflicts?.cancel();
    await _photos?.cancel();
    await _inFlight;
    await remote.close();
    state.dispose();
  }
}
