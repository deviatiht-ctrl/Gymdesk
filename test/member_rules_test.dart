import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/features/members/domain/member.dart';
import 'package:gym_desk/features/members/domain/enrollment_terms.dart';
import 'package:gym_desk/features/plans/domain/plan.dart';
import 'package:gym_desk/features/subscriptions/domain/gym_subscription.dart';
import 'package:gym_desk/features/subscriptions/domain/subscription_rules.dart';
import 'package:timezone/data/latest.dart' as tz;

Member member({String status = 'active'}) => Member({
  'id': 'member-1',
  'gym_id': 'gym',
  'member_number': 'PWR-000001',
  'qr_token': 'token',
  'first_name': 'Marie',
  'last_name': 'Jean',
  'status': status,
  'updated_at': '2026-01-01T00:00:00Z',
});

GymSubscription subscription({
  String status = 'active',
  String start = '2026-01-01',
  String end = '2026-01-31',
}) => GymSubscription({
  'id': 'sub-1',
  'gym_id': 'gym',
  'member_id': 'member-1',
  'plan_id': 'plan-1',
  'start_date': start,
  'end_date': end,
  'price': 1000,
  'status': status,
  'updated_at': '2026-01-01T00:00:00Z',
});

void main() {
  setUpAll(tz.initializeTimeZones);

  test('enrollment includes the first period without adding renewal price', () {
    final plan = GymPlan({
      'price': 500,
      'enrollment_price': 800,
      'duration_days': 30,
    });
    expect(plan.registrationPrice, 800);
    expect(plan.price, 500);
    final terms = EnrollmentTerms.create(
      plan: plan,
      existing: false,
      canManage: false,
      start: DateTime(2026, 10, 1),
      paid: 800,
    );
    expect(terms.price, 800);
    expect(terms.openingCredit, 0);
    expect(terms.status, 'active');
    expect(terms.kind, 'registration');
    expect(GymPlan({'price': 500}).registrationPrice, 500);
  });

  test('import retains a paid period without creating a new cash receipt', () {
    final terms = EnrollmentTerms.create(
      plan: GymPlan({
        'price': 500,
        'enrollment_price': 800,
        'duration_days': 30,
      }),
      existing: true,
      canManage: true,
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 30),
      paid: 0,
    );
    expect(terms.price, 500);
    expect(terms.openingCredit, 500);
    expect(terms.paymentAmount, 0);
    expect(terms.kind, 'import');
    expect(terms.status, 'active');
    expect(ymd(terms.end), '2026-09-30');
  });

  test(
    'import rejects reception, invalid dates and invalid payment amounts',
    () {
      final plan = GymPlan({'price': 500, 'duration_days': 30});
      expect(
        () => EnrollmentTerms.create(
          plan: plan,
          existing: true,
          canManage: false,
          start: DateTime(2026, 9, 1),
          end: DateTime(2026, 9, 30),
          paid: 0,
        ),
        throwsA(isA<MemberFailure>()),
      );
      expect(
        () => EnrollmentTerms.create(
          plan: plan,
          existing: true,
          canManage: true,
          start: DateTime(2026, 9, 1),
          end: DateTime(2026, 8, 30),
          paid: 0,
        ),
        throwsA(isA<MemberFailure>()),
      );
      for (final amount in [double.nan, double.infinity, -1.0, 501.0]) {
        expect(
          () => EnrollmentTerms.create(
            plan: plan,
            existing: false,
            canManage: true,
            start: DateTime(2026, 9, 1),
            paid: amount,
          ),
          throwsA(isA<MemberFailure>()),
        );
      }
    },
  );

  test('NIF is normalized and must contain ten digits', () {
    expect(normalizeNif('123-456-789-0'), '1234567890');
    expect(() => normalizeNif('123'), throwsA(isA<MemberFailure>()));
    expect(formatNif('1234567890'), '123-456-789-0');
  });

  test('phone normalization accepts Haitian local and E.164 forms', () {
    expect(normalizePhone('509 37 00 00 00'), '+50937000000');
    expect(normalizePhone('+509 37 00 00 00'), '+50937000000');
    expect(normalizePhone('37000000'), '+50937000000');
  });

  test('subscription validity includes grace and pending rules', () {
    final settings = {'grace_days': 2, 'allow_access_pending': true};
    final active = memberValidity(
      member(),
      [subscription(end: '2026-01-29')],
      settings,
      DateTime.utc(2026, 1, 30),
      'America/Port-au-Prince',
    );
    expect(active.valid, isTrue);
    expect(active.reason, 'ok');
    final pending = memberValidity(
      member(),
      [subscription(status: 'pending')],
      {'allow_access_pending': false},
      DateTime.utc(2026, 1, 15),
      'America/Port-au-Prince',
    );
    expect(pending.valid, isFalse);
    expect(pending.reason, 'pending_payment');
  });

  test('suspended members are denied before subscription checks', () {
    final result = memberValidity(
      member(status: 'suspended'),
      [subscription()],
      const {},
      DateTime.utc(2026, 1, 15),
      'America/Port-au-Prince',
    );
    expect(result.valid, isFalse);
    expect(result.reason, 'suspended');
  });

  test('subscription end dates are inclusive', () {
    expect(ymd(subscriptionEnd(DateTime.utc(2026, 1, 1), 30)), '2026-01-30');
    expect(
      memberValidity(
        member(),
        [subscription(end: '2026-01-30')],
        const {},
        DateTime.utc(2026, 1, 30, 23),
        'America/Port-au-Prince',
      ).valid,
      isTrue,
    );
    expect(
      memberValidity(
        member(),
        [subscription(end: '2026-01-30')],
        const {},
        DateTime.utc(2026, 1, 31, 12),
        'America/Port-au-Prince',
      ).reason,
      'expired',
    );
  });
}
