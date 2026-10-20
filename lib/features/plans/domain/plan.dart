import '../../../core/sync/sync_models.dart';

class GymPlan {
  const GymPlan(this.row);
  final Json row;

  String get id => row['id'] as String;
  String get gymId => row['gym_id'] as String;
  String get name => row['name'] as String? ?? '';
  int get durationDays => (row['duration_days'] as num?)?.toInt() ?? 0;
  double get price => (row['price'] as num?)?.toDouble() ?? 0;
  double? get enrollmentPrice => (row['enrollment_price'] as num?)?.toDouble();
  double get registrationFee =>
      (row['registration_fee'] as num?)?.toDouble() ??
      (enrollmentPrice != null && enrollmentPrice! > price
          ? enrollmentPrice! - price
          : 0.0);
  double get registrationPrice =>
      enrollmentPrice ?? (price + registrationFee);
  String get currency => row['currency'] as String? ?? 'HTG';
  String? get description => row['description'] as String?;
  bool get active => row['active'] == true;
  int get sortOrder => (row['sort_order'] as num?)?.toInt() ?? 0;
  String get updatedAt => row['updated_at'] as String;
  String? get deletedAt => row['deleted_at'] as String?;

  Json updated({
    String? name,
    int? durationDays,
    double? price,
    double? enrollmentPrice,
    double? registrationFee,
    String? currency,
    String? description,
    bool? active,
    int? sortOrder,
    String? deletedAt,
  }) => {
    ...row,
    'name': ?name,
    'duration_days': ?durationDays,
    'price': ?price,
    'enrollment_price': ?enrollmentPrice,
    'registration_fee': ?registrationFee,
    'currency': ?currency,
    if (description != null)
      'description': description.isEmpty ? null : description,
    'active': ?active,
    'sort_order': ?sortOrder,
    'deleted_at': ?deletedAt,
  };
}

class PlanDraft {
  const PlanDraft({
    required this.name,
    required this.durationDays,
    required this.price,
    this.enrollmentPrice,
    this.registrationFee = 0.0,
    this.currency = 'HTG',
    this.description = '',
    this.active = true,
    this.sortOrder = 0,
  });
  final String name;
  final int durationDays;
  final double price;
  final double? enrollmentPrice;
  final double registrationFee;
  final String currency;
  final String description;
  final bool active;
  final int sortOrder;
}

class PlanFailure implements Exception {
  const PlanFailure(this.code);
  final String code;
}
