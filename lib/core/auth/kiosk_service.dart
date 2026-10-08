import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class KioskUnlockFailure implements Exception {
  const KioskUnlockFailure(this.code);
  final String code;
}

class KioskService {
  KioskService(this.client, {required this.namespace, required this.gymId});

  final SupabaseClient client;
  final String namespace;
  final String gymId;
  static const _storage = FlutterSecureStorage();

  String get _lockKey => 'gymdesk:$namespace:kiosk_locked:$gymId';
  String get _verifierKey => 'gymdesk:$namespace:kiosk_verifier:$gymId';
  String get _failuresKey => 'gymdesk:$namespace:kiosk_failures:$gymId';

  Future<bool> isLocked() async {
    final val = await _storage.read(key: _lockKey);
    return val == 'true';
  }

  /// Verrouiller le kiosque en stockant l'empreinte pour le déverrouillage hors ligne
  Future<void> lock({required String currentEmail, required String currentPassword}) async {
    // Calculer le hachage salé des identifiants superviseur/propriétaire
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 100000, bits: 256);
    final salt = utf8.encode('kiosk:$gymId:$currentEmail');
    final secret = SecretKey(utf8.encode(currentPassword));
    final key = await pbkdf2.deriveKey(secretKey: secret, nonce: salt);
    final hashB64 = base64Encode(await key.extractBytes());

    final verifierData = {
      'email': currentEmail.trim().toLowerCase(),
      'hash': hashB64,
      'gym_id': gymId,
    };

    await _storage.write(key: _verifierKey, value: jsonEncode(verifierData));
    await _storage.write(key: _lockKey, value: 'true');
  }

  /// Déverrouillage par email + mot de passe d'un owner ou supervisor
  Future<bool> unlock({
    required String email,
    required String password,
    required bool isOnline,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    // Vérifier les échecs récents (cooldown 5 min après 5 échecs)
    final failuresRaw = await _storage.read(key: _failuresKey);
    if (failuresRaw != null) {
      try {
        final fData = jsonDecode(failuresRaw) as Map<String, dynamic>;
        final count = (fData['count'] as num?)?.toInt() ?? 0;
        final blockedUntil = fData['blocked_until'] == null
            ? null
            : DateTime.tryParse(fData['blocked_until'] as String);

        if (count >= 5 && blockedUntil != null && DateTime.now().toUtc().isBefore(blockedUntil)) {
          throw const KioskUnlockFailure('kiosk_cooldown_active');
        }
      } catch (_) {}
    }

    bool success = false;

    if (isOnline) {
      try {
        final res = await client.auth.signInWithPassword(
          email: cleanEmail,
          password: password,
        );
        if (res.user != null) {
          // Vérifier que le rôle est bien owner ou supervisor de cette salle
          final staffRes = await client
              .from('staff')
              .select('role, gym_id, active')
              .eq('user_id', res.user!.id)
              .maybeSingle();

          if (staffRes != null &&
              staffRes['gym_id'] == gymId &&
              staffRes['active'] == true &&
              (staffRes['role'] == 'owner' || staffRes['role'] == 'supervisor')) {
            success = true;
          }
        }
      } catch (_) {
        success = false;
      }
    }

    if (!success) {
      // Déverrouillage hors ligne via l'empreinte locale
      final savedVerifier = await _storage.read(key: _verifierKey);
      if (savedVerifier != null) {
        try {
          final data = jsonDecode(savedVerifier) as Map<String, dynamic>;
          if (data['email'] == cleanEmail) {
            final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 100000, bits: 256);
            final salt = utf8.encode('kiosk:$gymId:$cleanEmail');
            final secret = SecretKey(utf8.encode(password));
            final key = await pbkdf2.deriveKey(secretKey: secret, nonce: salt);
            final candidateHash = base64Encode(await key.extractBytes());

            if (candidateHash == data['hash']) {
              success = true;
            }
          }
        } catch (_) {}
      }
    }

    if (success) {
      // Réinitialiser les échecs et lever le verrouillage
      await _storage.delete(key: _failuresKey);
      await _storage.write(key: _lockKey, value: 'false');
      return true;
    } else {
      // Enregistrer l'échec
      int count = 1;
      if (failuresRaw != null) {
        try {
          final fData = jsonDecode(failuresRaw) as Map<String, dynamic>;
          count = ((fData['count'] as num?)?.toInt() ?? 0) + 1;
        } catch (_) {}
      }

      DateTime? blockUntil;
      if (count >= 5) {
        blockUntil = DateTime.now().toUtc().add(const Duration(minutes: 5));
      }

      await _storage.write(
        key: _failuresKey,
        value: jsonEncode({
          'count': count,
          'blocked_until': blockUntil?.toIso8601String(),
        }),
      );

      throw KioskUnlockFailure(count >= 5 ? 'kiosk_cooldown_active' : 'unlock_credentials_invalid');
    }
  }
}
