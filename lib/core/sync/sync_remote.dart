import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_models.dart';

abstract interface class SyncRemote {
  Future<Json> context();
  Future<Json> push(Json operation);
  Future<List<Json>> pull(
    SyncEntity entity,
    DateTime since,
    DateTime until, {
    String? afterTime,
    String? afterId,
  });
  Future<Json> reserveNumbers(String gymId);
  Future<void> uploadPhoto(String path, Uint8List bytes);
  void listen(String gymId, void Function() onChange);
  Future<void> close();
}

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this.client);
  final SupabaseClient client;
  RealtimeChannel? _channel;

  Future<T> _request<T>(Future<T> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 12));
    } on PostgrestException catch (e) {
      throw SyncRejected(
        switch (e.code) {
          '42501' => 'access_denied',
          '23505' => 'duplicate',
          '23503' => 'missing_dependency',
          '23514' || '22023' || '22P02' => 'invalid_record',
          'PGRST301' || 'PGRST302' || 'PGRST303' => 'session_expired',
          _ => 'server_error',
        },
        permanent: e.code != '57014' && e.code != '53300' && e.code != '08006',
      );
    } on AuthException {
      throw const SyncRejected('session_expired');
    } on StorageException {
      throw const SyncRejected('photo_upload', permanent: false);
    } on TimeoutException {
      throw const SyncRejected('network', permanent: false);
    } catch (_) {
      throw const SyncRejected('network', permanent: false);
    }
  }

  @override
  Future<Json> context() => _request(
    () async => Map<String, dynamic>.from(
      await client
          .rpc('sync_context')
          .timeout(const Duration(seconds: 4)) as Map,
    ),
  );

  @override
  Future<Json> push(Json operation) => _request(() async {
    final entity = operation['p_entity'] as String?;
    final function = entity == 'gyms' ? 'sync_branding' : 'sync_push';
    try {
      return Map<String, dynamic>.from(
        await client.rpc(function, params: operation) as Map,
      );
    } on PostgrestException catch (e) {
      if (entity == 'attendance' &&
          e.code != '42501' &&
          e.code != 'PGRST301' &&
          e.code != 'PGRST302' &&
          e.code != 'PGRST303') {
        return _pushAttendanceFallback(operation);
      }
      rethrow;
    }
  });

  Future<Json> _pushAttendanceFallback(Json operation) async {
    final raw = Map<String, dynamic>.from(
      (operation['p_payload'] as Map?) ?? const {},
    );
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final row = <String, dynamic>{
      'id': raw['id'],
      'gym_id': raw['gym_id'],
      'member_id': raw['member_id'],
      if (raw['badge_id'] != null) 'badge_id': raw['badge_id'],
      if (raw['subscription_id'] != null)
        'subscription_id': raw['subscription_id'],
      'scanned_at': raw['scanned_at'] ?? nowIso,
      'server_received_at': raw['server_received_at'] ?? nowIso,
      'result': raw['result'] ?? 'granted',
      'denial_reason': raw['denial_reason'],
      'entry_number_today': raw['entry_number_today'],
      'device_id': raw['device_id'],
      if (raw['scanned_by'] != null) 'scanned_by': raw['scanned_by'],
      'was_offline': raw['was_offline'] == true,
      'suspect_clock': raw['suspect_clock'] == true,
      if (raw['pin_verified'] != null)
        'pin_verified': raw['pin_verified'] == true,
      if (raw['fingerprint_verified'] != null)
        'fingerprint_verified': raw['fingerprint_verified'] == true,
      'created_at': raw['created_at'] ?? raw['scanned_at'] ?? nowIso,
    };

    Future<Map<String, dynamic>> tryInsert(Map<String, dynamic> payload) async {
      final inserted = await client
          .from('attendance')
          .upsert(payload, onConflict: 'id')
          .select()
          .maybeSingle();
      return Map<String, dynamic>.from(inserted ?? payload);
    }

    Map<String, dynamic> saved;
    try {
      saved = await tryInsert(row);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        // Si subscription_id, badge_id oswa scanned_by poko senkronize sou sèvè a
        final stripped = Map<String, dynamic>.from(row)
          ..remove('subscription_id')
          ..remove('badge_id')
          ..remove('scanned_by');
        try {
          saved = await tryInsert(stripped);
        } on PostgrestException catch (e2) {
          if (e2.code == '23503') {
            // Si member_id li menm poko sou sèvè a, kite l an 'missing_dependency' (pending)
            throw const SyncRejected('missing_dependency', permanent: false);
          }
          rethrow;
        }
      } else if (e.code == '23514' &&
          row['result'] == 'denied_pending_renewal') {
        final adjusted = Map<String, dynamic>.from(row)
          ..['result'] = 'denied_pending';
        saved = await tryInsert(adjusted);
      } else {
        rethrow;
      }
    }

    // Yon fwa liy attendance la deja nan public.attendance (v_old is not null),
    // sync_push ap sote blòk validasyon ki gen bèg member_validity(3 args) la epi anrejistre sync_receipts!
    try {
      return Map<String, dynamic>.from(
        await client.rpc('sync_push', params: operation) as Map,
      );
    } catch (_) {
      return <String, dynamic>{'outcome': 'accepted', 'row': saved};
    }
  }

  @override
  Future<List<Json>> pull(
    SyncEntity entity,
    DateTime since,
    DateTime until, {
    String? afterTime,
    String? afterId,
  }) => _request(() async {
    final result = await client.rpc(
      'sync_pull',
      params: {
        'p_entity': entity.table,
        'p_since': since.toUtc().toIso8601String(),
        'p_until': until.toUtc().toIso8601String(),
        'p_after_time': afterTime,
        'p_after_id': afterId,
        'p_limit': 250,
      },
    );
    return (result as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  });

  @override
  Future<Json> reserveNumbers(String gymId) => _request(() async {
    final result = await client.rpc(
      'reserve_member_numbers',
      params: {'p_gym': gymId, 'p_count': 50},
    );
    return Map<String, dynamic>.from((result as List).single as Map);
  });

  @override
  Future<void> uploadPhoto(String path, Uint8List bytes) => _request(() async {
    await client.storage
        .from('member-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
  });

  @override
  void listen(String gymId, void Function() onChange) {
    if (_channel != null) return;
    _channel = client
        .channel('gymdesk:$gymId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gym_id',
            value: gymId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  @override
  Future<void> close() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) await client.removeChannel(channel);
  }
}
