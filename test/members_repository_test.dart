import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/db/local_database.dart';
import 'package:gym_desk/core/sync/sync_models.dart';
import 'package:gym_desk/features/members/data/members_repository.dart';
import 'package:gym_desk/features/members/domain/member.dart';
import 'package:gym_desk/features/payments/domain/payment.dart';
import 'package:gym_desk/features/plans/domain/plan.dart';
import 'package:gym_desk/features/subscriptions/domain/gym_subscription.dart';
import 'package:gym_desk/features/subscriptions/domain/subscription_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  const gymId = '10000000-0000-4000-8000-000000000001';
  const staffId = '30000000-0000-4000-8000-000000000001';
  const planId = '40000000-0000-4000-8000-000000000001';
  final now = DateTime.utc(2026, 1, 5, 12);
  final session = StaffSession(
    staff: {
      'id': staffId,
      'user_id': 'user-1',
      'role': 'owner',
      'active': true,
    },
    gym: {
      'id': gymId,
      'name': 'PWR',
      'status': 'active',
      'timezone': 'America/Port-au-Prince',
      'currency': 'HTG',
      'settings': <String, dynamic>{},
    },
    verifiedAt: now,
  );
  final draft = MemberRegistration(
    firstName: 'Marie',
    lastName: 'Jean',
    phone: '37000000',
    nif: '123-456-789-0',
  );
  late LocalDatabase db;
  late MembersRepository repository;

  GymPlan plan() => GymPlan({
    'id': planId,
    'gym_id': gymId,
    'name': 'Mensual',
    'duration_days': 30,
    'price': 1000,
    'currency': 'HTG',
    'active': true,
    'sort_order': 0,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });

  setUpAll(tz.initializeTimeZones);
  setUp(() {
    db = LocalDatabase.testing(NativeDatabase.memory(), gymId: gymId);
    repository = MembersRepository(
      SupabaseClient('https://example.supabase.co', 'anon'),
      db,
      session,
    );
  });
  tearDown(() => db.close());

  test(
    'registration writes member, subscription and payment in one outbox batch',
    () async {
      await db.reserveBlock({'prefix': 'PWR-', 'seq_first': 1, 'seq_last': 5});
      final result = await repository.register(
        draft,
        changedAt: now,
        subscription: SubscriptionCommand(
          planId: planId,
          startDate: DateTime.utc(2026, 1, 5),
          endDate: DateTime.utc(2026, 2, 3),
          price: 1000,
          status: 'active',
        ),
        payment: const PaymentCommand(
          memberId: '',
          amount: 1000,
          currency: 'HTG',
          method: 'cash',
        ),
      );
      expect(result.memberNumber, 'PWR-000001');
      expect(result.subscriptionId, isNotNull);
      expect(result.paymentId, isNotNull);
      final queue = await db.pending();
      expect(
        queue.map((op) => op.entity),
        containsAll(<String>['members', 'subscriptions', 'payments']),
      );
      final member = Member(
        jsonDecode(
              (await db.record(SyncEntity.members, result.memberId))!.payload,
            )
            as Json,
      );
      expect(member.phone, '+50937000000');
      expect(member.nif, '1234567890');
      expect(member.qrToken.length, 40);
    },
  );

  test('photo is queued inside the same registration transaction', () async {
    final result = await repository.register(
      MemberRegistration(
        firstName: 'Marie',
        lastName: 'Jean',
        photo: Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]),
      ),
      changedAt: now,
    );
    expect((await db.photoForMember(result.memberId))!.bytes.length, 4);
    expect((await db.pending()).single.entity, 'members');
  });

  test('failed registration rolls back member and reserved number', () async {
    await db.reserveBlock({'prefix': 'PWR-', 'seq_first': 1, 'seq_last': 5});
    await expectLater(
      repository.register(
        MemberRegistration(
          firstName: 'Marie',
          lastName: 'Jean',
          photo: Uint8List.fromList(const [1, 2, 3]),
        ),
        changedAt: now,
      ),
      throwsA(isA<MemberFailure>()),
    );
    expect(await db.watchRecords(SyncEntity.members).first, isEmpty);
    expect(await db.pending(), isEmpty);
    expect(await db.nextMemberNumber(), 'PWR-000001');
  });

  test('duplicate detection uses normalized NIF and phone', () async {
    final first = await repository.register(draft, changedAt: now);
    expect(first.memberNumber, startsWith('TMP-'));
    final matches = await repository.duplicates(
      const MemberRegistration(
        firstName: 'Lòt',
        lastName: 'Moun',
        whatsapp: '50937000000',
      ),
    );
    expect(matches.single.reason, 'phone');
    expect(
      await repository.duplicates(
        const MemberRegistration(
          firstName: 'Lòt',
          lastName: 'Moun',
          nif: '1234567890',
        ),
      ),
      isNotEmpty,
    );
  });

  test(
    'imported period has no collectible balance and renews at the recurring price',
    () async {
      final result = await repository.register(draft, changedAt: now);
      final member = (await repository.watchMember(result.memberId).first)!;
      final imported = GymSubscription({
        'id': '50000000-0000-4000-8000-000000000001',
        'gym_id': gymId,
        'member_id': member.id,
        'plan_id': planId,
        'start_date': '2026-01-01',
        'end_date': '2026-01-31',
        'price': 500,
        'opening_credit': 500,
        'enrollment_kind': 'import',
        'status': 'active',
        'updated_at': now.toIso8601String(),
      });
      await db.save(SyncEntity.subscriptions, imported.row, changedAt: now);
      expect(imported.remainingAfter(0), 0);
      await expectLater(
        repository.collectPayment(
          imported,
          PaymentCommand(
            memberId: member.id,
            amount: 1,
            currency: 'HTG',
            method: 'cash',
          ),
          changedAt: now,
        ),
        throwsA(isA<MemberFailure>()),
      );
      expect(await repository.watchPayments(member.id).first, isEmpty);
      final renewal = await repository.renew(
        member,
        GymPlan({...plan().row, 'price': 500, 'enrollment_price': 800}),
        start: now,
        changedAt: now,
        payment: PaymentCommand(
          memberId: member.id,
          amount: 500,
          currency: 'HTG',
          method: 'cash',
        ),
      );
      expect(renewal.price, 500);
      expect(renewal.row['enrollment_kind'], 'renewal');
      expect(ymd(renewal.startDate), '2026-02-01');
      expect(
        (await repository.watchPayments(member.id).first).single.amount,
        500,
      );
    },
  );

  test('minor member requires guardian', () async {
    await expectLater(
      repository.register(
        MemberRegistration(
          firstName: 'Ti',
          lastName: 'Jij',
          birthDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
        ),
        changedAt: now,
      ),
      throwsA(isA<MemberFailure>()),
    );
  });

  test(
    'renewal starts after the active subscription and payment completes pending state',
    () async {
      final member = await repository.register(draft, changedAt: now);
      final saved = Member(
        jsonDecode(
              (await db.record(SyncEntity.members, member.memberId))!.payload,
            )
            as Json,
      );
      final renewed = await repository.renew(
        saved,
        plan(),
        start: DateTime.utc(2026, 1, 5),
        changedAt: now,
      );
      expect(ymd(renewed.startDate), '2026-01-05');
      expect(renewed.status, 'pending');
      await repository.collectPayment(
        renewed,
        const PaymentCommand(
          memberId: '',
          amount: 1000,
          currency: 'HTG',
          method: 'cash',
        ),
        changedAt: now.add(const Duration(minutes: 1)),
      );
      final subscription = GymSubscription(
        jsonDecode(
              (await db.record(SyncEntity.subscriptions, renewed.id))!.payload,
            )
            as Json,
      );
      expect(subscription.status, 'active');
      expect(
        (await db.pending())
            .map((op) => op.entity)
            .where((entity) => entity == 'payments'),
        hasLength(1),
      );
    },
  );
}
