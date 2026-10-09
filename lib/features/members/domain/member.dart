import 'dart:math';
import 'dart:typed_data';

import '../../../core/sync/sync_models.dart';

class Member {
  const Member(this.row);
  final Json row;

  String get id => row['id'] as String;
  String get gymId => row['gym_id'] as String;
  String get memberNumber => row['member_number'] as String? ?? '';
  String get qrToken => row['qr_token'] as String? ?? '';
  String get firstName => row['first_name'] as String? ?? '';
  String get lastName => row['last_name'] as String? ?? '';
  String get fullName => '$firstName $lastName'.trim();
  String? get sex => row['sex'] as String?;
  DateTime? get birthDate =>
      DateTime.tryParse(row['birth_date'] as String? ?? '');
  String? get phone => row['phone'] as String?;
  String? get whatsapp => row['whatsapp'] as String?;
  String? get email => row['email'] as String?;
  String? get address => row['address'] as String?;
  String? get nif => row['nif'] as String?;
  String? get cin => row['cin'] as String?;
  String? get emergencyName => row['emergency_contact_name'] as String?;
  String? get emergencyPhone => row['emergency_contact_phone'] as String?;
  String? get guardianName => row['guardian_name'] as String?;
  String? get photoUrl => row['photo_url'] as String?;
  String? get notes => row['notes'] as String?;
  String get status => row['status'] as String? ?? 'active';
  Json get qrStyle => Map<String, dynamic>.from(row['qr_style'] as Map? ?? {});
  String? get fingerprintTemplate => row['fingerprint_template'] as String?;
  bool get fingerprintRegistered =>
      row['fingerprint_registered'] == true ||
      (row['fingerprint_template'] as String?)?.isNotEmpty == true;
  String get updatedAt => row['updated_at'] as String;
  String? get deletedAt => row['deleted_at'] as String?;

  int? ageOn(DateTime date) {
    final birth = birthDate;
    if (birth == null) return null;
    var age = date.year - birth.year;
    if (date.month < birth.month ||
        (date.month == birth.month && date.day < birth.day)) {
      age--;
    }
    return age;
  }

  String qrPayload(String gymCode) => 'GD1|$gymCode|$memberNumber|$qrToken';
}

String normalizePhone(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits.length == 8) return '+509$digits';
  if (digits.length == 11 && digits.startsWith('509')) return '+$digits';
  return value.startsWith('+') ? '+$digits' : digits;
}

String? normalizeNif(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.length != 10) throw const MemberFailure('invalid_nif');
  return digits;
}

String formatNif(String digits) => digits.length == 10
    ? '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6, 9)}-${digits.substring(9)}'
    : digits;

String generateQrToken() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  final random = Random.secure();
  return List.generate(
    40,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

class MemberRegistration {
  const MemberRegistration({
    required this.firstName,
    required this.lastName,
    this.sex,
    this.birthDate,
    this.phone = '',
    this.whatsapp = '',
    this.email = '',
    this.address = '',
    this.nif = '',
    this.cin = '',
    this.emergencyName = '',
    this.emergencyPhone = '',
    this.guardianName = '',
    this.notes = '',
    this.photo,
  });

  final String firstName;
  final String lastName;
  final String? sex;
  final DateTime? birthDate;
  final String phone;
  final String whatsapp;
  final String email;
  final String address;
  final String nif;
  final String cin;
  final String emergencyName;
  final String emergencyPhone;
  final String guardianName;
  final String notes;
  final Uint8List? photo;
}

class MemberDuplicate {
  const MemberDuplicate({required this.member, required this.reason});
  final Member member;
  final String reason;
}

class MemberRegistrationResult {
  const MemberRegistrationResult({
    required this.memberId,
    required this.memberNumber,
    this.subscriptionId,
    this.paymentId,
  });
  final String memberId;
  final String memberNumber;
  final String? subscriptionId;
  final String? paymentId;
}

class MemberFailure implements Exception {
  const MemberFailure(this.code);
  final String code;
}
