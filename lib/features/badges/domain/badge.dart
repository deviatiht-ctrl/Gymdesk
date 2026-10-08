import '../../../core/sync/sync_models.dart';

enum BadgeStatus {
  unassigned,
  bound,
  blocked,
  retired,
}

class BadgeItem {
  const BadgeItem(this.row);
  final Json row;

  String get id => row['id'] as String;
  String get gymId => row['gym_id'] as String;
  String? get batchId => row['batch_id'] as String?;
  int get badgeNumber => (row['badge_number'] as num?)?.toInt() ?? 0;
  String get qrToken => row['qr_token'] as String? ?? '';
  String get status => row['status'] as String? ?? 'unassigned';
  String? get memberId => row['member_id'] as String?;
  DateTime? get boundAt => row['bound_at'] == null ? null : DateTime.tryParse(row['bound_at'] as String);
  String? get boundBy => row['bound_by'] as String?;
  DateTime? get printedAt => row['printed_at'] == null ? null : DateTime.tryParse(row['printed_at'] as String);
  DateTime get createdAt => DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
  DateTime get updatedAt => DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.now();

  bool get isAvailable => status == 'unassigned';
  bool get isBound => status == 'bound';
  bool get isBlocked => status == 'blocked';

  String get formattedNumber {
    if (badgeNumber >= 100) {
      return 'MEMBRE ${badgeNumber.toString().padLeft(3, '0')}';
    }
    return 'MEMBRE ${badgeNumber.toString().padLeft(2, '0')}';
  }

  String qrPayload(String gymCode) => 'GD2|$gymCode|$badgeNumber|$qrToken';
}

class BadgeBatch {
  const BadgeBatch(this.row);
  final Json row;

  String get id => row['id'] as String;
  String get gymId => row['gym_id'] as String;
  String get label => row['label'] as String? ?? '';
  int get rangeFrom => (row['range_from'] as num?)?.toInt() ?? 1;
  int get rangeTo => (row['range_to'] as num?)?.toInt() ?? 1;
  int get quantity => (row['quantity'] as num?)?.toInt() ?? 0;
  String get source => row['source'] as String? ?? 'plan_allotment';
  DateTime get createdAt => DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
}

class BadgeQuotaInfo {
  const BadgeQuotaInfo({
    required this.totalGenerated,
    required this.totalBound,
    required this.totalAvailable,
    required this.totalBlocked,
    required this.quotaLimit,
  });

  final int totalGenerated;
  final int totalBound;
  final int totalAvailable;
  final int totalBlocked;
  final int quotaLimit;

  int get quotaRemaining => (quotaLimit - totalGenerated).clamp(0, 9999);
  bool get canGenerate => quotaRemaining > 0;
  bool get nearLimit => totalGenerated > 0 && (totalBound / totalGenerated) >= 0.8;
}
