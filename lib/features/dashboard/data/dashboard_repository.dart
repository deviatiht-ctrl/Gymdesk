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
          "  entity IN ('members', 'subscriptions', 'payments', 'gym_contracts') "
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
    Map<String, dynamic>? activeContract;

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
      } else if (entity == 'gym_contracts') {
        if ({'active', 'trial', 'grace'}.contains(payload['status'])) {
          activeContract = payload;
        }
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

    final snapshot = activeContract?['price_snapshot'] as Map? ?? {};
    final contractConfig = snapshot['config'] as Map? ?? {};
    final offerId = (activeContract?['offer_id'] ?? snapshot['offer_id'])?.toString() ?? '';
    final offerName = (snapshot['name'] ?? activeContract?['name'])?.toString();

    final gymSettings = session.gym?['settings'] as Map? ?? {};
    final gymOfferId = session.gym?['offer_id']?.toString() ?? gymSettings['offer_id']?.toString() ?? '';
    final gymOfferName = session.gym?['plan_name']?.toString() ?? gymSettings['plan_name']?.toString();

    final isUnlimited = offerId == 'plan_enterprise' ||
        offerId == 'unlimited_annual' ||
        offerId.toLowerCase().contains('unlimited') ||
        offerId.toLowerCase().contains('illimit') ||
        gymOfferId == 'plan_enterprise' ||
        gymOfferId == 'unlimited_annual' ||
        gymOfferId.toLowerCase().contains('unlimited') ||
        gymOfferId.toLowerCase().contains('illimit') ||
        (offerName != null && (offerName.toLowerCase().contains('illimit') || offerName.toLowerCase().contains('unlimited'))) ||
        (gymOfferName != null && (gymOfferName.toLowerCase().contains('illimit') || gymOfferName.toLowerCase().contains('unlimited'))) ||
        (contractConfig['max_members'] != null && (contractConfig['max_members'] as num).toInt() == 0) ||
        contractConfig['is_unlimited'] == true ||
        (gymSettings['max_members'] != null && (gymSettings['max_members'] as num).toInt() == 0) ||
        gymSettings['is_unlimited'] == true;

    final resolvedMax = isUnlimited
        ? 0
        : ((contractConfig['max_members'] as num?)?.toInt() ??
            (gymSettings['max_members'] as num?)?.toInt() ??
            1000);

    final resolvedPlanName = offerName ?? gymOfferName ?? (isUnlimited ? 'Plan Illimité' : null);

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
      maxMembers: resolvedMax,
      isUnlimitedPlan: isUnlimited,
      planName: resolvedPlanName,
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
    this.maxMembers = 1000,
    this.isUnlimitedPlan = false,
    this.planName,
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
  final int maxMembers;
  final bool isUnlimitedPlan;
  final String? planName;
}
