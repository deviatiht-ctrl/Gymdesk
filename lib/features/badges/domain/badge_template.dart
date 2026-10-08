import '../../../core/sync/sync_models.dart';

class BadgeTemplate {
  const BadgeTemplate(this.row);
  final Json row;

  String get id => row['id'] as String;
  String get gymId => row['gym_id'] as String;
  String get name => row['name'] as String? ?? '';
  Json get layout => Map<String, dynamic>.from(row['layout'] as Map? ?? {});
  bool get isDefault => row['is_default'] == true;
  String? get deletedAt => row['deleted_at'] as String?;
  String get orientation =>
      layout['orientation'] == 'portrait' ? 'portrait' : 'landscape';
  bool get showPhoto => layout['show_photo'] != false;
  bool get showQr => layout['show_qr'] != false;
  bool get showGymName => layout['show_gym_name'] != false;
  bool get showStatus => layout['show_status'] == true;
  String get accentColor => layout['accent_color'] as String? ?? '';

  Json updated({
    String? name,
    Json? layout,
    bool? isDefault,
    String? deletedAt,
  }) => {
    ...row,
    'name': ?name,
    'layout': ?layout,
    'is_default': ?isDefault,
    'deleted_at': ?deletedAt,
  };

  static BadgeTemplate fallback(String gymId) => BadgeTemplate({
    'id': 'fallback',
    'gym_id': gymId,
    'name': 'GymDesk',
    'layout': {
      'orientation': 'landscape',
      'show_photo': true,
      'show_qr': true,
      'show_gym_name': true,
      'show_status': true,
    },
    'is_default': true,
  });
}

class BadgeTemplateDraft {
  const BadgeTemplateDraft({
    required this.name,
    this.orientation = 'landscape',
    this.showPhoto = true,
    this.showQr = true,
    this.showGymName = true,
    this.showStatus = true,
    this.accentColor = '',
    this.isDefault = false,
  });
  final String name;
  final String orientation;
  final bool showPhoto;
  final bool showQr;
  final bool showGymName;
  final bool showStatus;
  final String accentColor;
  final bool isDefault;

  Json get layout => {
    'orientation': orientation,
    'show_photo': showPhoto,
    'show_qr': showQr,
    'show_gym_name': showGymName,
    'show_status': showStatus,
    if (accentColor.isNotEmpty) 'accent_color': accentColor,
  };
}

class BadgeFailure implements Exception {
  const BadgeFailure(this.code);
  final String code;
}
