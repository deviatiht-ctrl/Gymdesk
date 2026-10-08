import '../../../core/sync/sync_models.dart';

class GymSettings {
  const GymSettings(this.row);
  final Json row;

  String get id => row['id'] as String;
  String get name => row['name'] as String? ?? '';
  String get code => row['code'] as String? ?? '';
  String get accentColor => row['accent_color'] as String? ?? '#1F6F4A';
  String get timezone => row['timezone'] as String? ?? 'America/Port-au-Prince';
  String get currency => row['currency'] as String? ?? 'HTG';
  String get address => row['address'] as String? ?? '';
  String get phone => row['phone'] as String? ?? '';
  String get email => row['email'] as String? ?? '';
  String? get logoUrl => row['logo_url'] as String?;
  String get updatedAt =>
      row['updated_at'] as String? ?? DateTime.now().toUtc().toIso8601String();
  Json get settings => Map<String, dynamic>.from(row['settings'] as Map? ?? {});

  GymSettings copy({
    String? name,
    String? accentColor,
    String? timezone,
    String? currency,
    String? address,
    String? phone,
    String? email,
    Object? logoUrl = _same,
    Json? settings,
  }) => GymSettings({
    ...row,
    'name': ?name,
    'accent_color': ?accentColor,
    'timezone': ?timezone,
    'currency': ?currency,
    if (address != null) 'address': address.isEmpty ? null : address,
    if (phone != null) 'phone': phone.isEmpty ? null : phone,
    if (email != null) 'email': email.isEmpty ? null : email,
    if (!identical(logoUrl, _same)) 'logo_url': logoUrl,
    'settings': ?settings,
  });

  static const _same = Object();
}

class SettingsFailure implements Exception {
  const SettingsFailure(this.code);
  final String code;
}
