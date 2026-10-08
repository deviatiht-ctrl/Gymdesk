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

  String get backgroundThemeId =>
      layout['background_theme_id'] as String? ?? 'dark_carbon_gold';
  String get qrStyle => layout['qr_style'] as String? ?? 'rounded';
  String get qrColor => layout['qr_color'] as String? ?? '';
  String get qrBgColor => layout['qr_bg_color'] as String? ?? '';
  Map<String, dynamic> get positions =>
      Map<String, dynamic>.from(layout['positions'] as Map? ?? {});

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
    'name': 'GymDesk VIP',
    'layout': {
      'orientation': 'landscape',
      'show_photo': false,
      'show_qr': true,
      'show_gym_name': true,
      'show_status': true,
      'background_theme_id': 'dark_carbon_gold',
      'qr_style': 'rounded',
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
    this.backgroundThemeId = 'dark_carbon_gold',
    this.qrStyle = 'rounded',
    this.qrColor = '',
    this.qrBgColor = '',
    this.positions = const {},
    this.isDefault = false,
  });
  final String name;
  final String orientation;
  final bool showPhoto;
  final bool showQr;
  final bool showGymName;
  final bool showStatus;
  final String accentColor;
  final String backgroundThemeId;
  final String qrStyle;
  final String qrColor;
  final String qrBgColor;
  final Map<String, dynamic> positions;
  final bool isDefault;

  Json get layout => {
    'orientation': orientation,
    'show_photo': showPhoto,
    'show_qr': showQr,
    'show_gym_name': showGymName,
    'show_status': showStatus,
    if (accentColor.isNotEmpty) 'accent_color': accentColor,
    'background_theme_id': backgroundThemeId,
    'qr_style': qrStyle,
    if (qrColor.isNotEmpty) 'qr_color': qrColor,
    if (qrBgColor.isNotEmpty) 'qr_bg_color': qrBgColor,
    if (positions.isNotEmpty) 'positions': positions,
  };
}

class BadgeFailure implements Exception {
  const BadgeFailure(this.code);
  final String code;
}
