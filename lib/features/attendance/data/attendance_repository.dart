import 'dart:convert';
import 'package:uuid/uuid.dart';

import '../../../core/db/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../../badges/domain/badge.dart';
import '../../members/data/member_pin_service.dart';
import '../../members/domain/member.dart';
import '../../members/domain/member_pin.dart';
import '../../subscriptions/domain/gym_subscription.dart';
import '../../subscriptions/domain/subscription_rules.dart';
import '../domain/attendance_entry.dart';

class BadgeLookupResult {
  const BadgeLookupResult({
    required this.status,
    this.badge,
    this.member,
    this.message = '',
  });

  final String status; // 'ready_for_pin', 'denied_unactivated', 'denied_blocked_badge', 'denied_unknown'
  final BadgeItem? badge;
  final Member? member;
  final String message;

  bool get requiresPin => status == 'ready_for_pin';
}

class AttendanceRepository {
  const AttendanceRepository(this.db, this.session);
  final LocalDatabase db;
  final StaffSession session;
  static const _uuid = Uuid();

  Stream<List<AttendanceEntry>> watch({int limit = 100}) =>
      db.watchRecords(SyncEntity.attendance, limit: limit).map((rows) {
        final entries = rows
            .map((row) => AttendanceEntry(
                  Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
                ))
            .toList();
        entries.sort((a, b) => a.scannedAt != b.scannedAt
            ? b.scannedAt.compareTo(a.scannedAt)
            : b.id.compareTo(a.id));
        return entries;
      });

  /// Analyse et validation immédiate de la carte avant saisie du PIN
  Future<BadgeLookupResult> resolveBadge(String raw) async {
    final parts = raw.trim().split('|');
    final gymCode = session.gym?['code'] ?? '';

    String? token;

    if (parts.length >= 4 && (parts[0] == 'GD2' || parts[0] == 'GD1')) {
      if (parts[1] != gymCode) {
        return const BadgeLookupResult(
          status: 'denied_unknown',
          message: 'scan_denied_other_gym',
        );
      }
      token = parts[3];
    } else {
      token = raw.trim();
    }

    final record = await db.badgeByToken(token);
    if (record == null) {
      // Vérifier si le token correspond à un ancien membre V1
      final memberRecord = await _memberByToken(token);
      if (memberRecord == null) {
        return const BadgeLookupResult(
          status: 'denied_unknown',
          message: 'scan_denied_unknown',
        );
      }
      // Ancien membre V1 sans badge lié : le traiter directement
      return BadgeLookupResult(
        status: 'ready_for_pin',
        member: memberRecord,
        message: 'scan_enter_pin',
      );
    }

    final badge = BadgeItem(jsonDecode(record.payload) as Map<String, dynamic>);
    if (badge.isAvailable) {
      return BadgeLookupResult(
        status: 'denied_unactivated',
        badge: badge,
        message: 'scan_denied_unactivated',
      );
    }

    if (badge.isBlocked) {
      return BadgeLookupResult(
        status: 'denied_blocked_badge',
        badge: badge,
        message: 'scan_denied_blocked_badge',
      );
    }

    // Badge lié : trouver le membre associé
    Member? member;
    if (badge.memberId != null) {
      final mRecord = await db.record(SyncEntity.members, badge.memberId!);
      if (mRecord != null) {
        member = Member(jsonDecode(mRecord.payload) as Map<String, dynamic>);
      }
    }

    if (member == null) {
      return BadgeLookupResult(
        status: 'denied_unknown',
        badge: badge,
        message: 'scan_denied_unknown',
      );
    }

    return BadgeLookupResult(
      status: 'ready_for_pin',
      badge: badge,
      member: member,
      message: 'scan_enter_pin',
    );
  }

  /// Vérification du PIN et enregistrement de la présence (Mode Kiosque)
  Future<ScanOutcome> verifyPinAndGrant({
    required BadgeLookupResult badgeResult,
    required String pin,
    required DateTime scannedAt,
    required bool offline,
    required bool suspectClock,
  }) async {
    final member = badgeResult.member!;
    final badge = badgeResult.badge;
    final pinService = MemberPinService(db);

    // 1. Vérification du PIN
    final pinCheck = await pinService.verifyPin(member.id, pin);
    final scanTime = scannedAt.toUtc();

    if (!pinCheck.isGranted) {
      final denialResult = pinCheck.status == PinVerifyStatus.pinLocked
          ? 'denied_pin_locked'
          : 'denied_bad_pin';

      final row = <String, dynamic>{
        'id': _uuid.v4(),
        'gym_id': session.gymId,
        'member_id': member.id,
        'badge_id': badge?.id,
        'subscription_id': null,
        'scanned_at': scanTime.toIso8601String(),
        'server_received_at': null,
        'result': denialResult,
        'denial_reason': pinCheck.message,
        'pin_verified': false,
        'entry_number_today': null,
        'device_id': await db.deviceId(),
        'scanned_by': session.staffId,
        'was_offline': offline,
        'suspect_clock': suspectClock,
        'created_at': scanTime.toIso8601String(),
      };
      await db.save(SyncEntity.attendance, row, changedAt: scanTime);

      return ScanOutcome(
        result: denialResult,
        entry: AttendanceEntry(row),
        member: member,
        message: denialResult == 'denied_pin_locked'
            ? 'scan_denied_pin_locked'
            : 'scan_denied_bad_pin',
      );
    }

    // 2. PIN valide : calculer la validité de l'abonnement
    final subscriptions = await _subscriptions(member.id);
    final validity = memberValidity(
      member,
      subscriptions,
      session.settings,
      scanTime,
      session.timezone,
    );

    // Déterminer la direction : entrée (Bienvenue) ou sortie (Au revoir)
    final todayGranted = await _todayGrantedEntries(member.id, scanTime);
    final isEntry = todayGranted.length % 2 == 0;
    final direction = isEntry ? 'in' : 'out';

    String result = 'denied_unknown';
    String? reason = validity.reason;
    int? entryNumber;

    if (validity.valid) {
      if (await _isDuplicate(member.id, scanTime)) {
        result = 'denied_duplicate';
        reason = 'duplicate_scan';
      } else {
        result = 'granted';
        entryNumber = todayGranted.length + 1;
      }
    } else {
      result = switch (validity.reason) {
        'pending_payment' => 'denied_pending_renewal',
        'expired' => 'denied_expired',
        'no_subscription' => 'denied_no_subscription',
        _ => 'denied_suspended',
      };
    }

    final row = <String, dynamic>{
      'id': _uuid.v4(),
      'gym_id': session.gymId,
      'member_id': member.id,
      'badge_id': badge?.id,
      'subscription_id': validity.subscriptionId,
      'scanned_at': scanTime.toIso8601String(),
      'server_received_at': null,
      'result': result,
      'denial_reason': result == 'granted' ? null : reason,
      'pin_verified': true,
      'entry_number_today': entryNumber,
      'direction': direction,
      'device_id': await db.deviceId(),
      'scanned_by': session.staffId,
      'was_offline': offline,
      'suspect_clock': suspectClock,
      'created_at': scanTime.toIso8601String(),
    };
    await db.save(SyncEntity.attendance, row, changedAt: scanTime);

    final outcomeMessage = result == 'granted'
        ? (isEntry ? 'welcome_member' : 'goodbye_member')
        : (result == 'denied_duplicate' ? 'duplicate_scan' : 'scan_$result');

    return ScanOutcome(
      result: result == 'denied_duplicate' ? 'duplicate' : result,
      entry: AttendanceEntry(row),
      member: member,
      message: outcomeMessage,
      direction: direction,
    );
  }

  /// Vérification d'empreinte digitale et enregistrement de présence (Mode Biométrique)
  Future<ScanOutcome> verifyFingerprintAndGrant({
    required Member member,
    BadgeItem? badge,
    required bool fingerprintMatched,
    required DateTime scannedAt,
    required bool offline,
    required bool suspectClock,
  }) async {
    final scanTime = scannedAt.toUtc();

    if (!fingerprintMatched) {
      const denialResult = 'denied_bad_fingerprint';
      final row = <String, dynamic>{
        'id': _uuid.v4(),
        'gym_id': session.gymId,
        'member_id': member.id,
        'badge_id': badge?.id,
        'subscription_id': null,
        'scanned_at': scanTime.toIso8601String(),
        'server_received_at': null,
        'result': denialResult,
        'denial_reason': 'scan_denied_bad_fingerprint',
        'pin_verified': false,
        'fingerprint_verified': false,
        'entry_number_today': null,
        'device_id': await db.deviceId(),
        'scanned_by': session.staffId,
        'was_offline': offline,
        'suspect_clock': suspectClock,
        'created_at': scanTime.toIso8601String(),
      };
      await db.save(SyncEntity.attendance, row, changedAt: scanTime);

      return ScanOutcome(
        result: denialResult,
        entry: AttendanceEntry(row),
        member: member,
        message: 'scan_denied_bad_fingerprint',
      );
    }

    final subscriptions = await _subscriptions(member.id);
    final validity = memberValidity(
      member,
      subscriptions,
      session.settings,
      scanTime,
      session.timezone,
    );

    final todayGranted = await _todayGrantedEntries(member.id, scanTime);
    final isEntry = todayGranted.length % 2 == 0;
    final direction = isEntry ? 'in' : 'out';

    String result = 'denied_unknown';
    String? reason = validity.reason;
    int? entryNumber;

    if (validity.valid) {
      if (await _isDuplicate(member.id, scanTime)) {
        result = 'denied_duplicate';
        reason = 'duplicate_scan';
      } else {
        result = 'granted';
        entryNumber = todayGranted.length + 1;
      }
    } else {
      result = switch (validity.reason) {
        'pending_payment' => 'denied_pending_renewal',
        'expired' => 'denied_expired',
        'no_subscription' => 'denied_no_subscription',
        _ => 'denied_suspended',
      };
    }

    final row = <String, dynamic>{
      'id': _uuid.v4(),
      'gym_id': session.gymId,
      'member_id': member.id,
      'badge_id': badge?.id,
      'subscription_id': validity.subscriptionId,
      'scanned_at': scanTime.toIso8601String(),
      'server_received_at': null,
      'result': result,
      'denial_reason': result == 'granted' ? null : reason,
      'pin_verified': false,
      'fingerprint_verified': true,
      'entry_number_today': entryNumber,
      'direction': direction,
      'device_id': await db.deviceId(),
      'scanned_by': session.staffId,
      'was_offline': offline,
      'suspect_clock': suspectClock,
      'created_at': scanTime.toIso8601String(),
    };
    await db.save(SyncEntity.attendance, row, changedAt: scanTime);

    final outcomeMessage = result == 'granted'
        ? (isEntry ? 'welcome_member' : 'goodbye_member')
        : (result == 'denied_duplicate' ? 'duplicate_scan' : 'scan_$result');

    return ScanOutcome(
      result: result == 'denied_duplicate' ? 'duplicate' : result,
      entry: AttendanceEntry(row),
      member: member,
      message: outcomeMessage,
      direction: direction,
    );
  }

  /// Log direct d'un refus sans PIN (badge inconnu, bloqué, ou vierge)
  Future<ScanOutcome> logImmediateDenial(
    BadgeLookupResult lookup, {
    required DateTime scannedAt,
    required bool offline,
    required bool suspectClock,
  }) async {
    final scanTime = scannedAt.toUtc();
    final row = <String, dynamic>{
      'id': _uuid.v4(),
      'gym_id': session.gymId,
      'member_id': lookup.member?.id,
      'badge_id': lookup.badge?.id,
      'subscription_id': null,
      'scanned_at': scanTime.toIso8601String(),
      'server_received_at': null,
      'result': lookup.status,
      'denial_reason': lookup.message,
      'pin_verified': false,
      'entry_number_today': null,
      'device_id': await db.deviceId(),
      'scanned_by': session.staffId,
      'was_offline': offline,
      'suspect_clock': suspectClock,
      'created_at': scanTime.toIso8601String(),
    };
    await db.save(SyncEntity.attendance, row, changedAt: scanTime);

    return ScanOutcome(
      result: lookup.status,
      entry: AttendanceEntry(row),
      member: lookup.member,
      message: lookup.message,
    );
  }

  Future<Member?> _memberByToken(String token) async {
    final rows = await db.watchRecords(SyncEntity.members, limit: 50000).first;
    for (final row in rows) {
      final member = Member(Map<String, dynamic>.from(jsonDecode(row.payload) as Map));
      if (member.qrToken == token) return member;
    }
    return null;
  }

  Future<List<GymSubscription>> _subscriptions(String memberId) async {
    final rows = await db.watchRecords(SyncEntity.subscriptions, limit: 50000).first;
    return rows
        .map((row) => GymSubscription(Map<String, dynamic>.from(jsonDecode(row.payload) as Map)))
        .where((s) => s.memberId == memberId && s.deletedAt == null)
        .toList();
  }

  Future<List<AttendanceEntry>> _todayGrantedEntries(String memberId, DateTime scannedAt) async {
    final date = gymDate(scannedAt, session.timezone);
    final rows = await db.watchRecords(SyncEntity.attendance, limit: 1000).first;
    return rows
        .map((row) => AttendanceEntry(Map<String, dynamic>.from(jsonDecode(row.payload) as Map)))
        .where((entry) =>
            entry.memberId == memberId &&
            entry.result == 'granted' &&
            gymDate(entry.scannedAt, session.timezone) == date)
        .toList();
  }

  Future<bool> _isDuplicate(String memberId, DateTime scannedAt) async {
    final seconds = ((session.settings['entry_duplicate_seconds'] as num?)?.toInt() ?? 5).clamp(1, 60);
    if (seconds == 0) return false;
    final rows = await db.watchRecords(SyncEntity.attendance, limit: 1000).first;
    return rows
        .map((row) => AttendanceEntry(Map<String, dynamic>.from(jsonDecode(row.payload) as Map)))
        .any((entry) =>
            entry.memberId == memberId &&
            entry.result == 'granted' &&
            entry.scannedAt.difference(scannedAt).abs() <= Duration(seconds: seconds));
  }
}
