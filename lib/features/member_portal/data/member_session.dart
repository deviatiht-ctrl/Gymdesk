import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/env.dart';

/// Erreur d'authentification membre (code stable pour l'UI).
class MemberAuthException implements Exception {
  const MemberAuthException(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  String toString() => 'MemberAuthException($code${message == null ? '' : ': $message'})';
}

class MemberSessionData {
  const MemberSessionData({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.email,
  });

  factory MemberSessionData.fromGoTrue(Map<String, dynamic> json) {
    final user = Map<String, dynamic>.from(json['user'] as Map? ?? const {});
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    final expiresAt = (json['expires_at'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn;
    return MemberSessionData(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: expiresAt,
      userId: user['id']?.toString() ?? '',
      email: user['email']?.toString() ?? '',
    );
  }

  factory MemberSessionData.fromJson(Map<String, dynamic> json) => MemberSessionData(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresAt: (json['expires_at'] as num).toInt(),
        userId: json['user_id'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );

  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  final String userId;
  final String email;

  bool get expiresSoon => DateTime.now().millisecondsSinceEpoch ~/ 1000 > expiresAt - 90;

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt,
        'user_id': userId,
        'email': email,
      };
}

/// Session de l'ESPACE MEMBRE, totalement séparée de la session du personnel :
/// stockage à part et appels REST GoTrue directs (le client Supabase standard
/// diffuse ses connexions à tous les onglets via BroadcastChannel, ce qui
/// déconnecterait le personnel si un membre se connecte sur le même navigateur).
class MemberAuth extends ChangeNotifier {
  MemberAuth._();
  static final instance = MemberAuth._();

  static const _storageKey = 'securgym:member_session:v1';
  static const _storage = FlutterSecureStorage();

  MemberSessionData? _session;
  Future<void>? _restoring;
  Future<MemberSessionData?>? _refreshing;
  SupabaseClient? _client;

  MemberSessionData? get session => _session;
  bool get signedIn => _session != null;
  String get _authUrl => '${AppEnv.supabaseUrl}/auth/v1';

  Map<String, String> get _headers => {
        'apikey': AppEnv.supabaseKey,
        'Content-Type': 'application/json',
      };

  /// Client Supabase (REST/RPC/Storage) qui utilise le jeton du membre,
  /// ou la clé publique quand personne n'est connecté.
  SupabaseClient get client => _client ??= SupabaseClient(
        AppEnv.supabaseUrl,
        AppEnv.supabaseKey,
        accessToken: () async => (await validSession())?.accessToken,
      );

  Future<void> restore() => _restoring ??= _restore();

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.isEmpty) return;
      _session = MemberSessionData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      notifyListeners();
      if (_session!.expiresSoon) await validSession();
    } catch (_) {
      await _clear();
    }
  }

  Future<MemberSessionData?> validSession() async {
    final current = _session;
    if (current == null) return null;
    if (!current.expiresSoon) return current;
    return _refreshing ??= _refresh(current).whenComplete(() => _refreshing = null);
  }

  Future<MemberSessionData?> _refresh(MemberSessionData current) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_authUrl/token?grant_type=refresh_token'),
            headers: _headers,
            body: jsonEncode({'refresh_token': current.refreshToken}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        await _save(MemberSessionData.fromGoTrue(jsonDecode(res.body) as Map<String, dynamic>));
        return _session;
      }
      if (res.statusCode >= 400 && res.statusCode < 500) {
        await _clear();
        return null;
      }
    } catch (_) {}
    // Réseau indisponible : on garde la session (le serveur refusera si expirée).
    return current;
  }

  Future<void> signIn(String email, String password) async {
    final res = await _post('/token?grant_type=password', {'email': email.trim().toLowerCase(), 'password': password});
    if (res.statusCode == 200) {
      await _save(MemberSessionData.fromGoTrue(jsonDecode(res.body) as Map<String, dynamic>));
      return;
    }
    throw _error(res, fallback: 'invalid_credentials');
  }

  /// Connexion avec le numéro de téléphone ou le nom de la fiche membre :
  /// l'Edge Function member_phone_login renvoie un jeton à usage unique.
  /// Renvoie le prénom du membre.
  Future<String> signInWithPhone(String gymId, String query) async {
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${AppEnv.supabaseUrl}/functions/v1/member_phone_login'),
            headers: {..._headers, 'Authorization': 'Bearer ${AppEnv.supabaseKey}'},
            body: jsonEncode({'gym_id': gymId, 'phone': query, 'query': query}),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const MemberAuthException('network');
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const MemberAuthException('network');
    }
    final status = (body['status'] ?? body['error'] ?? '').toString();
    if (status != 'ok' || body['token_hash'] is! String) {
      throw MemberAuthException(status.isEmpty ? 'network' : status);
    }
    final verify = await _post('/verify', {'type': 'magiclink', 'token_hash': body['token_hash']});
    if (verify.statusCode != 200) throw _error(verify, fallback: 'phone_login_failed');
    await _save(MemberSessionData.fromGoTrue(jsonDecode(verify.body) as Map<String, dynamic>));
    return body['first_name']?.toString() ?? '';
  }

  /// Crée le compte (confirmation email automatique côté projet). Si l'email a déjà
  /// un compte (membre d'un autre gym, ou propriétaire), on tente la connexion avec
  /// le mot de passe saisi.
  Future<void> signUpOrSignIn(String email, String password) async {
    final res = await _post('/signup', {'email': email.trim().toLowerCase(), 'password': password});
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['access_token'] is String) {
        await _save(MemberSessionData.fromGoTrue(body));
        return;
      }
      // Projet configuré avec confirmation email : la connexion directe échouera.
      try {
        await signIn(email, password);
        return;
      } on MemberAuthException {
        throw const MemberAuthException('email_confirmation_required');
      }
    }
    final error = _error(res, fallback: 'signup_failed');
    if (error.code == 'user_already_exists') {
      try {
        await signIn(email, password);
        return;
      } on MemberAuthException {
        throw const MemberAuthException('account_exists');
      }
    }
    throw error;
  }

  Future<void> sendPasswordReset(String email, String redirectTo) async {
    final res = await _post(
      '/recover?redirect_to=${Uri.encodeComponent(redirectTo)}',
      {'email': email.trim().toLowerCase()},
    );
    if (res.statusCode >= 300) throw _error(res, fallback: 'reset_failed');
  }

  /// Lien « mot de passe oublié » : jetons dans le fragment de l'URL (#access_token=…&type=recovery).
  Future<bool> consumeRecoveryFragment(Uri uri) async {
    if (uri.fragment.isEmpty) return false;
    Map<String, String> params;
    try {
      params = Uri.splitQueryString(uri.fragment);
    } catch (_) {
      return false;
    }
    if (params['type'] != 'recovery' || params['access_token'] == null || params['refresh_token'] == null) {
      return false;
    }
    final userRes = await http.get(
      Uri.parse('$_authUrl/user'),
      headers: {..._headers, 'Authorization': 'Bearer ${params['access_token']}'},
    );
    if (userRes.statusCode != 200) return false;
    await _save(MemberSessionData.fromGoTrue({
      'access_token': params['access_token'],
      'refresh_token': params['refresh_token'],
      'expires_in': int.tryParse(params['expires_in'] ?? '') ?? 3600,
      'expires_at': int.tryParse(params['expires_at'] ?? ''),
      'user': jsonDecode(userRes.body),
    }));
    return true;
  }

  Future<void> updatePassword(String password) async {
    final s = await validSession();
    if (s == null) throw const MemberAuthException('not_authenticated');
    final res = await http
        .put(
          Uri.parse('$_authUrl/user'),
          headers: {..._headers, 'Authorization': 'Bearer ${s.accessToken}'},
          body: jsonEncode({'password': password}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 300) throw _error(res, fallback: 'password_update_failed');
  }

  Future<void> signOut() async {
    final s = _session;
    await _clear();
    if (s == null) return;
    try {
      await http
          .post(
            Uri.parse('$_authUrl/logout?scope=local'),
            headers: {..._headers, 'Authorization': 'Bearer ${s.accessToken}'},
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    try {
      return await http
          .post(Uri.parse('$_authUrl$path'), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const MemberAuthException('network');
    }
  }

  MemberAuthException _error(http.Response res, {required String fallback}) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final code = (body['error_code'] ?? body['code'] ?? body['error'])?.toString() ?? '';
      final msg = (body['msg'] ?? body['message'] ?? body['error_description'])?.toString();
      final lower = '${msg ?? ''} $code'.toLowerCase();
      if (code == 'user_already_exists' || lower.contains('already registered')) {
        return MemberAuthException('user_already_exists', msg);
      }
      if (code == 'weak_password' || lower.contains('password should')) {
        return MemberAuthException('weak_password', msg);
      }
      if (code == 'invalid_credentials' || code == 'invalid_grant' || lower.contains('invalid login')) {
        return MemberAuthException('invalid_credentials', msg);
      }
      if (code == 'over_email_send_rate_limit' || code == 'over_request_rate_limit' || res.statusCode == 429) {
        return MemberAuthException('rate_limited', msg);
      }
      if (code == 'email_not_confirmed') return MemberAuthException('email_confirmation_required', msg);
      if (code == 'email_address_invalid' || lower.contains('invalid format')) {
        return MemberAuthException('invalid_email', msg);
      }
      return MemberAuthException(fallback, msg);
    } catch (_) {
      return MemberAuthException(fallback);
    }
  }

  Future<void> _save(MemberSessionData data) async {
    _session = data;
    notifyListeners();
    try {
      await _storage.write(key: _storageKey, value: jsonEncode(data.toJson()));
    } catch (_) {}
  }

  Future<void> _clear() async {
    _session = null;
    notifyListeners();
    try {
      await _storage.delete(key: _storageKey);
    } catch (_) {}
  }
}
