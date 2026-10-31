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
  bool get isOneTime => billingPeriod == 'one_time';
  bool get biometricSupported => config['biometric_supported'] == true;
  bool get includesDoorAccess => config['includes_door_access'] == true;
  String get doorHardwareKit =>
      config['door_hardware_kit'] as String? ??
      'Terminal FSTW F30 TCP/IP + Lecteur USB DigitalPersona 4500 + Ventouse 280kg + Bras LZ + Bouton sortie + Alimentation sécurisée';
  bool get installationIncluded => config['installation_included'] == true;
  bool get installmentsAllowed => config['installments_allowed'] == true;
  double get installment1 =>
      (config['installment_1_amount'] as num?)?.toDouble() ??
      (price > 0 ? (price * 0.58).roundToDouble() : 0.0);
  double get installment2 =>
      (config['installment_2_amount'] as num?)?.toDouble() ??
      (price > 0 ? ((price - installment1) / 2).roundToDouble() : 0.0);
  double get installment3 =>
      (config['installment_3_amount'] as num?)?.toDouble() ??
      (price > 0 ? (price - installment1 - installment2).roundToDouble() : 0.0);

  static const List<PlatformOffer> defaultAnnualPlans = [
    PlatformOffer(
      id: 'plan_basic',
      name: 'PLAN 1 : DÉMARRAGE (Porte biométrique)',
      description: 'Paiement unique pour les petites salles jusqu’à 150 membres, contrôle d’accès biométrique de porte inclus.',
      billingPeriod: 'one_time',
      price: 950,
      currency: 'USD',
      config: {
        'billing_type': 'one_time',
        'max_members': 150,
        'overage_member_fee': 2.0,
        'badge_quota': 0,
        'includes_tablet': false,
        'tablet_count': 0,
        'tablet_optional_price': 180.0,
        'biometric_supported': true,
        'includes_door_access': true,
        'door_hardware_kit':
            'Terminal FSTW F30 TCP/IP + Lecteur USB DigitalPersona 4500 + Ventouse 280kg + Bras LZ + Bouton sortie + Alimentation sécurisée',
        'installation_included': true,
        'installments_allowed': true,
        'installment_1_amount': 550.0,
        'installment_2_amount': 200.0,
        'installment_3_amount': 200.0,
        'features': [
          'Paiement unique (achat définitif — aucun renouvellement)',
          'Jusqu’à 150 membres actifs',
          'Dépassement : +2,00 USD / membre supplémentaire',
          '✅ Système de contrôle d’accès biométrique inclus',
          '✅ Lecteur d’empreintes USB inclus',
          '🛠️ Installation complète sur place par une équipe technique',
          '📱 Tablette Android d’accueil : sur commande (optionnelle, +180 USD)',
          '🎟️ Badges physiques QR en option (accès possible par empreinte seule)',
          '💳 Paiement en 3 fois possible : 550 USD d’acompte + 200 USD + 200 USD',
          'Code PIN temporaire pour les pass journée',
          'Support technique et mises à jour inclus',
        ],
      },
    ),
    PlatformOffer(
      id: 'plan_medium',
      name: 'PLAN 2 : CROISSANCE (Porte biométrique)',
      description: 'Paiement unique pour les salles jusqu’à 1 000 membres, avec rapports financiers et reçus.',
      billingPeriod: 'one_time',
      price: 1450,
      currency: 'USD',
      config: {
        'billing_type': 'one_time',
        'max_members': 1000,
        'overage_member_fee': 2.5,
        'badge_quota': 0,
        'includes_tablet': false,
        'tablet_count': 0,
        'tablet_optional_price': 150.0,
        'biometric_supported': true,
        'includes_door_access': true,
        'door_hardware_kit':
            'Terminal FSTW F30 TCP/IP + Lecteur USB DigitalPersona 4500 + Ventouse 280kg + Bras LZ + Bouton sortie + Alimentation sécurisée',
        'installation_included': false,
        'installments_allowed': true,
        'installment_1_amount': 850.0,
        'installment_2_amount': 300.0,
        'installment_3_amount': 300.0,
        'features': [
          'Paiement unique (achat définitif — aucun renouvellement)',
          'Jusqu’à 1 000 membres actifs',
          'Dépassement : +2,50 USD / membre supplémentaire',
          '✅ Système de contrôle d’accès biométrique inclus',
          '✅ Lecteur d’empreintes USB inclus',
          '🛠️ Installation de la porte par une équipe technique : sur commande (à la charge du client)',
          '📱 Tablette Android d’accueil : sur commande (optionnelle, +150 USD)',
          '🎟️ Badges physiques QR en option (accès possible par empreinte seule)',
          '💳 Paiement en 3 fois possible : 850 USD d’acompte + 300 USD + 300 USD',
          'Code PIN temporaire pour les pass journée',
          'Gestion des paiements, rapports financiers avancés et reçus',
          'Support prioritaire',
        ],
      },
    ),
    PlatformOffer(
      id: 'plan_pro',
      name: 'PLAN 3 : PROFESSIONNEL (Expansion)',
      description: 'Solution avancée pour les salles jusqu’à 1 000 membres, tablette et badges offerts.',
      billingPeriod: 'one_time',
      price: 2200,
      currency: 'USD',
      config: {
        'billing_type': 'one_time',
        'max_members': 1000,
        'overage_member_fee': 2.0,
        'badge_quota': 200,
        'includes_tablet': true,
        'tablet_count': 1,
        'tablet_optional_price': 0.0,
        'biometric_supported': true,
        'includes_door_access': true,
        'door_hardware_kit':
            'Terminal FSTW F30 TCP/IP + Lecteur USB DigitalPersona 4500 + Ventouse 280kg + Bras LZ + Bouton sortie + Alimentation sécurisée',
        'installation_included': true,
        'installments_allowed': true,
        'installment_1_amount': 1300.0,
        'installment_2_amount': 450.0,
        'installment_3_amount': 450.0,
        'is_hot': true,
        'features': [
          'Paiement unique (achat définitif — aucun renouvellement)',
          'Jusqu’à 1 000 membres actifs',
          'Dépassement : +2,00 USD / membre supplémentaire',
          '✅ Système de contrôle d’accès biométrique inclus',
          '✅ Lecteur d’empreintes USB inclus',
          '📱 1 tablette Android OFFERTE pour l’accueil',
          '🎟️ 200 badges physiques QR offerts (optionnels)',
          '🛠️ Installation complète sur place par une équipe technique',
          '💳 Paiement en 3 fois possible : 1 300 USD d’acompte + 450 USD + 450 USD',
          'Support prioritaire 24/7',
        ],
      },
    ),
    PlatformOffer(
      id: 'plan_enterprise',
      name: 'PLAN 4 : ENTREPRISE (Performance illimitée)',
      description: 'Accompagnement complet, membres illimités, accès API et responsable dédié.',
      billingPeriod: 'one_time',
      price: 3200,
      currency: 'USD',
      config: {
        'billing_type': 'one_time',
        'max_members': 0,
        'overage_member_fee': 0.0,
        'badge_quota': 500,
        'includes_tablet': true,
        'tablet_count': 1,
        'tablet_optional_price': 0.0,
        'biometric_supported': true,
        'includes_door_access': true,
        'door_hardware_kit':
            'Terminal FSTW F30 TCP/IP + Lecteur USB DigitalPersona 4500 + Ventouse 280kg + Bras LZ + Bouton sortie + Alimentation sécurisée',
        'installation_included': true,
        'installments_allowed': true,
        'installment_1_amount': 1800.0,
        'installment_2_amount': 700.0,
        'installment_3_amount': 700.0,
        'features': [
          'Paiement unique (achat définitif — aucun renouvellement)',
          'MEMBRES ILLIMITÉS (aucune limite) 🚀',
          'Dépassement : 0 USD (tout inclus)',
          '✅ Système de contrôle d’accès biométrique inclus',
          '✅ Lecteur d’empreintes USB inclus',
          '📱 1 tablette Android OFFERTE pour l’accueil',
          '🎟️ 500 badges physiques QR offerts (optionnels)',
          '🛠️ Installation complète sur place par une équipe technique',
          '💳 Paiement en 3 fois possible : 1 800 USD d’acompte + 700 USD + 700 USD',
          'Accès API, rapports avancés et sauvegarde cloud',
          'Équipe technique et responsable de compte dédiés',
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

/// Fiche complète d’une salle pour le super admin :
/// ligne `gyms` brute, statistiques, contrat/offre courant et propriétaire.
class GymDetail {
  const GymDetail({
    required this.gymJson,
    required this.stats,
    this.contract,
    this.owner,
  });
  final Json gymJson;
  final Json stats;
  final Json? contract;
  final Json? owner;

  Gym get gym => Gym.fromJson(gymJson);
  String? get logoUrl => gymJson['logo_url'] as String?;
  String? get createdAt => gymJson['created_at'] as String?;
  String? get trialEndsAt => gymJson['trial_ends_at'] as String?;
  String? get trialEndsSoonAt => gymJson['trial_ends_soon_at'] as String?;
  String? get source => gymJson['source'] as String?;
  Json get settings =>
      Map<String, dynamic>.from(gymJson['settings'] as Map? ?? {});

  int stat(String key) => (stats[key] as num?)?.toInt() ?? 0;
  double get paymentsTotal =>
      (stats['payments_total'] as num?)?.toDouble() ?? 0;

  factory GymDetail.fromJson(Json json) => GymDetail(
    gymJson: Map<String, dynamic>.from(json['gym'] as Map? ?? {}),
    stats: Map<String, dynamic>.from(json['stats'] as Map? ?? {}),
    contract: json['contract'] is Map
        ? Map<String, dynamic>.from(json['contract'] as Map)
        : null,
    owner: json['owner'] is Map
        ? Map<String, dynamic>.from(json['owner'] as Map)
        : null,
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
