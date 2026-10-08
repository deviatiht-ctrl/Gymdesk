import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../../attendance/domain/attendance_entry.dart';
import '../../members/domain/member.dart';
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

  bool _outside(DateTime value, DateTime start, DateTime end) =>
      value.isBefore(start) || value.isAfter(end);
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
