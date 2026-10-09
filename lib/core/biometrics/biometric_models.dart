enum BiometricSensorState {
  disconnected,
  notSupported,
  ready,
  waitingFinger,
  capturing,
  error,
}

enum BiometricAccessMode {
  badgePin,        // Mòd 1: Badge QR + PIN sèlman
  fingerprintOnly, // Mòd 2: Biométrie (Anprent) sèlman (1:N)
  combo,           // Mòd 3: Badge QR + Anprent (1:1 ak sekou PIN)
}

extension BiometricAccessModeExt on BiometricAccessMode {
  String get id => switch (this) {
    BiometricAccessMode.badgePin => 'badge_pin',
    BiometricAccessMode.fingerprintOnly => 'fingerprint_only',
    BiometricAccessMode.combo => 'combo',
  };

  static BiometricAccessMode fromString(String? value) => switch (value) {
    'fingerprint_only' => BiometricAccessMode.fingerprintOnly,
    'combo' => BiometricAccessMode.combo,
    _ => BiometricAccessMode.badgePin,
  };
}

class BiometricEvent {
  const BiometricEvent({
    required this.type,
    this.template,
    this.quality,
    this.message,
    this.matchScore,
    this.raw = const {},
  });

  final String type;
  final String? template;
  final int? quality;
  final String? message;
  final double? matchScore;
  final Map<String, dynamic> raw;

  factory BiometricEvent.fromMap(Map<dynamic, dynamic> map) {
    return BiometricEvent(
      type: map['event'] as String? ?? 'unknown',
      template: map['template'] as String?,
      quality: (map['quality'] as num?)?.toInt(),
      message: map['message'] as String?,
      matchScore: (map['score'] as num?)?.toDouble(),
      raw: Map<String, dynamic>.from(map),
    );
  }
}

class BiometricMatchResult {
  const BiometricMatchResult({
    required this.isMatch,
    required this.score,
    this.memberId,
  });

  final bool isMatch;
  final double score;
  final String? memberId;
}
