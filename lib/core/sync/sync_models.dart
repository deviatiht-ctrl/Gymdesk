typedef Json = Map<String, dynamic>;

enum SyncEntity {
  staff('staff', writable: false),
  gyms('gyms', writable: false),
  members('members'),
  plans('plans'),
  subscriptions('subscriptions'),
  payments('payments'),
  attendance('attendance'),
  badgeTemplates('badge_templates'),
  badgeBatches('badge_batches', writable: false),
  badges('badges'),
  badgeHistory('badge_history', writable: false),
  memberPins('member_pins'),
  paymentDeclarations('payment_declarations'),
  gymContracts('gym_contracts', writable: false),
  platformInvoices('platform_invoices', writable: false),
  auditLog('audit_log', writable: false);

  const SyncEntity(this.table, {this.writable = true});
  final String table;
  final bool writable;

  String get cursorField => switch (this) {
    attendance => 'server_received_at',
    auditLog || badgeHistory || badgeBatches || paymentDeclarations => 'created_at',
    _ => 'updated_at',
  };
}

enum SyncPhase { offline, idle, running, error, blocked }

class SyncState {
  const SyncState({
    this.phase = SyncPhase.offline,
    this.pending = 0,
    this.failed = 0,
    this.conflicts = 0,
    this.initialized = false,
    this.progress = 0,
    this.clockSuspect = false,
    this.errorCode,
    this.lastSync,
  });

  final SyncPhase phase;
  final int pending;
  final int failed;
  final int conflicts;
  final bool initialized;
  final double progress;
  final bool clockSuspect;
  final String? errorCode;
  final DateTime? lastSync;
}

class StaffSession {
  const StaffSession({
    required this.staff,
    required this.gym,
    required this.verifiedAt,
  });

  final Json staff;
  final Json? gym;
  final DateTime verifiedAt;

  String get userId => staff['user_id'] as String;
  String get staffId => staff['id'] as String;
  String? get gymId => gym?['id'] as String?;
  String get role => staff['role'] as String;
  bool get isPlatformAdmin => role == 'super_admin';
  bool get isOwner => role == 'owner';
  bool get isSupervisor => role == 'supervisor';
  bool get isReception => role == 'reception';
  bool get canManageGym => role == 'owner' || role == 'supervisor';
  bool get active =>
      staff['active'] == true &&
      staff['deleted_at'] == null &&
      (isPlatformAdmin ||
          {'active', 'trial', 'grace'}.contains(gym?['status']));
  String get name => gym?['name'] as String? ?? 'GymDesk';
  String get timezone =>
      gym?['timezone'] as String? ?? 'America/Port-au-Prince';
  Json get settings =>
      Map<String, dynamic>.from(gym?['settings'] as Map? ?? {});
  int get offlineHours =>
      ((settings['offline_lease_hours'] as num?)?.toInt() ?? 24).clamp(1, 72);
  bool offlineAllowed(DateTime now) =>
      active &&
      now.isAfter(verifiedAt.subtract(const Duration(minutes: 10))) &&
      now.difference(verifiedAt) < Duration(hours: offlineHours);

  Json toJson() => {
    'staff': staff,
    'gym': gym,
    'verified_at': verifiedAt.toUtc().toIso8601String(),
  };
  factory StaffSession.fromJson(Json json) => StaffSession(
    staff: Map<String, dynamic>.from(json['staff'] as Map),
    gym: json['gym'] == null
        ? null
        : Map<String, dynamic>.from(json['gym'] as Map),
    verifiedAt: DateTime.parse(json['verified_at'] as String),
  );
}

class SyncRejected implements Exception {
  const SyncRejected(this.code, {this.permanent = true});
  final String code;
  final bool permanent;
}

Duration retryDelay(int attempts) =>
    Duration(seconds: 1 << attempts.clamp(1, 9));
