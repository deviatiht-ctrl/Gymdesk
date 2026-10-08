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

  Stream<DashboardMetrics> watch() => db
      .customSelect(
        "SELECT entity, payload FROM records WHERE gym_id = ? AND deleted_at IS NULL",
        variables: [Variable.withString(db.gymId)],
        readsFrom: {db.records},
      )
      .watch()
      .map((rows) => _metrics(rows));

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
    for (final subscription in subscriptions.where(
      (subscription) => subscription.deletedAt == null,
    )) {
      if (subscription.status == 'pending') {
        pendingSubscriptions++;
        final paid = payments
            .where(
              (payment) =>
                  payment.subscriptionId == subscription.id &&
                  payment.deletedAt == null,
            )
            .fold<double>(0, (total, payment) => total + payment.amount);
        pendingAmount += subscription.remainingAfter(paid);
      }
      if (subscription.status == 'active' &&
          !subscription.endDate.isBefore(today) &&
          !subscription.endDate.isAfter(expiringLimit)) {
        expiring.add(subscription.memberId);
      }
    }
    final todaysPayments = payments
        .where(
          (payment) =>
              payment.deletedAt == null &&
              gymDate(payment.paidAt, session.timezone) == today,
        )
        .toList();
    final todaysAttendance = attendance
        .where((entry) => gymDate(entry.scannedAt, session.timezone) == today)
        .toList();
    return DashboardMetrics(
      activeMembers: members
          .where(
            (member) => member.status == 'active' && member.deletedAt == null,
          )
          .length,
      suspendedMembers: members
          .where((member) => member.status == 'suspended')
          .length,
      expiringMembers: expiring.length,
      pendingSubscriptions: pendingSubscriptions,
      pendingAmount: pendingAmount,
      paymentsToday: todaysPayments.length,
      revenueToday: todaysPayments.fold<double>(
        0,
        (total, payment) => total + payment.amount,
      ),
      entriesToday: todaysAttendance
          .where((entry) => entry.result == 'granted')
          .length,
      deniedToday: todaysAttendance
          .where((entry) => entry.result != 'granted')
          .length,
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
