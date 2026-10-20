import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/sync/sync_models.dart';
import 'package:gym_desk/features/staff/domain/staff_profile.dart';

void main() {
  group('Staff Profile & Permissions', () {
    test('extracts permissions and job title correctly', () {
      final json = {
        'id': 'st-1',
        'user_id': 'u-1',
        'gym_id': 'g-1',
        'role': 'reception',
        'full_name': 'Marie Claire',
        'active': true,
        'updated_at': '2026-10-20T10:00:00Z',
        'permissions': {
          'job_title': 'caissier',
          'can_add_members': true,
          'can_cashier': true,
          'can_view_payments': true,
          'can_view_receipts': true,
          'can_view_reports': false,
          'can_manage_plans': false,
          'can_access_control': true,
        },
      };

      final profile = StaffProfile.fromJson(json);
      expect(profile.jobTitle, 'caissier');
      expect(profile.canAddMembers, isTrue);
      expect(profile.canCashier, isTrue);
      expect(profile.canViewPayments, isTrue);
      expect(profile.canViewReceipts, isTrue);
      expect(profile.canViewReports, isFalse);
      expect(profile.canManagePlans, isFalse);
      expect(profile.canAccessControl, isTrue);
    });

    test('defaults gracefully when permissions are missing', () {
      final json = {
        'id': 'st-2',
        'user_id': 'u-2',
        'gym_id': 'g-1',
        'role': 'reception',
        'full_name': 'Jean Baptiste',
        'active': true,
        'updated_at': '2026-10-20T10:00:00Z',
      };

      final profile = StaffProfile.fromJson(json);
      expect(profile.jobTitle, 'reception');
      expect(profile.canAddMembers, isTrue);
      expect(profile.canCashier, isTrue);
      expect(profile.canViewReports, isFalse);
      expect(profile.canManagePlans, isFalse);
      expect(profile.canAccessControl, isTrue);
      expect(profile.fingerprintRegistered, isFalse);
      expect(profile.fingerprintTemplate, isNull);
    });

    test('serializes and deserializes fingerprint data correctly', () {
      final json = {
        'id': 'st-3',
        'user_id': 'u-3',
        'gym_id': 'g-1',
        'role': 'manager',
        'full_name': 'Owner Gym',
        'active': true,
        'updated_at': '2026-10-20T10:00:00Z',
        'permissions': {'job_title': 'superviseur'},
        'fingerprint_template': 'BASE64_TEMPLATE_PRIMARY_1234567890',
        'fingerprint_backup_template': 'BASE64_TEMPLATE_BACKUP_1234567890',
        'fingerprint_registered': true,
        'fingerprint_enrolled_at': '2026-10-20T10:05:00Z',
      };

      final profile = StaffProfile.fromJson(json);
      expect(profile.fingerprintRegistered, isTrue);
      expect(profile.fingerprintTemplate, 'BASE64_TEMPLATE_PRIMARY_1234567890');
      expect(profile.fingerprintBackupTemplate, 'BASE64_TEMPLATE_BACKUP_1234567890');
      expect(profile.fingerprintEnrolledAt, '2026-10-20T10:05:00Z');

      final serialized = profile.toJson();
      expect(serialized['fingerprint_registered'], isTrue);
      expect(serialized['fingerprint_template'], 'BASE64_TEMPLATE_PRIMARY_1234567890');
      expect(serialized['fingerprint_backup_template'], 'BASE64_TEMPLATE_BACKUP_1234567890');
      expect(serialized['fingerprint_enrolled_at'], '2026-10-20T10:05:00Z');
      expect(serialized['full_name'], 'Owner Gym');
    });
  });

  group('StaffSession Permission Checks', () {
    test('owner always bypasses all restrictions', () {
      final session = StaffSession(
        staff: {
          'id': 'st-owner',
          'user_id': 'u-owner',
          'role': 'owner',
          'active': true,
          'permissions': {
            'can_view_reports': false, // Even if somehow set to false
          },
        },
        gym: {'id': 'g-1', 'status': 'active'},
        verifiedAt: DateTime.now().toUtc(),
      );

      expect(session.isOwner, isTrue);
      expect(session.canAddMembers, isTrue);
      expect(session.canCashier, isTrue);
      expect(session.canViewPayments, isTrue);
      expect(session.canViewReceipts, isTrue);
      expect(session.canViewReports, isTrue);
      expect(session.canManagePlans, isTrue);
      expect(session.canAccessControl, isTrue);
    });

    test('secretary role restricts cashier and financial views', () {
      final session = StaffSession(
        staff: {
          'id': 'st-sec',
          'user_id': 'u-sec',
          'role': 'reception',
          'active': true,
          'permissions': {
            'job_title': 'secretaire',
            'can_add_members': true,
            'can_cashier': false,
            'can_view_payments': false,
            'can_view_receipts': true,
            'can_view_reports': false,
            'can_manage_plans': false,
            'can_access_control': true,
          },
        },
        gym: {'id': 'g-1', 'status': 'active'},
        verifiedAt: DateTime.now().toUtc(),
      );

      expect(session.jobTitle, 'secretaire');
      expect(session.canAddMembers, isTrue);
      expect(session.canCashier, isFalse);
      expect(session.canViewPayments, isFalse);
      expect(session.canViewReceipts, isTrue);
      expect(session.canViewReports, isFalse);
      expect(session.canManagePlans, isFalse);
      expect(session.canAccessControl, isTrue);
    });

    test('supervisor has administrative permissions', () {
      final session = StaffSession(
        staff: {
          'id': 'st-sup',
          'user_id': 'u-sup',
          'role': 'supervisor',
          'active': true,
          'permissions': {
            'job_title': 'superviseur',
            'can_add_members': true,
            'can_cashier': true,
            'can_view_payments': true,
            'can_view_receipts': true,
            'can_view_reports': true,
            'can_manage_plans': true,
            'can_access_control': true,
          },
        },
        gym: {'id': 'g-1', 'status': 'active'},
        verifiedAt: DateTime.now().toUtc(),
      );

      expect(session.jobTitle, 'superviseur');
      expect(session.canViewReports, isTrue);
      expect(session.canManagePlans, isTrue);
      expect(session.canCashier, isTrue);
    });

    test('switching session with unlocked staff updates role and permissions', () {
      final initialSession = StaffSession(
        staff: {
          'id': 'st-sec',
          'user_id': 'u-sec',
          'role': 'reception',
          'active': true,
          'permissions': {'job_title': 'secretaire', 'can_cashier': false},
        },
        gym: {'id': 'g-1', 'status': 'active'},
        verifiedAt: DateTime.now().toUtc(),
      );

      expect(initialSession.canCashier, isFalse);
      expect(initialSession.jobTitle, 'secretaire');

      final cashierProfile = StaffProfile(
        id: 'st-cashier',
        userId: 'u-cashier',
        gymId: 'g-1',
        role: 'reception',
        fullName: 'Jean Cashier',
        active: true,
        updatedAt: '2026-10-20T10:00:00Z',
        permissions: {'job_title': 'caissier', 'can_cashier': true},
        fingerprintRegistered: true,
        fingerprintTemplate: 'FP_TEMPLATE_ABC',
      );

      final unlockedSession = StaffSession(
        staff: cashierProfile.toJson(),
        gym: initialSession.gym,
        verifiedAt: DateTime.now().toUtc(),
      );

      expect(unlockedSession.staffId, 'st-cashier');
      expect(unlockedSession.jobTitle, 'caissier');
      expect(unlockedSession.canCashier, isTrue);
    });
  });
}
