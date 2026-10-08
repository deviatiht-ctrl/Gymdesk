enum PinVerifyStatus {
  ok,
  badPin,
  pinLocked,
  resetRequired,
  notConfigured,
}

class PinVerifyResult {
  const PinVerifyResult({
    required this.status,
    this.failedCount = 0,
    this.lockedUntil,
    this.message = '',
  });

  final PinVerifyStatus status;
  final int failedCount;
  final DateTime? lockedUntil;
  final String message;

  bool get isGranted => status == PinVerifyStatus.ok;
}

class MemberPinData {
  const MemberPinData({
    required this.memberId,
    required this.gymId,
    required this.pinHash,
    required this.salt,
    this.algo = 'pbkdf2_sha256',
    this.iterations = 210000,
    this.failedCount = 0,
    this.totalFailed = 0,
    this.lockedUntil,
    this.resetRequired = false,
    this.setAt,
    this.updatedAt,
  });

  final String memberId;
  final String gymId;
  final String pinHash;
  final String salt;
  final String algo;
  final int iterations;
  final int failedCount;
  final int totalFailed;
  final DateTime? lockedUntil;
  final bool resetRequired;
  final DateTime? setAt;
  final DateTime? updatedAt;

  factory MemberPinData.fromJson(Map<String, dynamic> json) => MemberPinData(
    memberId: json['member_id'] as String,
    gymId: json['gym_id'] as String,
    pinHash: json['pin_hash'] as String? ?? '',
    salt: json['salt'] as String? ?? '',
    algo: json['algo'] as String? ?? 'pbkdf2_sha256',
    iterations: (json['iterations'] as num?)?.toInt() ?? 210000,
    failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
    totalFailed: (json['total_failed'] as num?)?.toInt() ?? 0,
    lockedUntil: json['locked_until'] == null
        ? null
        : DateTime.tryParse(json['locked_until'] as String),
    resetRequired: json['reset_required'] == true || (json['pin_hash'] == 'UNSET'),
    setAt: json['set_at'] == null
        ? null
        : DateTime.tryParse(json['set_at'] as String),
    updatedAt: json['updated_at'] == null
        ? null
        : DateTime.tryParse(json['updated_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': memberId,
    'member_id': memberId,
    'gym_id': gymId,
    'pin_hash': pinHash,
    'salt': salt,
    'algo': algo,
    'iterations': iterations,
    'failed_count': failedCount,
    'total_failed': totalFailed,
    'locked_until': lockedUntil?.toUtc().toIso8601String(),
    'reset_required': resetRequired,
    'set_at': setAt?.toUtc().toIso8601String() ?? DateTime.now().toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String() ?? DateTime.now().toUtc().toIso8601String(),
  };

  MemberPinData copyWith({
    int? failedCount,
    int? totalFailed,
    DateTime? lockedUntil,
    bool? resetRequired,
    DateTime? updatedAt,
  }) => MemberPinData(
    memberId: memberId,
    gymId: gymId,
    pinHash: pinHash,
    salt: salt,
    algo: algo,
    iterations: iterations,
    failedCount: failedCount ?? this.failedCount,
    totalFailed: totalFailed ?? this.totalFailed,
    lockedUntil: lockedUntil,
    resetRequired: resetRequired ?? this.resetRequired,
    setAt: setAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Validation des règles de complexité pour le PIN membre (4 à 6 chiffres)
String? validateMemberPinFormat(String pin, {DateTime? birthDate}) {
  final clean = pin.trim();
  if (clean.length < 4 || clean.length > 6 || !RegExp(r'^\d+$').hasMatch(clean)) {
    return 'pin_format_length';
  }

  // Refus des chiffres tous identiques (ex. 0000, 11111)
  final allSame = clean.split('').every((c) => c == clean[0]);
  if (allSame) {
    return 'pin_trivial_repeated';
  }

  // Refus des séquences ascendantes (ex. 1234, 012345, 2345)
  bool isSeqAsc = true;
  for (int i = 0; i < clean.length - 1; i++) {
    if (clean.codeUnitAt(i + 1) != clean.codeUnitAt(i) + 1) {
      isSeqAsc = false;
      break;
    }
  }
  if (isSeqAsc) return 'pin_trivial_sequential';

  // Refus des séquences descendantes (ex. 4321, 543210, 9876)
  bool isSeqDesc = true;
  for (int i = 0; i < clean.length - 1; i++) {
    if (clean.codeUnitAt(i + 1) != clean.codeUnitAt(i) - 1) {
      isSeqDesc = false;
      break;
    }
  }
  if (isSeqDesc) return 'pin_trivial_sequential';

  // Refus de l'année de naissance si connue
  if (birthDate != null) {
    final yearStr = birthDate.year.toString();
    if (clean == yearStr || clean.contains(yearStr)) {
      return 'pin_trivial_birth_year';
    }
  }

  return null;
}
