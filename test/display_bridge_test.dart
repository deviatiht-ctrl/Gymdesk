import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/access_control/display_bridge.dart';
import 'package:gym_desk/core/access_control/terminal_access_service.dart';

void main() {
  test('decision survives the host → 2nd screen bridge round trip', () {
    final original = AccessDecision(
      AccessOutcome.granted,
      person: AccessPerson.fromSnapshot({
        'member_id': 'm-1',
        'name': 'Marie Jean',
        'first_name': 'Marie',
        'allowed': true,
        'reason': 'ok',
        'days_left': 12,
        'plan_name': 'Mensuel',
        'end_date': '2026-11-12T00:00:00.000',
      }),
      uid: 'abc',
    );
    final wire = jsonDecode(jsonEncode({
      'type': 'decision',
      'outcome': original.outcome.name,
      'has_person': true,
      'opened_by_app': false,
      'uid': original.uid,
      'row': TerminalAccessService.eventRowFor(original),
    })) as Map<String, dynamic>;

    final decoded = AccessDisplayBridge.decisionFromMessage(wire)!;
    expect(decoded.outcome, AccessOutcome.granted);
    expect(decoded.person!.name, 'Marie Jean');
    expect(decoded.person!.firstName, 'Marie');
    expect(decoded.person!.daysLeft, 12);
    expect(decoded.person!.planName, 'Mensuel');
    expect(decoded.person!.id, 'm-1');
    expect(decoded.person!.isEmployee, isFalse);
  });

  test('unrecognized fingerprint has no person on the 2nd screen', () {
    const original = AccessDecision(AccessOutcome.unrecognized);
    final decoded = AccessDisplayBridge.decisionFromMessage({
      'outcome': 'unrecognized',
      'has_person': false,
      'row': TerminalAccessService.eventRowFor(original),
    })!;
    expect(decoded.outcome, AccessOutcome.unrecognized);
    expect(decoded.person, isNull);
  });
}
