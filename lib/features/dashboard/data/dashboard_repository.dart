import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../../attendance/domain/attendance_entry.dart';
import '../../members/domain/member.dart';
import '../../payments/domain/payment.dart';
import '../../subscriptions/domain/gym_subscription.dart';
import '../../subscriptions/domain/subscription_rules.dart';

class DashboardRepository {
  const DashboardRepository(this.db, this.session);
  final LocalDatabase db;
  final StaffSession session;

  Stream<DashboardMetrics> watch() {
    final now = DateTime.now().toUtc();
    final today = gymDate(now, session.timezone);
    // Filtre attendance a soti nan kòmansman jounen an (ak yon tanpon 1 jou pou diferans UTC/lokal)
    final recentScanThreshold = today.subtract(const Duration(days: 1)).toIso8601String();

    return db
        .customSelect(
          "SELECT entity, payload FROM records "
          "WHERE gym_id = ? AND deleted_at IS NULL "
          "AND ("
          "  entity IN ('members', 'subscriptions', 'payments') "
          "  OR (entity = 'attendance' AND json_extract(payload, '\$.scanned_at') >= ?)"
          ")",
          variables: [
            Variable.withString(db.gymId),
            Variable.withString(recentScanThreshold),
          ],
          readsFrom: {db.records},
        )
        .watch()
        .map((rows) => _metrics(rows));
  }

  DashboardMetrics _metrics(List<QueryRow> rows) {
    final members = <Member>[];
    final subscriptions = <GymSubscription>[];
    final payments = <GymPayment>[];
    final attendance = <AttendanceEntry>[];

    for (final row in rows) {
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload')) as Map,
      );
      final entity = row.read<String>('entity');
      if (entity == 'members') {
        members.add(Member(payload));
      } else if (entity == 'subscriptions') {
        subscriptions.add(GymSubscription(payload));
      } else if (entity == 'payments') {
        payments.add(GymPayment(payload));
      } else if (entity == 'attendance') {
        attendance.add(AttendanceEntry(payload));
      }
    }

    final today = gymDate(DateTime.now().toUtc(), session.timezone);
    final expiringLimit = today.add(const Duration(days: 30));
    final expiring = <String>{};
    var pendingSubscriptions = 0;
    var pendingAmount = 0.0;

    // Indexation O(1) peman pa subscription_id pou evite bouk O(S * P)
    final paymentsBySub = <String, double>{};
    final todaysPayments = <GymPayment>[];
    for (final payment in payments) {
      if (payment.deletedAt != null) continue;
      if (payment.subscriptionId != null) {
        paymentsBySub[payment.subscriptionId!] =
            (paymentsBySub[payment.subscriptionId!] ?? 0) + payment.amount;
      }
      if (gymDate(payment.paidAt, session.timezone) == today) {
        todaysPayments.add(payment);
      }
    }

    for (final subscription in subscriptions) {
      if (subscription.deletedAt != null) continue;
      if (subscription.status == 'pending') {
        pendingSubscriptions++;
        final paid = paymentsBySub[subscription.id] ?? 0.0;
        pendingAmount += subscription.remainingAfter(paid);
      }
      if (subscription.status == 'active' &&
          !subscription.endDate.isBefore(today) &&
          !subscription.endDate.isAfter(expiringLimit)) {
        expiring.add(subscription.memberId);
      }
    }

    var entriesToday = 0;
    var deniedToday = 0;
    for (final entry in attendance) {
      if (gymDate(entry.scannedAt, session.timezone) == today) {
        if (entry.result.startsWith('granted')) {
          entriesToday++;
        } else {
          deniedToday++;
        }
      }
    }

    var activeMembers = 0;
    var suspendedMembers = 0;
    for (final member in members) {
      if (member.status == 'active' && member.deletedAt == null) {
        activeMembers++;
      } else if (member.status == 'suspended') {
        suspendedMembers++;
      }
    }

    return DashboardMetrics(
      activeMembers: activeMembers,
      suspendedMembers: suspendedMembers,
      expiringMembers: expiring.length,
      pendingSubscriptions: pendingSubscriptions,
      pendingAmount: pendingAmount,
      paymentsToday: todaysPayments.length,
      revenueToday: todaysPayments.fold<double>(
        0,
        (total, payment) => total + payment.amount,
      ),
      entriesToday: entriesToday,
      deniedToday: deniedToday,
    );
  }
}

class DashboardMetrics {
  const DashboardMetrics({
    required this.activeMembers,
    required this.suspendedMembers,
    required this.expiringMembers,
    required this.pendingSubscriptions,
    required this.pendingAmount,
    required this.paymentsToday,
    required this.revenueToday,
    required this.entriesToday,
    required this.deniedToday,
  });
  final int activeMembers;
  final int suspendedMembers;
  final int expiringMembers;
  final int pendingSubscriptions;
  final double pendingAmount;
  final int paymentsToday;
  final double revenueToday;
  final int entriesToday;
  final int deniedToday;
}
