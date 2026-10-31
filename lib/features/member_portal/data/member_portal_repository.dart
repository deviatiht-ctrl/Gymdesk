import 'package:supabase_flutter/supabase_flutter.dart';

import 'member_session.dart';

/// Accès aux RPC de l'espace membre (migration 34). Toutes les données sont
/// filtrées côté serveur par (compte connecté, gym) : un membre ne voit jamais
/// un autre gym ni un autre membre.
class MemberPortalRepository {
  MemberPortalRepository([MemberAuth? auth]) : auth = auth ?? MemberAuth.instance;

  final MemberAuth auth;
  SupabaseClient get _client => auth.client;

  static final Map<String, String> _signedCache = {};

  Future<List<Map<String, dynamic>>> gyms() async {
    final res = await _client.rpc('member_portal_gyms');
    return (res as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>?> gym(String gymId) async {
    final res = await _client.rpc('member_portal_gym', params: {'p_gym': gymId});
    final map = Map<String, dynamic>.from(res as Map? ?? const {});
    if (map['found'] != true) return null;
    return Map<String, dynamic>.from(map['gym'] as Map);
  }

  Future<String> check({
    required String gymId,
    required String email,
    required String phone,
    String? memberNumber,
  }) async {
    final res = await _client.rpc('member_portal_check', params: {
      'p_gym': gymId,
      'p_email': email.trim(),
      'p_phone': phone.trim(),
      'p_member_number': (memberNumber ?? '').trim().isEmpty ? null : memberNumber!.trim(),
    });
    return (res as Map?)?['status']?.toString() ?? 'not_found';
  }

  Future<String> link({required String gymId, required String phone, String? memberNumber}) async {
    final res = await _client.rpc('member_portal_link', params: {
      'p_gym': gymId,
      'p_phone': phone.trim(),
      'p_member_number': (memberNumber ?? '').trim().isEmpty ? null : memberNumber!.trim(),
    });
    return (res as Map?)?['status']?.toString() ?? 'error';
  }

  Future<String> attachRequest(String requestId) async {
    final res = await _client.rpc('member_portal_attach_request', params: {'p_request_id': requestId});
    return (res as Map?)?['status']?.toString() ?? 'error';
  }

  Future<Map<String, dynamic>> me(String gymId) async {
    final res = await _client.rpc('member_portal_me', params: {'p_gym': gymId});
    return Map<String, dynamic>.from(res as Map? ?? const {});
  }

  Future<String> requestRenewal(String gymId, String? planId) async {
    final res = await _client.rpc('member_portal_request_renewal', params: {
      'p_gym': gymId,
      'p_plan_id': planId,
    });
    return (res as Map?)?['status']?.toString() ?? 'error';
  }

  /// Logo d'un gym (bucket privé, lecture publique autorisée par la migration 34).
  Future<String?> logoUrl(String? path, {int seconds = 60 * 60 * 24 * 7}) =>
      _signed('gym-assets', path, seconds);

  Future<String?> photoUrl(String? path) => _signed('member-photos', path, 3600);

  Future<String?> receiptUrl(String? path) => _signed('receipts', path, 3600);

  Future<String?> _signed(String bucket, String? path, int seconds) async {
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final key = '$bucket/$path/$seconds';
    final cached = _signedCache[key];
    if (cached != null) return cached;
    try {
      final url = await _client.storage.from(bucket).createSignedUrl(path, seconds);
      _signedCache[key] = url;
      return url;
    } catch (_) {
      return null;
    }
  }
}
