import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class PinVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecurePinVault implements PinVault {
  SecurePinVault(String namespace, String userId)
    : key = 'gymdesk:$namespace:pin:$userId';
  final String key;
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: key);
  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);
  @override
  Future<void> clear() => _storage.delete(key: key);
}

class PinFailure implements Exception {
  const PinFailure(this.code);
  final String code;
}

class PinStatus {
  const PinStatus({
    required this.enabled,
    this.failures = 0,
    this.blockedUntil,
  });
  final bool enabled;
  final int failures;
  final DateTime? blockedUntil;
  bool get requiresPassword => failures >= 10;
}

Future<List<int>> _derivePin((String, List<int>) input) async {
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(input.$1)), nonce: input.$2);
  return key.extractBytes();
}

class PinService {
  PinService(
    this.vault, {
    DateTime Function()? now,
    Future<List<int>> Function(String, List<int>)? derive,
  }) : _now = now ?? DateTime.now,
       _derive = derive ?? ((pin, salt) => compute(_derivePin, (pin, salt)));
  final PinVault vault;
  final DateTime Function() _now;
  final Future<List<int>> Function(String, List<int>) _derive;
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Map<String, dynamic>?> _read() async {
    try {
      final text = await vault.read();
      if (text == null) return null;
      final data = Map<String, dynamic>.from(jsonDecode(text) as Map);
      if (data['version'] != 1 ||
          data['iterations'] != 600000 ||
          data['failures'] is! int ||
          (data['failures'] as int) < 0 ||
          base64Decode(data['salt'] as String).length != 16 ||
          base64Decode(data['verifier'] as String).length != 32) {
        throw const PinFailure('pin_storage');
      }
      if (data['blocked_until'] != null) {
        DateTime.parse(data['blocked_until'] as String);
      }
      return data;
    } catch (_) {
      throw const PinFailure('pin_storage');
    }
  }

  Future<PinStatus> status() => _serial(() async {
    final data = await _read();
    return PinStatus(
      enabled: data != null,
      failures: data?['failures'] as int? ?? 0,
      blockedUntil: data?['blocked_until'] == null
          ? null
          : DateTime.parse(data!['blocked_until'] as String),
    );
  });

  Future<void> _write(Map<String, dynamic> data) async {
    try {
      await vault.write(jsonEncode(data));
    } catch (_) {
      throw const PinFailure('pin_storage');
    }
  }

  Future<void> verify(String pin) => _serial(() => _verify(pin));

  Future<void> _verify(String pin) async {
    final data = await _read();
    if (data == null) throw const PinFailure('pin_missing');
    final failures = data['failures'] as int;
    if (failures >= 10) throw const PinFailure('pin_password_required');
    final blocked = DateTime.tryParse(data['blocked_until'] as String? ?? '');
    if (blocked != null && _now().toUtc().isBefore(blocked)) {
      throw const PinFailure('pin_cooldown');
    }
    data['failures'] = failures + 1;
    if (failures + 1 >= 5) {
      data['blocked_until'] = _now()
          .toUtc()
          .add(Duration(seconds: 60 * (1 << (failures - 4).clamp(0, 5))))
          .toIso8601String();
    }
    await _write(data);
    final actual = await _derive(pin, base64Decode(data['salt'] as String));
    final expected = base64Decode(data['verifier'] as String);
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected[i] ^ (i < actual.length ? actual[i] : 0);
    }
    if (difference != 0) {
      throw PinFailure(
        failures + 1 >= 10 ? 'pin_password_required' : 'pin_incorrect',
      );
    }
    data['failures'] = 0;
    data.remove('blocked_until');
    await _write(data);
  }

  Future<void> configure(
    String pin, {
    String previous = '',
    bool recentPasswordLogin = false,
  }) => _serial(() async {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      throw const PinFailure('pin_format');
    }
    if (await _read() != null && !recentPasswordLogin) await _verify(previous);
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final verifier = await _derive(pin, salt);
    await _write({
      'version': 1,
      'iterations': 600000,
      'salt': base64Encode(salt),
      'verifier': base64Encode(verifier),
      'failures': 0,
    });
  });

  Future<void> remove({
    String previous = '',
    bool recentPasswordLogin = false,
  }) => _serial(() async {
    if (await _read() == null) return;
    if (!recentPasswordLogin) await _verify(previous);
    try {
      await vault.clear();
    } catch (_) {
      throw const PinFailure('pin_storage');
    }
  });

  Future<void> resetAfterPasswordLogin() => _serial(() async {
    final data = await _read();
    if (data == null) return;
    data['failures'] = 0;
    data.remove('blocked_until');
    await _write(data);
  });
}
