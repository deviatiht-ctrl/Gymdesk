import 'dart:convert';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../domain/payment.dart';

class PaymentsRepository {
  const PaymentsRepository(this.db);
  final LocalDatabase db;

  Stream<List<GymPayment>> watch({
    String? memberId,
    String method = 'all',
    int limit = 1000,
  }) => db.watchRecords(SyncEntity.payments, limit: limit).map((rows) {
    final payments = rows
        .map(
          (row) => GymPayment(
            Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
          ),
        )
        .where(
          (p) =>
              (memberId == null || p.memberId == memberId) &&
              (method == 'all' || p.method == method),
        )
        .toList();
    payments.sort(
      (a, b) => a.paidAt != b.paidAt
          ? b.paidAt.compareTo(a.paidAt)
          : b.id.compareTo(a.id),
    );
    return payments;
  });

  Future<double> paidForSubscription(String subscriptionId) async {
    final rows = await db.watchRecords(SyncEntity.payments, limit: 5000).first;
    return rows
        .map(
          (row) => GymPayment(
            Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
          ),
        )
        .where((p) => p.subscriptionId == subscriptionId && p.deletedAt == null)
        .fold<double>(0, (total, p) => total + p.amount);
  }
}
