import 'dart:convert';

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
    try {
      final res = await _client.rpc('portal_get_gym', params: {'p_gym_code': gymCode});
      if (res is Map<String, dynamic>) {
        return res;
      }
    } catch (_) {
      // Fallback sekirite: si RPC an gen yon ansyen erè kolòn nan baz done a, li rekipere l an dirèk
      try {
        final gymRows = await _client
            .from('gyms')
            .select('id, name, currency, logo_url')
            .or('id.eq.$gymCode,name.ilike.$gymCode')
            .limit(1);
        if (gymRows.isNotEmpty) {
          final gym = gymRows.first;
          final gymId = gym['id'] as String;
          final planRows = await _client
              .from('plans')
              .select('id, name, duration_days, price, currency, description')
              .eq('gym_id', gymId)
              .eq('active', true)
              .order('price', ascending: true);
          return {
            'gym': gym,
            'plans': planRows,
          };
        }
      } catch (_) {}
      rethrow;
    }
    return <String, dynamic>{};
  }

  /// Chèche yon manm pou renouvèlman san mande koneksyon (pa telefòn oswa ID).
  Future<Map<String, dynamic>> lookupMember({
    required String gymCode,
    required String query,
  }) async {
    try {
      final res = await _client.rpc('portal_lookup_member', params: {
        'p_gym_code': gymCode,
        'p_query': query,
      });
      if (res is Map<String, dynamic>) {
        return res;
      }
    } catch (_) {}
    return {'found': false};
  }

  /// Rekipere dènye eskanè anprent nan pòt la pou renouvèlman an dirèk.
  Future<Map<String, dynamic>> getLatestDoorScan(String gymCode) async {
    try {
      final res = await _client.rpc('portal_latest_door_scan', params: {
        'p_gym_code': gymCode,
      });
      if (res is Map<String, dynamic>) {
        return res;
      }
    } catch (_) {}
    return {'found': false};
  }

  /// Soumèt yon demann enskripsyon oswa renouvèlman depi pòtay wèb la.
  Future<Map<String, dynamic>> submitJoinRequest({
    required String gymCode,
    String? planId,
    required String firstName,
    required String lastName,
    required String phone,
    String? email,
    String kind = 'new_membership',
    String? notes,
    String? memberId,
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
    if (memberId != null && memberId.isNotEmpty) params['p_member_id'] = memberId;

    final res = await _client.rpc('portal_submit', params: params);
    if (res is Map<String, dynamic>) {
      return res;
    }
    return <String, dynamic>{'success': true};
  }
  /// Rekipere eta demann lan an dirèk (pou swiv anprent ak resi a sou telefòn lan).
  Future<Map<String, dynamic>> getRequestStatus(
    String requestId, {
    String? fallbackPhone,
    String? fallbackGymId,
  }) async {
    Map<String, dynamic>? parseRow(Map<String, dynamic> r) {
      final gym = r['gyms'] as Map<String, dynamic>?;
      final plan = r['plans'] as Map<String, dynamic>?;
      final rawNotes = r['notes']?.toString() ?? '';
      Map<String, dynamic>? embeddedReceipt;
      if (rawNotes.contains('__RECEIPT__:')) {
        final jsonPart = rawNotes.split('__RECEIPT__:').last.trim();
        try {
          embeddedReceipt = Map<String, dynamic>.from(jsonDecode(jsonPart) as Map);
        } catch (_) {}
      }
      final regFee = (embeddedReceipt?['registration_fee'] as num?)?.toDouble() ??
          (plan?['registration_fee'] as num?)?.toDouble() ??
          0.0;
      return {
        'found': true,
        'id': r['id'],
        'status': r['status'],
        'kind': r['kind'],
        'plan_id': r['plan_id'],
        'first_name': r['first_name'],
        'last_name': r['last_name'],
        'phone': r['phone'],
        'email': r['email'],
        'created_at': r['created_at'],
        'updated_at': r['updated_at'],
        'gym_name': gym?['name'] ?? '',
        'gym_currency': gym?['currency'] ?? 'HTG',
        'gym_logo_url': gym?['logo_url'],
        'plan_name': embeddedReceipt?['plan_name'] ?? plan?['name'] ?? '',
        'plan_price': (embeddedReceipt?['plan_fee'] as num?)?.toDouble() ?? plan?['price'],
        'registration_fee': regFee,
        'has_biometric': r['status'] == 'approved' || r['status'] == 'completed',
        'member_id': r['member_id'],
        'member_number': embeddedReceipt?['member_number'],
        'receipt': embeddedReceipt,
      };
    }

    // 1. Chèche dirèkteman nan portal_requests (pi rapid + gen __RECEIPT__ nan notes)
    final isUuid = RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(requestId.trim());
    if (isUuid) {
      try {
        final rows = await _client
            .from('portal_requests')
            .select('*, gyms(name, currency, logo_url), plans(name, price)')
            .eq('id', requestId.trim())
            .limit(1);
        if (rows.isNotEmpty) {
          final parsed = parseRow(Map<String, dynamic>.from(rows.first as Map));
          if (parsed != null) return parsed;
        }
      } catch (_) {}
    }

    // 2. Fallback RPC portal_get_request_status si disponib
    if (isUuid) {
      try {
        final res = await _client.rpc('portal_get_request_status', params: {
          'p_request_id': requestId.trim(),
        });
        if (res is Map<String, dynamic> && res['found'] == true) {
          return res;
        }
      } catch (_) {}
    }

    // 3. Fallback pa nimewo telefòn si requestId te yon kòd sesyon lokal (SEC-...)
    if (fallbackPhone != null && fallbackPhone.trim().isNotEmpty) {
      try {
        var q = _client
            .from('portal_requests')
            .select('*, gyms(name, currency, logo_url), plans(name, price)')
            .eq('phone', fallbackPhone.trim());
        if (fallbackGymId != null && fallbackGymId.isNotEmpty) {
          q = q.eq('gym_id', fallbackGymId);
        }
        final rows = await q.order('created_at', ascending: false).limit(1);
        if (rows.isNotEmpty) {
          final parsed = parseRow(Map<String, dynamic>.from(rows.first as Map));
          if (parsed != null) return parsed;
        }
      } catch (_) {}
    }

    return {'found': false};
  }
}