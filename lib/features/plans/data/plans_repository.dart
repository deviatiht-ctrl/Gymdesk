import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../domain/plan.dart';

class PlansRepository {
  const PlansRepository(this.db, this.session);
  final LocalDatabase db;
  final StaffSession session;
  static const _uuid = Uuid();

  Future<T> _local<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlanFailure {
      rethrow;
    } on SyncRejected catch (e) {
      throw PlanFailure(e.code);
    } catch (_) {
      throw const PlanFailure('local_storage');
    }
  }

  Stream<List<GymPlan>> watch({bool includeInactive = true}) =>
      db.watchRecords(SyncEntity.plans, limit: 1000).map((rows) {
        final plans = rows
            .map(
              (row) => GymPlan(
                Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
              ),
            )
            .where((plan) => includeInactive || plan.active)
            .toList();
        plans.sort(
          (a, b) => a.sortOrder != b.sortOrder
              ? a.sortOrder.compareTo(b.sortOrder)
              : a.name.compareTo(b.name),
        );
        return plans;
      });

  Future<GymPlan> save(
    PlanDraft draft, {
    GymPlan? existing,
    required DateTime changedAt,
  }) => _local(() async {
    if (!{'owner', 'supervisor'}.contains(session.role)) {
      throw const PlanFailure('access_denied');
    }
    _validate(draft);
    final row = {
      ...(existing?.row ?? {}),
      'id': existing?.id ?? _uuid.v4(),
      'gym_id': session.gymId,
      'name': draft.name.trim(),
      'duration_days': draft.durationDays,
      'price': draft.price,
      'enrollment_price': draft.enrollmentPrice,
      'currency': draft.currency,
      'description': draft.description.trim().isEmpty
          ? null
          : draft.description.trim(),
      'active': draft.active,
      'sort_order': draft.sortOrder,
      'created_at':
          existing?.row['created_at'] ?? changedAt.toUtc().toIso8601String(),
      'updated_at': changedAt.toUtc().toIso8601String(),
      'deleted_at': null,
    };
    await db.save(SyncEntity.plans, row, changedAt: changedAt);
    return GymPlan(row);
  });

  Future<void> remove(GymPlan plan, {required DateTime changedAt}) =>
      _local(() async {
        if (session.role != 'owner') throw const PlanFailure('access_denied');
        await db.save(
          SyncEntity.plans,
          plan.row,
          changedAt: changedAt,
          deleting: true,
        );
      });

  void _validate(PlanDraft draft) {
    if (draft.name.trim().length < 2 ||
        draft.name.trim().length > 120 ||
        draft.durationDays < 1 ||
        draft.durationDays > 3650 ||
        !draft.price.isFinite ||
        (draft.enrollmentPrice != null &&
            (!draft.enrollmentPrice!.isFinite ||
                draft.enrollmentPrice! < 0 ||
                draft.enrollmentPrice! > 999999999)) ||
        draft.price < 0 ||
        draft.price > 999999999 ||
        !{'HTG', 'USD'}.contains(draft.currency) ||
        draft.description.length > 500 ||
        draft.sortOrder < 0 ||
        draft.sortOrder > 10000) {
      throw const PlanFailure('invalid_record');
    }
  }
}
