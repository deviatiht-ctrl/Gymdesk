import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/auth/pin_service.dart';

class MemoryPinVault implements PinVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> clear() async => value = null;
}

Future<List<int>> testDerive(String pin, List<int> salt) async {
  final bytes = utf8.encode('$pin:${base64Encode(salt)}');
  return List<int>.generate(32, (index) => bytes[index % bytes.length]);
}

void main() {
  late MemoryPinVault vault;
  late DateTime now;
  late PinService service;

  setUp(() {
    vault = MemoryPinVault();
    now = DateTime.utc(2026, 10, 5, 12);
    service = PinService(vault, now: () => now, derive: testDerive);
  });

  test('configure and verify a PIN without storing it in clear text', () async {
    await service.configure('246810');
    expect(vault.value, isNotNull);
    expect(vault.value, isNot(contains('246810')));
    await service.verify('246810');
    expect((await service.status()).enabled, isTrue);
  });

  test(
    'wrong PIN enters cooldown and a correct PIN waits for the cooldown',
    () async {
      await service.configure('246810');
      for (var i = 0; i < 5; i++) {
        await expectLater(service.verify('000000'), throwsA(isA<PinFailure>()));
      }
      await expectLater(
        service.verify('246810'),
        throwsA(predicate((e) => e is PinFailure && e.code == 'pin_cooldown')),
      );
      now = now.add(const Duration(seconds: 61));
      await service.verify('246810');
      expect((await service.status()).failures, 0);
    },
  );

  test('ten failures require a password sign-in reset', () async {
    await service.configure('246810');
    for (var i = 0; i < 10; i++) {
      final status = await service.status();
      final blocked = status.blockedUntil;
      if (blocked != null && now.isBefore(blocked)) now = blocked;
      await expectLater(service.verify('000000'), throwsA(isA<PinFailure>()));
    }
    expect((await service.status()).requiresPassword, isTrue);
    await expectLater(
      service.verify('246810'),
      throwsA(
        predicate((e) => e is PinFailure && e.code == 'pin_password_required'),
      ),
    );
  });

  test(
    'successful password sign-in clears cooldown but does not replace the PIN silently',
    () async {
      await service.configure('246810');
      for (var i = 0; i < 5; i++) {
        await expectLater(service.verify('000000'), throwsA(isA<PinFailure>()));
      }
      await service.resetAfterPasswordLogin();
      expect((await service.status()).blockedUntil, isNull);
      await service.configure('135791', recentPasswordLogin: true);
      await service.verify('135791');
    },
  );

  test('removing PIN requires current PIN or recent password login', () async {
    await service.configure('246810');
    await expectLater(
      service.remove(previous: '111111'),
      throwsA(isA<PinFailure>()),
    );
    expect((await service.status()).enabled, isTrue);
    await service.remove(previous: '246810');
    expect((await service.status()).enabled, isFalse);
  });

  test('corrupted secure storage reports storage failure', () async {
    vault.value = '{broken';
    await expectLater(
      service.status(),
      throwsA(predicate((e) => e is PinFailure && e.code == 'pin_storage')),
    );
  });
}
