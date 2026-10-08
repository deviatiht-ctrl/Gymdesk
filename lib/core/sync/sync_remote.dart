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
      return await request().timeout(const Duration(seconds: 30));
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
    final function = operation['p_entity'] == 'gyms'
        ? 'sync_branding'
        : 'sync_push';
    return Map<String, dynamic>.from(
      await client.rpc(function, params: operation) as Map,
    );
  });

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
