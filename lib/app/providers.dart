import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'runtime.dart';

part 'providers.g.dart';

@Riverpod(keepAlive: true)
AppRuntime appRuntime(Ref ref) {
  final runtime = AppRuntime(
    Supabase.instance.client,
    namespace: Uri.parse(AppEnv.supabaseUrl).host,
  );
  ref.onDispose(() => unawaited(runtime.shutdown()));
  return runtime;
}

@Riverpod(keepAlive: true)
class AppLanguage extends _$AppLanguage {
  static const _storage = FlutterSecureStorage();
  @override
  Locale build() {
    unawaited(_load());
    return const Locale('ht');
  }

  Future<void> _load() async {
    try {
      final code = await _storage.read(key: 'gymdesk:language');
      if (ref.mounted && {'ht', 'fr', 'en'}.contains(code)) {
        state = Locale(code!);
      }
    } catch (_) {
      return;
    }
  }

  Future<void> change(String code) async {
    if (!{'ht', 'fr', 'en'}.contains(code)) return;
    state = Locale(code);
    await _storage.write(key: 'gymdesk:language', value: code);
  }
}
