import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/sync/sync_models.dart';
import '../domain/staff_profile.dart';

class StaffDraftStore {
  StaffDraftStore(String namespace, String userId)
    : _key = 'gymdesk:$namespace:staff-provision:$userId';
  final String _key;
  static const _storage = FlutterSecureStorage();

  Future<Json?> read() async {
    final value = await _storage.read(key: _key);
    return value == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<void> save(CreateStaffCommand command) {
    final data = command.toJson()..remove('password');
    return _storage.write(key: _key, value: jsonEncode(data));
  }

  Future<void> clear() => _storage.delete(key: _key);
}
