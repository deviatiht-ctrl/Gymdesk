import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/biometrics/biometric_models.dart';
import 'package:gym_desk/core/biometrics/biometric_service.dart';
import 'package:gym_desk/features/members/domain/member.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Biometric Models & Access Modes', () {
    test('Access mode fromString and id extension works', () {
      expect(BiometricAccessModeExt.fromString('badge_pin'), BiometricAccessMode.badgePin);
      expect(BiometricAccessModeExt.fromString('fingerprint_only'), BiometricAccessMode.fingerprintOnly);
      expect(BiometricAccessModeExt.fromString('combo'), BiometricAccessMode.combo);
      expect(BiometricAccessModeExt.fromString(null), BiometricAccessMode.badgePin);

      expect(BiometricAccessMode.badgePin.id, 'badge_pin');
      expect(BiometricAccessMode.fingerprintOnly.id, 'fingerprint_only');
      expect(BiometricAccessMode.combo.id, 'combo');
    });

    test('BiometricEvent parses map properly', () {
      final event = BiometricEvent.fromMap({
        'event': 'fingerprint_captured',
        'template': 'abc123xyz==',
        'quality': 95,
      });

      expect(event.type, 'fingerprint_captured');
      expect(event.template, 'abc123xyz==');
      expect(event.quality, 95);
    });
  });

  group('Biometric Matching & Similarity', () {
    test('computeSimilarity returns 1.0 for identical templates', () {
      final sample = base64Encode(List.generate(512, (i) => (i * 7) % 256));
      expect(BiometricService.computeSimilarity(sample, sample), 1.0);
    });

    test('computeSimilarity returns 0.0 for empty or invalid templates', () {
      expect(BiometricService.computeSimilarity('', 'abc'), 0.0);
      expect(BiometricService.computeSimilarity('abc', ''), 0.0);
      expect(BiometricService.computeSimilarity('', ''), 0.0);
    });

    test('computeSimilarity detects close minutiae similarity', () {
      final bytes1 = List.generate(512, (i) => (i * 3) % 250);
      // bytes2 slightly perturbed by 1-2 points
      final bytes2 = List.generate(512, (i) => ((i * 3) % 250) + (i % 2 == 0 ? 1 : 0));

      final t1 = base64Encode(bytes1);
      final t2 = base64Encode(bytes2);

      final score = BiometricService.computeSimilarity(t1, t2);
      expect(score, greaterThanOrEqualTo(0.95));
    });

    test('1:N matching finds the correct enrolled member', () async {
      final service = BiometricService();

      final bytesA = List.generate(512, (i) => (i * 11) % 250);
      final bytesB = List.generate(512, (i) => (i * 23) % 250);

      final memberA = Member({
        'id': 'mem-a',
        'gym_id': 'gym-1',
        'member_number': '000001',
        'first_name': 'Jean',
        'last_name': 'Baptiste',
        'status': 'active',
        'fingerprint_registered': true,
        'fingerprint_template': base64Encode(bytesA),
      });

      final memberB = Member({
        'id': 'mem-b',
        'gym_id': 'gym-1',
        'member_number': '000002',
        'first_name': 'Marie',
        'last_name': 'Claire',
        'status': 'active',
        'fingerprint_registered': true,
        'fingerprint_template': base64Encode(bytesB),
      });

      // Candidate matches memberA
      final candidateA = base64Encode(bytesA);
      final match = await service.match1toN(
        candidateTemplate: candidateA,
        members: [memberA, memberB],
      );

      expect(match, isNotNull);
      expect(match!.id, 'mem-a');
      expect(match.firstName, 'Jean');

      service.dispose();
    });
  });
}
