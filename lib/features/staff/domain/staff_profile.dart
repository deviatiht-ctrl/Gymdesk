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
  );
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
  });

  final String requestId;
  final String staffId;
  final String email;
  final String fullName;
  final String phone;
  final String role;
  final String password;

  Json toJson() => {
    'action': 'create_staff',
    'request_id': requestId,
    'staff_id': staffId,
    'email': email,
    'full_name': fullName,
    'phone': phone,
    'role': role,
    'password': password,
  };
}

class StaffFailure implements Exception {
  const StaffFailure(this.code);
  final String code;
}
