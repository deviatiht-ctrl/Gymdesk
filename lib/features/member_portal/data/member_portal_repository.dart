import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'member_session.dart';

/// Accès aux RPC de l'espace membre (migration 34). Toutes les données sont
/// filtrées côté serveur par (compte connecté, gym) : un membre ne voit jamais
/// un autre gym ni un autre membre.
class MemberPortalRepository {
  MemberPortalRepository([MemberAuth? auth]) : auth = auth ?? MemberAuth.instance;

  final MemberAuth auth;
  SupabaseClient get _client => auth.client;

  /// Client REST/Realtime du membre (jeton du membre, pas celui du personnel).
  SupabaseClient get client => _client;

  static final Map<String, String> _signedCache = {};

  Future<List<Map<String, dynamic>>> gyms() async {
    final res = await _client.rpc('member_portal_gyms');
    return (res as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Gyms du membre connecté (compte lié ou inscription en cours).
  Future<List<Map<String, dynamic>>> myGyms() async {
    final res = await _client.rpc('member_portal_my_gyms');
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

  /// Messagerie membre → gym (table member_messages, migration 34).
  Future<String> sendMessage(String gymId, String body) async {
    final res = await _client.rpc('member_portal_send_message', params: {
      'p_gym': gymId,
      'p_body': body,
    });
    return (res as Map?)?['status']?.toString() ?? 'error';
  }

  /// Conversation du membre (marque lus les messages venant du gym).
  Future<List<Map<String, dynamic>>> messages(String gymId) async {
    final res = await _client.rpc('member_portal_messages', params: {'p_gym': gymId});
    return (res as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Canal temps réel sur la conversation du membre (policy member_messages).
  RealtimeChannel messagesChannel(String memberId, void Function() onChange) =>
      _client
          .channel('member-msgs:$memberId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'member_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'member_id',
              value: memberId,
            ),
            callback: (_) => onChange(),
          )
          .subscribe();

  /// Mise à jour du profil par le membre (champs en liste blanche côté serveur).
  Future<String> updateProfile(String gymId, Map<String, dynamic> patch) async {
    final res = await _client.rpc('member_portal_update_profile', params: {
      'p_gym': gymId,
      'p_patch': patch,
    });
    return (res as Map?)?['status']?.toString() ?? 'error';
  }

  /// Photo du membre : `member-photos/<gym>/<member>/<fichier>.jpg`
  /// (policy member_portal_photo_insert/update, migration 34).
  Future<void> uploadPhoto(String path, Uint8List bytes) => _client.storage
      .from('member-photos')
      .uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );

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
