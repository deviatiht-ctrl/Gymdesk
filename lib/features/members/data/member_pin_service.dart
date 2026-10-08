import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../domain/member_pin.dart';

class MemberPinService {
  MemberPinService(this.db, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final LocalDatabase db;
  final DateTime Function() _now;

  static const int _iterations = 210000;
  static const int _saltBytes = 16;

  /// Dérivation PBKDF2-HMAC-SHA256 avec 210 000 itérations
  Future<String> _deriveHash(String pin, List<int> salt, int iterations) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin.trim())),
      nonce: salt,
    );
    final bytes = await key.extractBytes();
    return base64Encode(bytes);
  }

  /// Création d'une nouvelle empreinte salée pour un membre
  Future<MemberPinData> createPinData(
    String memberId,
    String gymId,
    String rawPin,
  ) async {
    final random = Random.secure();
    final saltBytes = List<int>.generate(_saltBytes, (_) => random.nextInt(256));
    final saltB64 = base64Encode(saltBytes);
    final hashB64 = await _deriveHash(rawPin, saltBytes, _iterations);

    final now = _now().toUtc();
    return MemberPinData(
      memberId: memberId,
      gymId: gymId,
      pinHash: hashB64,
      salt: saltB64,
      algo: 'pbkdf2_sha256',
      iterations: _iterations,
      failedCount: 0,
      totalFailed: 0,
      lockedUntil: null,
      resetRequired: false,
      setAt: now,
      updatedAt: now,
    );
  }

  /// Récupérer les données PIN d'un membre depuis la base locale
  Future<MemberPinData?> getPinData(String memberId) async {
    final record = await db.memberPinRecord(memberId);
    if (record == null) return null;
    try {
      final json = jsonDecode(record.payload) as Map<String, dynamic>;
      return MemberPinData.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Sauvegarder les données PIN dans la base locale et l'outbox
  Future<void> savePinData(MemberPinData pinData) async {
    await db.save(
      SyncEntity.memberPins,
      pinData.toJson(),
      changedAt: _now().toUtc(),
    );
  }

  /// Vérification du code PIN saisi au scan
  Future<PinVerifyResult> verifyPin(String memberId, String inputPin) async {
    final pinData = await getPinData(memberId);
    if (pinData == null || pinData.pinHash == 'UNSET') {
      return const PinVerifyResult(
        status: PinVerifyStatus.notConfigured,
        message: 'pin_not_set',
      );
    }

    if (pinData.resetRequired) {
      return const PinVerifyResult(
        status: PinVerifyStatus.resetRequired,
        message: 'pin_reset_required',
      );
    }

    final now = _now().toUtc();

    // Vérifier si le badge est verrouillé temporairement (5 min)
    if (pinData.lockedUntil != null && now.isBefore(pinData.lockedUntil!)) {
      return PinVerifyResult(
        status: PinVerifyStatus.pinLocked,
        failedCount: pinData.failedCount,
        lockedUntil: pinData.lockedUntil,
        message: 'pin_locked_cooldown',
      );
    }

    // Vérification cryptographique
    final salt = base64Decode(pinData.salt);
    final candidateHash = await _deriveHash(inputPin, salt, pinData.iterations);

    final expectedBytes = base64Decode(pinData.pinHash);
    final candidateBytes = base64Decode(candidateHash);

    // Comparaison en temps constant pour éviter les timing attacks
    var diff = expectedBytes.length ^ candidateBytes.length;
    for (var i = 0; i < expectedBytes.length; i++) {
      diff |= expectedBytes[i] ^ (i < candidateBytes.length ? candidateBytes[i] : 0);
    }

    if (diff == 0) {
      // PIN correct : réinitialiser failed_count consécutif
      if (pinData.failedCount > 0 || pinData.lockedUntil != null) {
        final updated = pinData.copyWith(
          failedCount: 0,
          lockedUntil: null,
          updatedAt: now,
        );
        await savePinData(updated);
      }
      return const PinVerifyResult(status: PinVerifyStatus.ok);
    }

    // Échec de saisie : incrémenter les compteurs
    final newFailed = pinData.failedCount + 1;
    final newTotalFailed = pinData.totalFailed + 1;
    DateTime? lockUntil;
    bool requireReset = pinData.resetRequired;

    if (newTotalFailed >= 10) {
      requireReset = true;
    } else if (newFailed >= 5) {
      // 5 échecs consécutifs -> verrouillage 5 minutes
      lockUntil = now.add(const Duration(minutes: 5));
    }

    final updated = pinData.copyWith(
      failedCount: newFailed,
      totalFailed: newTotalFailed,
      lockedUntil: lockUntil,
      resetRequired: requireReset,
      updatedAt: now,
    );
    await savePinData(updated);

    if (requireReset) {
      return PinVerifyResult(
        status: PinVerifyStatus.resetRequired,
        failedCount: newFailed,
        message: 'pin_reset_required',
      );
    }

    if (lockUntil != null) {
      return PinVerifyResult(
        status: PinVerifyStatus.pinLocked,
        failedCount: newFailed,
        lockedUntil: lockUntil,
        message: 'pin_locked_5min',
      );
    }

    return PinVerifyResult(
      status: PinVerifyStatus.badPin,
      failedCount: newFailed,
      message: 'pin_incorrect',
    );
  }

  /// Réinitialisation du code PIN (superviseur / propriétaire avec le membre présent)
  Future<void> resetPin(String memberId, String gymId, String newRawPin) async {
    final fresh = await createPinData(memberId, gymId, newRawPin);
    await savePinData(fresh);
  }

  /// Marque le PIN comme « à redéfinir » (fallback hors ligne du RPC
  /// reset_member_pin). L'ancien hash est invalidé : le membre devra
  /// choisir un nouveau code à la réception.
  Future<void> markPinResetRequired(String memberId, String gymId) async {
    final existing = await getPinData(memberId);
    final data = MemberPinData(
      memberId: memberId,
      gymId: gymId,
      pinHash: 'UNSET',
      salt: 'UNSET',
      failedCount: 0,
      totalFailed: 0,
      resetRequired: true,
      setAt: existing?.setAt,
      updatedAt: _now().toUtc(),
    );
    await savePinData(data);
  }
}
