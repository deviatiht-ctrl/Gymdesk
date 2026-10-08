import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../domain/staff_profile.dart';

class StaffRepository {
  const StaffRepository(this.client, this.db, this.session);
  final SupabaseClient client;
  final LocalDatabase db;
  final StaffSession session;

  Future<T> _request<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 60));
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['error'] : null;
      const safe = {
        'access_denied',
        'owner_exists',
        'request_mismatch',
        'invalid_record',
        'weak_password',
        'network',
        'origin_denied',
        'session_expired',
        'provision_failed',
      };
      throw StaffFailure(
        code is String && safe.contains(code) ? code : 'server_error',
      );
    } on PostgrestException catch (e) {
      throw StaffFailure(switch (e.code) {
        '42501' => 'access_denied',
        '40001' => 'conflict',
        '23505' => 'owner_exists',
        '22023' || '22P02' =>
          e.message == 'request_mismatch'
              ? 'request_mismatch'
              : 'invalid_record',
        'PGRST301' || 'PGRST302' || 'PGRST303' => 'session_expired',
        _ => 'server_error',
      });
    } on AuthException {
      throw const StaffFailure('session_expired');
    } on TimeoutException {
      throw const StaffFailure('network');
    } on StaffFailure {
      rethrow;
    } on SyncRejected catch (e) {
      throw StaffFailure(e.code);
    } catch (_) {
      throw const StaffFailure('network');
    }
  }

  Stream<List<StaffProfile>> watch() =>
      db.watchRecords(SyncEntity.staff, limit: 500).map((rows) {
        final staff = rows
            .map(
              (row) => StaffProfile.fromJson(
                Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
              ),
            )
            .where((person) => person.deletedAt == null)
            .toList();
        staff.sort(
          (a, b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );
        return staff;
      });

  Future<StaffProfile> create(CreateStaffCommand command) => _request(() async {
    if (session.role != 'owner') throw const StaffFailure('access_denied');
    final response = await client.functions.invoke(
      'manage_staff',
      body: command.toJson(),
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['staff'] is! Map) throw const StaffFailure('provision_failed');
    final staff = StaffProfile.fromJson(
      Map<String, dynamic>.from(data['staff'] as Map),
    );
    await db.putRemote(
      SyncEntity.staff,
      Map<String, dynamic>.from(data['staff'] as Map),
    );
    return staff;
  });

  Future<StaffProfile> updateAccess(
    StaffProfile target, {
    required String role,
    required bool active,
  }) => _request(() async {
    if (session.role != 'owner' ||
        !{'supervisor', 'reception'}.contains(role) ||
        !{'supervisor', 'reception'}.contains(target.role)) {
      throw const StaffFailure('access_denied');
    }
    final result = await client.rpc(
      'update_staff_access',
      params: {
        'p_staff': target.id,
        'p_role': role,
        'p_active': active,
        'p_version': target.updatedAt,
      },
    );
    final row = Map<String, dynamic>.from(result as Map);
    await db.putRemote(SyncEntity.staff, row);
    return StaffProfile.fromJson(row);
  });

  Future<StaffProfile> updateProfile(
    StaffProfile target, {
    required String fullName,
    required String phone,
  }) => _request(() async {
    if (target.gymId != session.gymId ||
        (session.role != 'owner' && target.id != session.staffId)) {
      throw const StaffFailure('access_denied');
    }
    if (fullName.trim().length < 2 ||
        fullName.trim().length > 120 ||
        phone.length > 32) {
      throw const StaffFailure('invalid_record');
    }
    final result = await client
        .from('staff')
        .update({
          'full_name': fullName.trim(),
          'phone': phone.isEmpty ? null : phone,
        })
        .eq('id', target.id)
        .eq('gym_id', target.gymId)
        .select()
        .single();
    final row = Map<String, dynamic>.from(result);
    await db.putRemote(SyncEntity.staff, row);
    return StaffProfile.fromJson(row);
  });
}
