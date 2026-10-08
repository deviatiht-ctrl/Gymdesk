import '../../../core/sync/sync_models.dart';
import '../../members/domain/member.dart';

class AttendanceEntry {
  const AttendanceEntry(this.row);
  final Json row;

  String get id => row['id'] as String;
  String get gymId => row['gym_id'] as String;
  String? get memberId => row['member_id'] as String?;
  String? get subscriptionId => row['subscription_id'] as String?;
  DateTime get scannedAt => DateTime.parse(row['scanned_at'] as String);
  DateTime? get serverReceivedAt =>
      DateTime.tryParse(row['server_received_at'] as String? ?? '');
  String get result => row['result'] as String? ?? 'denied_unknown';
  String? get denialReason => row['denial_reason'] as String?;
  int? get entryNumberToday => (row['entry_number_today'] as num?)?.toInt();
  String? get deviceId => row['device_id'] as String?;
  String? get scannedBy => row['scanned_by'] as String?;
  bool get wasOffline => row['was_offline'] == true;
  bool get suspectClock => row['suspect_clock'] == true;
}

class QrCredential {
  const QrCredential({
    required this.gymCode,
    required this.memberNumber,
    required this.token,
  });
  final String gymCode;
  final String memberNumber;
  final String token;
}

class ScanOutcome {
  const ScanOutcome({
    required this.result,
    this.entry,
    this.member,
    required this.message,
    this.direction = 'in',
  });
  final String result;
  final AttendanceEntry? entry;
  final Member? member;
  final String message;
  final String direction;

  bool get isCheckIn => direction == 'in';
  bool get isCheckOut => direction == 'out';
}

class AttendanceFailure implements Exception {
  const AttendanceFailure(this.code);
  final String code;
}
