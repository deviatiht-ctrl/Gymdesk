import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../domain/gym_subscription.dart';
import '../domain/subscription_rules.dart';

class SubscriptionsRepository {
  const SubscriptionsRepository(this.db, this.session);
  final LocalDatabase db;
  final StaffSession session;

  bool get _canModifySubscriptions =>
      {'owner', 'supervisor', 'reception', 'manager'}.contains(session.role);

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
        .where((s) => s.deletedAt == null && (status == 'all' || s.status == status))
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
            .where((s) => s.memberId == memberId && s.deletedAt == null)
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
        .where((s) => s.memberId == memberId && s.deletedAt == null)
        .toList();
  }

  Future<void> cancel(
    GymSubscription subscription, {
    required DateTime changedAt,
  }) => _local(() async {
    if (!_canModifySubscriptions ||
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
    if (!_canModifySubscriptions) {
      throw const SubscriptionFailure('access_denied');
    }
    await db.save(SyncEntity.subscriptions, {
      ...subscription.row,
      'status': 'active',
      'validated_by': session.staffId,
      'validated_at': changedAt.toUtc().toIso8601String(),
    }, changedAt: changedAt);
  });

  Future<GymSubscription> updateSubscription(
    GymSubscription subscription, {
    String? planId,
    required DateTime startDate,
    required DateTime endDate,
    required double price,
    required String status,
    required DateTime changedAt,
  }) => _local(() async {
    if (!_canModifySubscriptions) {
      throw const SubscriptionFailure('access_denied');
    }
    final sDate = dateOnly(startDate);
    final eDate = dateOnly(endDate);
    if (eDate.isBefore(sDate) || price < 0) {
      throw const SubscriptionFailure('invalid_record');
    }
    final updatedRow = <String, dynamic>{
      ...subscription.row,
      'plan_id': planId ?? subscription.planId,
      'start_date': ymd(sDate),
      'end_date': ymd(eDate),
      'price': price,
      'status': status,
      if (status == 'active') ...{
        'validated_by': session.staffId,
        'validated_at': changedAt.toUtc().toIso8601String(),
      },
      'updated_at': changedAt.toUtc().toIso8601String(),
      'deleted_at': null,
    };
    await db.save(
      SyncEntity.subscriptions,
      updatedRow,
      changedAt: changedAt,
    );
    return GymSubscription(updatedRow);
  });

  Future<void> deleteSubscription(
    GymSubscription subscription, {
    required DateTime changedAt,
    SupabaseClient? client,
  }) => _local(() async {
    if (!_canModifySubscriptions) {
      throw const SubscriptionFailure('access_denied');
    }
    await db.save(
      SyncEntity.subscriptions,
      subscription.row,
      changedAt: changedAt,
      deleting: true,
    );
    if (client != null) {
      try {
        await client.from('subscriptions').update({
          'status': 'cancelled',
          'deleted_at': changedAt.toUtc().toIso8601String(),
          'updated_at': changedAt.toUtc().toIso8601String(),
        }).eq('id', subscription.id);
      } catch (_) {}
    }
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
