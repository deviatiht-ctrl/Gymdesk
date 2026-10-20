import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../../attendance/domain/attendance_entry.dart';
import '../../members/domain/member.dart';
import '../../payments/domain/currency.dart';
import '../../payments/domain/payment.dart';
import '../../subscriptions/domain/gym_subscription.dart';
import '../../subscriptions/domain/subscription_rules.dart';

class ReportsRepository {
  const ReportsRepository(this.db, this.session);
  final LocalDatabase db;
  final StaffSession session;

  Future<ReportSnapshot> load({
    required DateTime start,
    required DateTime end,
  }) async {
    final startDate = dateOnly(start);
    final endDate = dateOnly(end);
    final members = <String, Member>{};
    final staff = <String, Json>{};
    final subscriptions = <String, GymSubscription>{};
    final payments = <GymPayment>[];
    final attendance = <AttendanceEntry>[];
    final audit = <AuditEntry>[];
    final rows = await db
        .customSelect(
          "SELECT entity, payload FROM records WHERE gym_id = ? AND deleted_at IS NULL",
          variables: [Variable.withString(db.gymId)],
          readsFrom: {db.records},
        )
        .get();
    for (final row in rows) {
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload')) as Map,
      );
      final entity = row.read<String>('entity');
      if (entity == 'members') {
        members[payload['id'] as String] = Member(payload);
      } else if (entity == 'staff') {
        staff[payload['id'] as String] = payload;
      } else if (entity == 'subscriptions') {
        subscriptions[payload['id'] as String] = GymSubscription(payload);
      } else if (entity == 'payments') {
        final payment = GymPayment(payload);
        if (!_outside(
          gymDate(payment.paidAt, session.timezone),
          startDate,
          endDate,
        )) {
          payments.add(payment);
        }
      } else if (entity == 'attendance') {
        final entry = AttendanceEntry(payload);
        if (!_outside(
          gymDate(entry.scannedAt, session.timezone),
          startDate,
          endDate,
        )) {
          attendance.add(entry);
        }
      } else if (entity == 'audit_log') {
        final entry = AuditEntry(payload);
        if (!_outside(
          gymDate(entry.createdAt, session.timezone),
          startDate,
          endDate,
        )) {
          audit.add(entry);
        }
      }
    }
    payments.sort((a, b) => b.paidAt.compareTo(a.paidAt));
    attendance.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    audit.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final expiring =
        subscriptions.values
            .where(
              (subscription) =>
                  subscription.status == 'active' &&
                  !subscription.endDate.isBefore(endDate) &&
                  !subscription.endDate.isAfter(
                    endDate.add(const Duration(days: 30)),
                  ),
            )
            .toList()
          ..sort((a, b) => a.endDate.compareTo(b.endDate));
    return ReportSnapshot(
      start: startDate,
      end: endDate,
      members: members,
      staff: staff,
      subscriptions: subscriptions,
      payments: payments,
      attendance: attendance,
      audit: audit,
      expiring: expiring,
    );
  }

  bool _outside(DateTime value, DateTime start, DateTime end) {
    final v = dateOnly(value);
    return v.isBefore(start) || v.isAfter(end);
  }

  Future<String> sendDailyReportEmail({
    required DateTime date,
    required ReportSnapshot report,
    required SupabaseClient client,
  }) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final newMembersCount = report.members.values.where((m) {
      final created = m.row['created_at'] != null ? DateTime.tryParse(m.row['created_at'].toString()) : null;
      if (created == null) return false;
      final cDate = dateOnly(gymDate(created, session.timezone));
      return cDate == dateOnly(date);
    }).length;

    final payload = <String, dynamic>{
      'report_date': dateStr,
      'total_usd': report.collected['USD'] ?? 0.0,
      'total_htg': report.collected['HTG'] ?? 0.0,
      'total_registration_fees': report.totalRegistrationFees,
      'total_subscriptions': report.totalPlanFees,
      'payments_count': report.payments.length,
      'checkins_count': report.granted,
      'new_members_count': newMembersCount,
    };

    try {
      final res = await client.rpc('enqueue_daily_report', params: {
        'p_report_date': dateStr,
        'p_payload': payload,
      });
      return res?.toString() ?? 'queued';
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const ReportsFailure('access_denied');
      throw ReportsFailure(e.message);
    } catch (e) {
      throw ReportsFailure(e.toString());
    }
  }
}

class ReportsFailure implements Exception {
  const ReportsFailure(this.code);
  final String code;
  @override
  String toString() => code;
}

class ReportSnapshot {
  const ReportSnapshot({
    required this.start,
    required this.end,
    required this.members,
    required this.staff,
    required this.subscriptions,
    required this.payments,
    required this.attendance,
    required this.audit,
    required this.expiring,
  });
  final DateTime start;
  final DateTime end;
  final Map<String, Member> members;
  final Map<String, Json> staff;
  final Map<String, GymSubscription> subscriptions;
  final List<GymPayment> payments;
  final List<AttendanceEntry> attendance;
  final List<AuditEntry> audit;
  final List<GymSubscription> expiring;

  double get revenue =>
      payments.fold<double>(0, (total, payment) => total + payment.amount);

  /// Billets réellement encaissés par devise (USD / HTG).
  Map<String, double> get collected => collectedByCurrency(payments.map((p) => p.row));

  /// Total des frais d'inscription encaissés.
  double get totalRegistrationFees =>
      payments.fold<double>(0, (total, payment) => total + payment.registrationFee);

  /// Total des abonnements / cotisations réguliers encaissés.
  double get totalPlanFees =>
      payments.fold<double>(0, (total, payment) => total + payment.planFee);

  /// Frais d'inscription ventilés par devise.
  Map<String, double> get registrationCollected =>
      collectedByCurrency(payments.map((p) => {
        ...p.row,
        'amount': p.registrationFee,
        'received_amount': p.registrationFee,
      }));

  /// Abonnements / cotisations ventilés par devise.
  Map<String, double> get planFeesCollected =>
      collectedByCurrency(payments.map((p) => {
        ...p.row,
        'amount': p.planFee,
        'received_amount': p.planFee,
      }));

  int get granted =>
      attendance.where((entry) => entry.result == 'granted').length;
  int get denied => attendance.length - granted;
  String memberName(String? id) =>
      id == null ? '' : members[id]?.fullName ?? id;
  String staffName(String? id) =>
      id == null ? '' : staff[id]?['full_name'] as String? ?? id;
}

class AuditEntry {
  const AuditEntry(this.row);
  final Json row;
  String get id => row['id'] as String;
  String? get actorId => row['actor_id'] as String?;
  String get action => row['action'] as String? ?? '';
  String get entity => row['entity'] as String? ?? '';
  String? get entityId => row['entity_id'] as String?;
  DateTime get createdAt => DateTime.parse(row['created_at'] as String);
  Json get details => Map<String, dynamic>.from(row['details'] as Map? ?? {});
}
