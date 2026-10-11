import 'dart:typed_data';

class UsbIdentity {
  const UsbIdentity({
    required this.vid,
    required this.pid,
    this.vendorName,
    this.productName,
    this.serialNumber,
    this.deviceClass,
  });

  final String vid; // e.g. "0x1612"
  final String pid; // e.g. "0x0011"
  final String? vendorName;
  final String? productName;
  final String? serialNumber;
  final String? deviceClass;

  @override
  String toString() => '$vendorName $productName ($vid:$pid)';
}

class ReaderInfo {
  const ReaderInfo({
    required this.vendor,
    required this.model,
    required this.vid,
    required this.pid,
    this.serial,
    this.firmware,
  });

  final String vendor;
  final String model;
  final String vid;
  final String pid;
  final String? serial;
  final String? firmware;
}

class ReaderCapabilities {
  const ReaderCapabilities({
    required this.hasLivePreview,
    required this.hasLivenessDetection,
    required this.supportedFormats,
    required this.hasNative1N,
    this.max1NCandidates = 10000,
  });

  final bool hasLivePreview;
  final bool hasLivenessDetection;
  final List<String> supportedFormats;
  final bool hasNative1N;
  final int max1NCandidates;
}

enum ReaderEventType {
  connected,
  disconnected,
  fingerDown,
  fingerUp,
  imageCaptured,
  error,
}

class ReaderEvent {
  const ReaderEvent({
    required this.type,
    this.message,
    this.quality,
    this.previewImage,
  });

  final ReaderEventType type;
  final String? message;
  final int? quality;
  final Uint8List? previewImage;
}

class Capture {
  const Capture({
    required this.template,
    required this.quality,
    this.imageBytes,
    this.isoTemplate,
  });

  final String template; // Gabarit en base64
  final int quality;     // 0 à 100
  final Uint8List? imageBytes;
  final String? isoTemplate; // ISO 19794-2
}

class Template {
  const Template({
    required this.data,
    required this.vendor,
    required this.templateFormat,
    this.sdkVersion,
    this.isoData,
    this.fingerIndex = 1,
    this.memberId,
  });

  final String data;
  final String vendor;
  final String templateFormat;
  final String? sdkVersion;
  final String? isoData;
  final int fingerIndex;
  final String? memberId;
}

enum MatchLevel {
  low(0.70),
  normal(0.85),
  high(0.92),
  strict(0.96);

  const MatchLevel(this.threshold);
  final double threshold;
}

class IdentifyResult {
  const IdentifyResult({
    required this.memberId,
    required this.score,
    required this.fingerIndex,
    this.matchedTemplate,
  });

  final String memberId;
  final double score;
  final int fingerIndex;
  final Template? matchedTemplate;
}

class NetworkAccessTerminal {
  const NetworkAccessTerminal({
    required this.id,
    required this.gymId,
    required this.label,
    required this.vendor,
    required this.model,
    this.serial,
    required this.ip,
    this.port = 51211,
    this.firmware,
    this.connector = 'device_sdk',
    this.doorLabel = 'Porte Principale',
    this.status = 'active',
    this.lastSeen,
  });

  final String id;
  final String gymId;
  final String label;
  final String vendor; // ex: 'Suprema'
  final String model;  // ex: 'BioEntry W2'
  final String? serial;
  final String ip;
  final int port;
  final String? firmware;
  final String connector; // 'device_sdk', 'bioStar_api', 'gsdk', 'direct_http'
  final String doorLabel;
  final String status;
  final DateTime? lastSeen;

  Map<String, dynamic> toJson() => {
    'id': id,
    'gym_id': gymId,
    'label': label,
    'vendor': vendor,
    'model': model,
    'serial': serial,
    'ip': ip,
    'port': port,
    'firmware': firmware,
    'connector': connector,
    'door_label': doorLabel,
    'status': status,
    'last_seen': lastSeen?.toIso8601String(),
  };

  factory NetworkAccessTerminal.fromJson(Map<String, dynamic> json) => NetworkAccessTerminal(
    id: json['id']?.toString() ?? '',
    gymId: json['gym_id']?.toString() ?? '',
    label: json['label']?.toString() ?? 'Terminal Porte',
    vendor: json['vendor']?.toString() ?? 'Suprema',
    model: json['model']?.toString() ?? 'BioEntry W2',
    serial: json['serial']?.toString(),
    ip: json['ip']?.toString() ?? '192.168.1.100',
    port: (json['port'] as num?)?.toInt() ?? 51211,
    firmware: json['firmware']?.toString(),
    connector: json['connector']?.toString() ?? 'device_sdk',
    doorLabel: json['door_label']?.toString() ?? 'Porte Principale',
    status: json['status']?.toString() ?? 'active',
    lastSeen: json['last_seen'] != null ? DateTime.tryParse(json['last_seen'].toString()) : null,
  );
}

class TerminalUser {
  const TerminalUser({
    required this.userId,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.templates,
    this.isActive = true,
  });

  final String userId;       // Numéro de membre ou ID
  final String name;         // Prénom + Nom
  final DateTime startDate;  // Début abonnement
  final DateTime endDate;    // Fin abonnement
  final List<String> templates; // Gabarits Suprema / ISO
  final bool isActive;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'name': name,
    'start_date': startDate.toIso8601String(),
    'end_date': endDate.toIso8601String(),
    'templates': templates,
    'is_active': isActive,
  };
}

