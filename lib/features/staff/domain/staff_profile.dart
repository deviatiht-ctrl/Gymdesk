import '../../../core/sync/sync_models.dart';

class StaffProfile {
  const StaffProfile({
    required this.id,
    required this.userId,
    required this.gymId,
    required this.role,
    required this.fullName,
    required this.active,
    required this.updatedAt,
    this.phone,
    this.deletedAt,
    this.permissions = const {},
    this.fingerprintTemplate,
    this.fingerprintBackupTemplate,
    this.fingerprintRegistered = false,
    this.fingerprintEnrolledAt,
  });

  final String id;
  final String userId;
  final String gymId;
  final String role;
  final String fullName;
  final bool active;
  final String updatedAt;
  final String? phone;
  final String? deletedAt;
  final Map<String, dynamic> permissions;
  final String? fingerprintTemplate;
  final String? fingerprintBackupTemplate;
  final bool fingerprintRegistered;
  final String? fingerprintEnrolledAt;

  String get jobTitle => permissions['job_title'] as String? ?? (role == 'supervisor' || role == 'manager' ? 'superviseur' : 'reception');
  bool get canAddMembers => permissions['can_add_members'] as bool? ?? true;
  bool get canCashier => permissions['can_cashier'] as bool? ?? (role != 'secretaire');
  bool get canViewPayments => permissions['can_view_payments'] as bool? ?? true;
  bool get canViewReceipts => permissions['can_view_receipts'] as bool? ?? true;
  bool get canViewReports => permissions['can_view_reports'] as bool? ?? (role == 'manager' || role == 'supervisor');
  bool get canManagePlans => permissions['can_manage_plans'] as bool? ?? (role == 'manager' || role == 'supervisor');
  bool get canAccessControl => permissions['can_access_control'] as bool? ?? true;

  factory StaffProfile.fromJson(Json json) => StaffProfile(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    gymId: json['gym_id'] as String,
    role: json['role'] as String,
    fullName: json['full_name'] as String,
    active: json['active'] == true,
    updatedAt: json['updated_at'] as String,
    phone: json['phone'] as String?,
    deletedAt: json['deleted_at'] as String?,
    permissions: json['permissions'] is Map
        ? Map<String, dynamic>.from(json['permissions'] as Map)
        : const {},
    fingerprintTemplate: json['fingerprint_template'] as String?,
    fingerprintBackupTemplate: json['fingerprint_backup_template'] as String?,
    fingerprintRegistered: json['fingerprint_registered'] == true,
    fingerprintEnrolledAt: json['fingerprint_enrolled_at'] as String?,
  );

  Json toJson() {
    final map = <String, dynamic>{
      'id': id,
      'user_id': userId,
      'gym_id': gymId,
      'role': role,
      'full_name': fullName,
      'active': active,
      'updated_at': updatedAt,
      'permissions': permissions,
      'fingerprint_registered': fingerprintRegistered,
    };
    if (phone != null) map['phone'] = phone;
    if (deletedAt != null) map['deleted_at'] = deletedAt;
    if (fingerprintTemplate != null) map['fingerprint_template'] = fingerprintTemplate;
    if (fingerprintBackupTemplate != null) map['fingerprint_backup_template'] = fingerprintBackupTemplate;
    if (fingerprintEnrolledAt != null) map['fingerprint_enrolled_at'] = fingerprintEnrolledAt;
    return map;
  }
}

class CreateStaffCommand {
  const CreateStaffCommand({
    required this.requestId,
    required this.staffId,
    required this.email,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.password,
    this.permissions = const {},
  });

  final String requestId;
  final String staffId;
  final String email;
  final String fullName;
  final String phone;
  final String role;
  final String password;
  final Map<String, dynamic> permissions;

  Json toJson() => {
    'action': 'create_staff',
    'request_id': requestId,
    'staff_id': staffId,
    'email': email,
    'full_name': fullName,
    'phone': phone,
    'role': role,
    'password': password,
    if (permissions.isNotEmpty) 'permissions': permissions,
  };
}

class StaffFailure implements Exception {
  const StaffFailure(this.code);
  final String code;
}
