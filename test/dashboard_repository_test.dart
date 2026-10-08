import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/db/local_database.dart';
import 'package:gym_desk/core/sync/sync_models.dart';
import 'package:gym_desk/features/dashboard/data/dashboard_repository.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  const gymId = '10000000-0000-4000-8000-000000000001';
  final now = DateTime.now().toUtc();
  final session = StaffSession(
    staff: {
      'id': 'staff-1',
      'user_id': 'user-1',
      'role': 'owner',
      'active': true,
    },
    gym: {
      'id': gymId,
      'code': 'PWR',
      'status': 'active',
      'timezone': 'America/Port-au-Prince',
      'currency': 'HTG',
      'settings': <String, dynamic>{},
    },
    verifiedAt: now,
  );
  late LocalDatabase db;

  setUpAll(tz.initializeTimeZones);
  setUp(
    () => db = LocalDatabase.testing(NativeDatabase.memory(), gymId: gymId),
  );
  tearDown(() => db.close());

  test(
    'dashboard metrics aggregate active members, pending amounts and today activity',
    () async {
      const memberId = '20000000-0000-4000-8000-000000000001';
      const subscriptionId = '30000000-0000-4000-8000-000000000001';
      await db.save(SyncEntity.members, {
        'id': memberId,
        'gym_id': gymId,
        'member_number': 'PWR-000001',
        'qr_token': 'token',
        'first_name': 'Marie',
        'last_name': 'Jean',
        'status': 'active',
        'updated_at': now.toIso8601String(),
      }, changedAt: now);
      await db.save(SyncEntity.subscriptions, {
        'id': subscriptionId,
        'gym_id': gymId,
        'member_id': memberId,
        'start_date': '2020-01-01',
        'end_date': '2099-01-01',
        'price': 1000,
        'status': 'pending',
        'updated_at': now.toIso8601String(),
      }, changedAt: now);
      await db.save(SyncEntity.payments, {
        'id': '40000000-0000-4000-8000-000000000001',
        'gym_id': gymId,
        'member_id': memberId,
        'subscription_id': subscriptionId,
        'amount': 400,
        'currency': 'HTG',
        'method': 'cash',
        'paid_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }, changedAt: now);
      await db.save(SyncEntity.attendance, {
        'id': '50000000-0000-4000-8000-000000000001',
        'gym_id': gymId,
        'member_id': memberId,
        'scanned_at': now.toIso8601String(),
        'result': 'granted',
        'entry_number_today': 1,
        'was_offline': true,
        'suspect_clock': false,
        'created_at': now.toIso8601String(),
      }, changedAt: now);

      final metrics = await DashboardRepository(db, session).watch().first;
      expect(metrics.activeMembers, 1);
      expect(metrics.pendingAmount, 600);
      expect(metrics.revenueToday, 400);
      expect(metrics.entriesToday, 1);
    },
  );
}
