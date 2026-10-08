import '../../../core/sync/sync_models.dart';

class Gym {
  const Gym({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.updatedAt,
    required this.timezone,
    required this.currency,
    required this.accentColor,
    this.address,
    this.phone,
    this.email,
    this.deletedAt,
  });

  final String id;
  final String code;
  final String name;
  final String status;
  final String updatedAt;
  final String timezone;
  final String currency;
  final String accentColor;
  final String? address;
  final String? phone;
  final String? email;
  final String? deletedAt;
  bool get archived => deletedAt != null;

  factory Gym.fromJson(Json json) => Gym(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    status: json['status'] as String,
    updatedAt: json['updated_at'] as String,
    timezone: json['timezone'] as String,
    currency: json['currency'] as String,
    accentColor: json['accent_color'] as String,
    address: json['address'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    deletedAt: json['deleted_at'] as String?,
  );
}

class PlatformStatistics {
  const PlatformStatistics({
    required this.gyms,
    required this.activeGyms,
    required this.members,
    required this.entriesToday,
  });
  final int gyms;
  final int activeGyms;
  final int members;
  final int entriesToday;
  factory PlatformStatistics.fromJson(Json json) => PlatformStatistics(
    gyms: (json['gyms'] as num).toInt(),
    activeGyms: (json['active_gyms'] as num).toInt(),
    members: (json['members'] as num).toInt(),
    entriesToday: (json['entries_today'] as num).toInt(),
  );
}

class GymPage {
  const GymPage(
    this.gyms,
    this.statistics,
    this.hasNext, {
    this.overviews = const {},
  });
  final List<Gym> gyms;
  final PlatformStatistics statistics;
  final bool hasNext;
  final Map<String, GymOverview> overviews;
}

class PlatformOffer {
  const PlatformOffer({
    required this.id,
    required this.name,
    required this.billingPeriod,
    required this.price,
    required this.currency,
    required this.config,
    this.description,
  });
  final String id;
  final String name;
  final String? description;
  final String billingPeriod;
  final double price;
  final String currency;
  final Json config;

  int get badgeQuota => (config['badge_quota'] as num?)?.toInt() ?? 0;
  double get minMonthly => (config['min_monthly'] as num?)?.toDouble() ?? 0;
  double get setupFee => (config['setup_fee'] as num?)?.toDouble() ?? 0;
  List<Json> get tiers => [
    for (final t in (config['tiers'] as List? ?? const []))
      Map<String, dynamic>.from(t as Map),
  ];
  bool get isAnnual => billingPeriod == 'annual';

  factory PlatformOffer.fromJson(Json json) => PlatformOffer(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    billingPeriod: json['billing_period'] as String? ?? 'monthly',
    price: (json['price'] as num? ?? 0).toDouble(),
    currency: json['currency'] as String? ?? 'USD',
    config: Map<String, dynamic>.from(json['config'] as Map? ?? {}),
  );
}

class GymOverview {
  const GymOverview({
    required this.members,
    this.offerName,
    this.offerPrice,
    this.offerCurrency,
    this.billingPeriod,
    this.contractStatus,
    this.expiresAt,
  });
  final int members;
  final String? offerName;
  final double? offerPrice;
  final String? offerCurrency;
  final String? billingPeriod;
  final String? contractStatus;
  final String? expiresAt;
  bool get hasContract => contractStatus != null;

  factory GymOverview.fromJson(Json json) => GymOverview(
    members: (json['members'] as num? ?? 0).toInt(),
    offerName: json['offer_name'] as String?,
    offerPrice: (json['offer_price'] as num?)?.toDouble(),
    offerCurrency: json['offer_currency'] as String?,
    billingPeriod: json['billing_period'] as String?,
    contractStatus: json['contract_status'] as String?,
    expiresAt: json['expires_at'] as String?,
  );
}

class CreateGymCommand {
  const CreateGymCommand({
    required this.requestId,
    required this.gymId,
    required this.staffId,
    required this.gym,
    required this.ownerEmail,
    required this.ownerName,
    required this.ownerPassword,
  });
  final String requestId;
  final String gymId;
  final String staffId;
  final Json gym;
  final String ownerEmail;
  final String ownerName;
  final String ownerPassword;

  Json toJson() => {
    'action': 'create',
    'request_id': requestId,
    'gym_id': gymId,
    'staff_id': staffId,
    'gym': gym,
    'owner_email': ownerEmail,
    'owner_name': ownerName,
    'owner_password': ownerPassword,
  };
}

class PlatformFailure implements Exception {
  const PlatformFailure(this.code);
  final String code;
}
