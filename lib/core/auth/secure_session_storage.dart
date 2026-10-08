import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage(this.namespace);
  final String namespace;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  String get _key => 'gymdesk:$namespace:auth';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => storage.containsKey(key: _key);

  @override
  Future<String?> accessToken() => storage.read(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => storage.delete(key: _key);
}
