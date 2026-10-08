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
  bool get isHot => config['is_hot'] == true;
  bool get includesTablet => config['includes_tablet'] == true;
  int get maxMembers => (config['max_members'] as num?)?.toInt() ?? 0;
  double get overageMemberFee =>
      (config['overage_member_fee'] as num?)?.toDouble() ?? 0.0;
  int get tabletCount =>
      (config['tablet_count'] as num?)?.toInt() ?? (includesTablet ? 1 : 0);
  double get tabletOptionalPrice =>
      (config['tablet_optional_price'] as num?)?.toDouble() ?? 0.0;

  List<String> get features => [
    for (final f in (config['features'] as List? ?? const [])) '$f',
  ];
  List<Json> get tiers => [
    for (final t in (config['tiers'] as List? ?? const []))
      Map<String, dynamic>.from(t as Map),
  ];
  bool get isAnnual => billingPeriod == 'annual';

  static const List<PlatformOffer> defaultAnnualPlans = [
    PlatformOffer(
      id: 'plan_basic',
      name: 'PLAN 1 : BASIC (Starter)',
      description: 'Idéal pour petites salles démarrant la gestion numérique.',
      billingPeriod: 'annual',
      price: 350,
      currency: 'USD',
      config: {
        'max_members': 50,
        'overage_member_fee': 2.0,
        'badge_quota': 0,
        'includes_tablet': false,
        'tablet_count': 0,
        'tablet_optional_price': 180.0,
        'features': [
          'Jiska 50 manb aktif',
          'Depasman : +2.00 USD / manb extra',
          'Badj QR fizik sou kòmand (frais impression)',
          'Opsyon Tablèt Android : +180 USD',
          'Sipò teknik & mizajou enkli',
        ],
      },
    ),
    PlatformOffer(
      id: 'plan_medium',
      name: 'PLAN 2 : MEDIUM (Growth)',
      description: 'Pour salles en croissance cherchant un contrôle rigoureux.',
      billingPeriod: 'annual',
      price: 750,
      currency: 'USD',
      config: {
        'max_members': 150,
        'overage_member_fee': 5.0,
        'badge_quota': 0,
        'includes_tablet': false,
        'tablet_count': 0,
        'tablet_optional_price': 150.0,
        'features': [
          'Jiska 150 manb aktif',
          'Depasman : +5.00 USD / manb extra',
          'Badj QR fizik sou kòmand (frais impression)',
          'Opsyon Tablèt Android : +150 USD',
          'Jesyon peman & rapò finansye',
        ],
      },
    ),
    PlatformOffer(
      id: 'plan_pro',
      name: 'PLAN 3 : PRO (Expansion)',
      description: 'Solution complète clé en main avec tablette et 300 badges offerts.',
      billingPeriod: 'annual',
      price: 1200,
      currency: 'USD',
      config: {
        'max_members': 300,
        'overage_member_fee': 3.0,
        'badge_quota': 300,
        'includes_tablet': true,
        'tablet_count': 1,
        'is_hot': true,
        'features': [
          'Jiska 300 manb aktif',
          'Depasman : +3.00 USD / manb extra',
          '300 Badj fizik QR GRATIS enkli 🪪',
          '1 Tablèt Android GRATIS enkli 📱',
          'Eskanè kamera rapid & PIN sekirize',
          'Sipò priyoritè 24/7',
        ],
      },
    ),
    PlatformOffer(
      id: 'plan_enterprise',
      name: 'PLAN 4 : ENTERPRISE (Unlimited)',
      description: 'Accompagnement illimité et haute performance avec 2 tablettes et 500 badges.',
      billingPeriod: 'annual',
      price: 2200,
      currency: 'USD',
      config: {
        'max_members': 0,
        'overage_member_fee': 0.0,
        'badge_quota': 500,
        'includes_tablet': true,
        'tablet_count': 2,
        'features': [
          'MEMBRES ILLIMITÉS (San limit) 🚀',
          'Depasman manb : 0 USD (Tout enkli)',
          '500 Badj fizik QR GRATIS enkli 🪪',
          '2 Tablettes Android GRATIS enkli 📱📱',
          'Aksè API, rapò avanse & backup nwaj',
          'Responsab kont dedye',
        ],
      },
    ),
  ];

  Json toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'billing_period': billingPeriod,
    'price': price,
    'currency': currency,
    'config': config,
  };

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
