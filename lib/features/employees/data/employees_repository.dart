import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../domain/employee.dart';

class EmployeeFailure implements Exception {
  const EmployeeFailure(this.code);
  final String code;
}

class EmployeesRepository {
  const EmployeesRepository(this.db, this.session, {this.now});
  final LocalDatabase db;
  final StaffSession session;
  final DateTime Function()? now;
  static const _uuid = Uuid();

  DateTime get _now => (now ?? () => DateTime.now().toUtc())();

  Stream<List<Employee>> watch() =>
      db.watchRecords(SyncEntity.employees, limit: 5000).map((rows) {
        final list = [
          for (final r in rows)
            Employee(Map<String, dynamic>.from(jsonDecode(r.payload) as Map)),
        ]..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
        return list;
      });

  Future<List<Employee>> all() => watch().first;

  bool get _canManage => session.canManageGym || session.role == 'reception';

  /// Kreye oswa modifye yon anplwaye. Retounen id li.
  Future<String> save({
    Employee? existing,
    required String firstName,
    required String lastName,
    required String jobType,
    String phone = '',
    String email = '',
    String jobTitle = '',
    String notes = '',
    bool active = true,
  }) async {
    if (!_canManage) throw const EmployeeFailure('access_denied');
    final first = firstName.trim();
    if (first.isEmpty || first.length > 80 || lastName.trim().length > 80) {
      throw const EmployeeFailure('invalid_record');
    }
    if (!Employee.jobTypes.contains(jobType)) throw const EmployeeFailure('invalid_record');
    final mail = email.trim().toLowerCase();
    if (mail.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(mail)) {
      throw const EmployeeFailure('invalid_email');
    }
    final id = existing?.id ?? _uuid.v4();
    final row = <String, dynamic>{
      ...?existing?.row,
      'id': id,
      'gym_id': db.gymId,
      'first_name': first,
      'last_name': lastName.trim(),
      'phone': phone.trim().isEmpty ? null : phone.trim(),
      'email': mail.isEmpty ? null : mail,
      'job_type': jobType,
      'job_title': jobTitle.trim().isEmpty ? null : jobTitle.trim(),
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'active': active,
      'fingerprint_templates': existing?.row['fingerprint_templates'] ?? const <String>[],
      'fingerprint_registered': existing?.fingerprintRegistered ?? false,
    };
    await _write(row);
    return id;
  }

  Future<void> saveFingerprints(Employee employee, List<String> captures) async {
    if (!_canManage) throw const EmployeeFailure('access_denied');
    final templates = captures.where((t) => t.isNotEmpty).toList();
    if (templates.isEmpty) throw const EmployeeFailure('invalid_record');
    // Dènye kapti a (verifye kont premye a) se template prensipal la;
    // nou kenbe 2 kapti diferan pou W2 a (2 template pa dwèt).
    final pair = templates.length >= 2 ? [templates.last, templates.first] : [templates.last];
    await _write({
      ...employee.row,
      'fingerprint_template': pair.first,
      'fingerprint_templates': pair,
      'fingerprint_registered': true,
    });
  }

  Future<void> clearFingerprints(Employee employee) async {
    if (!_canManage) throw const EmployeeFailure('access_denied');
    await _write({
      ...employee.row,
      'fingerprint_template': null,
      'fingerprint_templates': const <String>[],
      'fingerprint_registered': false,
    });
  }

  Future<void> archive(Employee employee) async {
    if (!session.canManageGym) throw const EmployeeFailure('access_denied');
    try {
      await db.save(SyncEntity.employees, employee.row, changedAt: _now, deleting: true);
    } on SyncRejected catch (e) {
      throw EmployeeFailure(e.code);
    }
  }

  Future<void> _write(Json row) async {
    try {
      await db.save(SyncEntity.employees, row, changedAt: _now);
    } on SyncRejected catch (e) {
      throw EmployeeFailure(e.code);
    } catch (_) {
      throw const EmployeeFailure('local_storage');
    }
  }
}
