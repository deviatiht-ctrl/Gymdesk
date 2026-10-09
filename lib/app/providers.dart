import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'runtime.dart';
import '../core/biometrics/biometric_service.dart';
import '../core/access_control/fstw_access_control_service.dart';
import '../core/access_control/fstw_realtime_listener.dart';

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

final biometricServiceProvider = Provider<BiometricService>((ref) {
  final service = BiometricService();
  ref.onDispose(service.dispose);
  return service;
});

final fstwAccessControlServiceProvider = Provider<FstwAccessControlService>((ref) {
  final runtime = ref.watch(appRuntimeProvider);
  final service = FstwAccessControlService(client: runtime.client);
  final session = runtime.session;
  if (session?.gymId != null) {
    final doorIp = session!.settings['door_terminal_ip'] as String? ?? '192.168.1.200';
    final doorPort = (session.settings['door_terminal_port'] as num?)?.toInt() ?? 5005;
    service.configure(gymId: session.gymId!, ip: doorIp, port: doorPort);
  }
  ref.onDispose(service.dispose);
  return service;
});

final fstwRealtimeListenerProvider = Provider<FstwRealtimeListener?>((ref) {
  final runtime = ref.watch(appRuntimeProvider);
  final session = runtime.session;
  final fstwService = ref.watch(fstwAccessControlServiceProvider);
  if (session?.gymId == null) return null;

  final listener = FstwRealtimeListener(
    client: runtime.client,
    fstwService: fstwService,
  );
  listener.start(session!.gymId!);
  ref.onDispose(listener.stop);
  return listener;
});
