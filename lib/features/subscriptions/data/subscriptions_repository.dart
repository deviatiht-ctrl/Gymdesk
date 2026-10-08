import 'dart:convert';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../domain/gym_subscription.dart';

class SubscriptionsRepository {
  const SubscriptionsRepository(this.db, this.session);
  final LocalDatabase db;
  final StaffSession session;

  Future<T> _local<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SubscriptionFailure {
      rethrow;
    } on SyncRejected catch (e) {
      throw SubscriptionFailure(e.code);
    } catch (_) {
      throw const SubscriptionFailure('local_storage');
    }
  }

  Stream<List<GymSubscription>> watch({
    String status = 'all',
    int limit = 1000,
  }) => db.watchRecords(SyncEntity.subscriptions, limit: limit).map((rows) {
    final subscriptions = rows
        .map(
          (row) => GymSubscription(
            Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
          ),
        )
        .where((s) => status == 'all' || s.status == status)
        .toList();
    subscriptions.sort(
      (a, b) => a.endDate != b.endDate
          ? b.endDate.compareTo(a.endDate)
          : b.id.compareTo(a.id),
    );
    return subscriptions;
  });

  Stream<List<GymSubscription>> watchForMember(String memberId) =>
      db.watchRecords(SyncEntity.subscriptions, limit: 5000).map((rows) {
        final subscriptions = rows
            .map(
              (row) => GymSubscription(
                Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
              ),
            )
            .where((s) => s.memberId == memberId)
            .toList();
        subscriptions.sort(
          (a, b) => a.endDate != b.endDate
              ? b.endDate.compareTo(a.endDate)
              : b.id.compareTo(a.id),
        );
        return subscriptions;
      });

  Future<List<GymSubscription>> forMember(String memberId) async {
    final rows = await db
        .watchRecords(SyncEntity.subscriptions, limit: 5000)
        .first;
    return rows
        .map(
          (row) => GymSubscription(
            Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
          ),
        )
        .where((s) => s.memberId == memberId)
        .toList();
  }

  Future<void> cancel(
    GymSubscription subscription, {
    required DateTime changedAt,
  }) => _local(() async {
    if (!session.canManageGym ||
        subscription.deletedAt != null ||
        subscription.status == 'cancelled') {
      throw const SubscriptionFailure('access_denied');
    }
    await db.save(SyncEntity.subscriptions, {
      ...subscription.row,
      'status': 'cancelled',
    }, changedAt: changedAt);
  });

  Future<void> validateRenewal(
    GymSubscription subscription, {
    required DateTime changedAt,
  }) => _local(() async {
    if (!session.canManageGym) {
      throw const SubscriptionFailure('access_denied');
    }
    await db.save(SyncEntity.subscriptions, {
      ...subscription.row,
      'status': 'active',
      'validated_by': session.staffId,
      'validated_at': changedAt.toUtc().toIso8601String(),
    }, changedAt: changedAt);
  });

  Future<void> rejectRenewal(
    GymSubscription subscription, {
    required DateTime changedAt,
    String reason = 'Refusé par la direction',
  }) => _local(() async {
    if (!session.canManageGym) {
      throw const SubscriptionFailure('access_denied');
    }
    await db.save(SyncEntity.subscriptions, {
      ...subscription.row,
      'status': 'cancelled',
      'notes': reason,
    }, changedAt: changedAt);
  });
}
