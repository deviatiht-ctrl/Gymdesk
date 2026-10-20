import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/portal_request.dart';

class PortalRepository {
  const PortalRepository(this._client);

  final SupabaseClient _client;

  /// Rekipere tout demann an liy yo pou sal sa a.
  Future<List<PortalRequest>> fetchRequests(String gymId, {String? status}) async {
    var query = _client
        .from('portal_requests')
        .select('*, plans(name, price, currency)')
        .eq('gym_id', gymId);

    if (status != null && status.isNotEmpty) {
      query = query.eq('status', status);
    }

    final data = await query.order('created_at', ascending: false);
    return (data as List<dynamic>)
        .map((e) => PortalRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Kouran tan reyèl sou demann pòtay yo pou gym lan.
  Stream<List<PortalRequest>> watchRequests(String gymId) {
    return _client
        .from('portal_requests')
        .stream(primaryKey: ['id'])
        .eq('gym_id', gymId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(PortalRequest.fromJson).toList());
  }

  /// Mete ajou eta yon demann (pending, approved, rejected, completed).
  Future<void> updateStatus(String requestId, String status) async {
    await _client.from('portal_requests').update({
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', requestId);
  }

  /// Rekipere enfòmasyon piblik gym lan ak fòmil yo pou paj adezyon an.
  Future<Map<String, dynamic>> getPublicGym(String gymCode) async {
    final res = await _client.rpc('portal_get_gym', params: {'p_gym_code': gymCode});
    if (res is Map<String, dynamic>) {
      return res;
    }
    return <String, dynamic>{};
  }

  /// Soumèt yon demann enskripsyon depi pòtay wèb la.
  Future<Map<String, dynamic>> submitJoinRequest({
    required String gymCode,
    String? planId,
    required String firstName,
    required String lastName,
    required String phone,
    String? email,
    String kind = 'new_membership',
    String? notes,
  }) async {
    final params = <String, dynamic>{
      'p_gym_code': gymCode,
      'p_first_name': firstName,
      'p_last_name': lastName,
      'p_phone': phone,
      'p_kind': kind,
    };
    if (planId != null) params['p_plan_id'] = planId;
    if (email != null && email.isNotEmpty) params['p_email'] = email;
    if (notes != null && notes.isNotEmpty) params['p_notes'] = notes;

    final res = await _client.rpc('portal_submit', params: params);
    if (res is Map<String, dynamic>) {
      return res;
    }
    return <String, dynamic>{'success': true};
  }
}
