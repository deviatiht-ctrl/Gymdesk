import '../../../core/sync/sync_models.dart';

class GymSubscription {
  const GymSubscription(this.row);
  final Json row;

  String get id => row['id'] as String;
  String get gymId => row['gym_id'] as String;
  String get memberId => row['member_id'] as String;
  String? get planId => row['plan_id'] as String?;
  DateTime get startDate => DateTime.parse(row['start_date'] as String);
  DateTime get endDate => DateTime.parse(row['end_date'] as String);
  double get price => (row['price'] as num?)?.toDouble() ?? 0;
  double get openingCredit => (row['opening_credit'] as num?)?.toDouble() ?? 0;
  bool get imported => row['enrollment_kind'] == 'import';
  double remainingAfter(double paid) =>
      (price - openingCredit - paid).clamp(0, price).toDouble();
  String get status => row['status'] as String? ?? 'pending';
  String? get renewedFrom => row['renewed_from'] as String?;
  String? get createdBy => row['created_by'] as String?;
  String get updatedAt => row['updated_at'] as String;
  String? get deletedAt => row['deleted_at'] as String?;
}

class SubscriptionCommand {
  const SubscriptionCommand({
    this.memberId,
    required this.planId,
    required this.startDate,
    required this.endDate,
    required this.price,
    required this.status,
    this.renewedFrom,
  });
  final String? memberId;
  final String? planId;
  final DateTime startDate;
  final DateTime endDate;
  final double price;
  final String status;
  final String? renewedFrom;
}

class SubscriptionFailure implements Exception {
  const SubscriptionFailure(this.code);
  final String code;
}
