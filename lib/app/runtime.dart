import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth/kiosk_native.dart';
import '../core/auth/kiosk_service.dart';
import '../core/auth/pin_service.dart';
import '../core/db/local_database.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/sync_models.dart';
import '../core/sync/sync_remote.dart';

enum SessionPhase {
  starting,
  signedOut,
  ready,
  locked,
  recovery,
  blocked,
  error,
}

class AppRuntime extends ChangeNotifier {
  AppRuntime(this.client, {required this.namespace});
  final SupabaseClient client;
  final String namespace;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  SessionPhase phase = SessionPhase.starting;
  StaffSession? session;
  LocalDatabase? database;
  SyncEngine? sync;
  PinService? pin;
  KioskService? kiosk;
  bool kioskLocked = false;
  bool onboardingDone = true;
  String? errorCode;
  bool busy = false;
  bool _recoveringPassword = false;
  bool _disposed = false;
  StreamSubscription<AuthState>? _auth;
  Timer? _idleTimer;
  DateTime _lastActivity = DateTime.now();
  DateTime? _passwordLoginAt;
  Future<void> _serial = Future.value();

  String _cacheKey(String userId) => 'gymdesk:$namespace:staff:$userId';
  String get _onboardingKey => 'gymdesk:$namespace:onboarding';

  Future<void> completeOnboarding() async {
    onboardingDone = true;
    try {
      await _secure.write(key: _onboardingKey, value: 'done');
    } catch (_) {}
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize({bool passwordRecovery = false}) async {
    _recoveringPassword = passwordRecovery;
    _auth = client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.passwordRecovery) {
        _recoveringPassword = true;
        unawaited(refresh());
      } else if (event.event == AuthChangeEvent.signedOut) {
        unawaited(_schedule(_reset));
      } else if (event.event == AuthChangeEvent.signedIn && !busy) {
        unawaited(refresh());
      }
    });
    _idleTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_checkIdle()),
    );
    try {
      onboardingDone =
          (await _secure.read(key: _onboardingKey)) == 'done';
    } catch (_) {}
    await refresh();
  }

  void activity() => _lastActivity = DateTime.now();

  Future<void> _checkIdle() async {
    if (_disposed ||
        (phase != SessionPhase.ready && phase != SessionPhase.recovery)) {
      return;
    }
    final elapsed = DateTime.now().difference(_lastActivity);
    final logoutMinutes =
        (session?.settings['auto_logout_minutes'] as num?)?.toInt() ?? 30;
    if (logoutMinutes > 0 &&
        elapsed >= Duration(minutes: logoutMinutes.clamp(1, 1440))) {
      await signOut();
      return;
    }
    if (phase != SessionPhase.ready) return;
    final service = pin;
    if (service == null) return;
    try {
      final status = await service.status();
      final lockMinutes =
          (session?.settings['pin_lock_minutes'] as num?)?.toInt() ?? 5;
      if (status.enabled &&
          elapsed >= Duration(minutes: lockMinutes.clamp(1, 60))) {
        phase = SessionPhase.locked;
        _notify();
      }
    } catch (_) {
      phase = SessionPhase.locked;
      errorCode = 'pin_storage';
      _notify();
    }
  }

  Future<void> _schedule(Future<void> Function() action) {
    _serial = _serial.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } catch (error) {
        errorCode = error is SyncRejected ? error.code : 'local_storage';
        phase = SessionPhase.error;
        _notify();
      }
    });
    return _serial;
  }

  Future<void> refresh() => _schedule(_open);

  Future<void> signIn(String email, String password) async {
    if (busy) return;
    busy = true;
    errorCode = null;
    _notify();
    try {
      await client.auth
          .signInWithPassword(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 30));
      _passwordLoginAt = DateTime.now();
      await refresh();
      if (phase == SessionPhase.ready) {
        try {
          await pin?.resetAfterPasswordLogin();
        } catch (_) {}
      }
    } on AuthException {
      errorCode = 'login_failed';
    } catch (_) {
      errorCode = 'network';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _closeWorkspace() async {
    final engine = sync;
    sync = null;
    engine?.state.removeListener(_onSync);
    await engine?.close();
    final db = database;
    database = null;
    await db?.close();
  }

  Future<void> _open() async {
    phase = SessionPhase.starting;
    errorCode = null;
    _notify();
    await _closeWorkspace();
    final user = client.auth.currentUser;
    if (user == null) {
      await _reset();
      return;
    }
    if (_recoveringPassword) {
      session = null;
      activity();
      phase = SessionPhase.recovery;
      _notify();
      return;
    }
    final remote = SupabaseSyncRemote(client);
    StaffSession? resolved;
    try {
      final context = await remote.context();
      resolved = StaffSession(
        staff: Map<String, dynamic>.from(context['staff'] as Map),
        gym: context['gym'] == null
            ? null
            : Map<String, dynamic>.from(context['gym'] as Map),
        verifiedAt: DateTime.parse(context['server_time'] as String),
      );
      if (resolved.userId != user.id) throw const SyncRejected('access_denied');
      await _cache(resolved);
    } on SyncRejected catch (e) {
      if (e.code != 'network') {
        await _secure.delete(key: _cacheKey(user.id));
        phase = SessionPhase.blocked;
        errorCode = e.code;
        _notify();
        return;
      }
      final cached = await _secure.read(key: _cacheKey(user.id));
      if (cached != null) {
        final candidate = StaffSession.fromJson(jsonDecode(cached) as Json);
        if (candidate.userId == user.id &&
            candidate.offlineAllowed(DateTime.now().toUtc()) &&
            !candidate.isPlatformAdmin) {
          resolved = candidate;
        }
      }
      if (resolved == null) {
        phase = SessionPhase.error;
        errorCode = 'first_sync_required';
        _notify();
        return;
      }
    }
    session = resolved;
    pin = PinService(SecurePinVault(namespace, resolved.userId));
    if (!resolved.isPlatformAdmin) {
      final db = LocalDatabase(
        gymId: resolved.gymId!,
        userId: '${resolved.userId}_${resolved.role}',
        namespace: namespace,
      );
      database = db;
      kiosk = KioskService(
        client,
        namespace: namespace,
        gymId: resolved.gymId!,
      );
      try {
        kioskLocked = await kiosk!.isLocked();
      } catch (_) {
        kioskLocked = false;
      }
      final engine = SyncEngine(
        db: db,
        remote: remote,
        session: resolved,
        onSession: (fresh) async {
          session = fresh;
          await _cache(fresh);
          _notify();
        },
      );
      sync = engine;
      engine.state.addListener(_onSync);
      // Une salle suspendue garde sa base locale ouverte (export de données
      // depuis le paywall) mais le moteur de sync ne démarre pas.
      if (!resolved.active) {
        phase = SessionPhase.blocked;
        errorCode = 'gym_suspended';
        _notify();
        return;
      }
      phase = SessionPhase.ready;
      _notify();
      await engine.start();
      if (engine.state.value.phase == SyncPhase.blocked) {
        phase = SessionPhase.blocked;
        errorCode = engine.state.value.errorCode;
        _notify();
        return;
      }
    } else if (!resolved.active) {
      phase = SessionPhase.blocked;
      errorCode = 'gym_suspended';
      _notify();
      return;
    }
    phase = SessionPhase.ready;
    activity();
    try {
      if (!pinRecentlyAuthenticated && (await pin!.status()).enabled) {
        phase = SessionPhase.locked;
      }
    } catch (_) {
      phase = SessionPhase.locked;
      errorCode = 'pin_storage';
    }
    _notify();
  }

  Future<void> _cache(StaffSession staff) => _secure.write(
    key: _cacheKey(staff.userId),
    value: jsonEncode(staff.toJson()),
  );

  void _onSync() {
    final state = sync?.state.value;
    if (state?.phase == SyncPhase.blocked) {
      phase = SessionPhase.blocked;
      errorCode = state?.errorCode;
    }
    _notify();
  }

  bool get pinRecentlyAuthenticated =>
      _passwordLoginAt != null &&
      DateTime.now().difference(_passwordLoginAt!) <
          const Duration(minutes: 10);

  void applyLocalGym(Json gym) {
    final current = session;
    if (current == null || gym['id'] != current.gymId) return;
    session = StaffSession(
      staff: current.staff,
      gym: gym,
      verifiedAt: current.verifiedAt,
    );
    _notify();
  }

  Future<PinStatus> pinStatus() {
    final service = pin;
    if (service == null) return Future.error(const PinFailure('pin_missing'));
    return service.status();
  }

  Future<void> lockNow() async {
    final service = pin;
    if (phase != SessionPhase.ready || service == null) return;
    if (!(await service.status()).enabled) return;
    phase = SessionPhase.locked;
    _notify();
  }

  Future<void> unlock(String value) async {
    final service = pin;
    if (busy || phase != SessionPhase.locked || service == null) return;
    busy = true;
    errorCode = null;
    _notify();
    try {
      await service.verify(value);
      phase = SessionPhase.ready;
      activity();
    } on PinFailure catch (e) {
      errorCode = e.code;
    } catch (_) {
      errorCode = 'pin_storage';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> configurePin(String value, {String previous = ''}) async {
    final service = pin;
    if (phase != SessionPhase.ready || service == null) {
      throw const PinFailure('pin_missing');
    }
    await service.configure(
      value,
      previous: previous,
      recentPasswordLogin: pinRecentlyAuthenticated,
    );
  }

  Future<void> removePin(String previous) async {
    final service = pin;
    if (phase != SessionPhase.ready || service == null) {
      throw const PinFailure('pin_missing');
    }
    await service.remove(
      previous: previous,
      recentPasswordLogin: pinRecentlyAuthenticated,
    );
  }

  /// Verrouille le scanner en mode kiosque (owner/supervisor uniquement).
  Future<void> lockKiosk({
    required String email,
    required String password,
  }) async {
    final service = kiosk;
    final current = session;
    if (service == null ||
        current == null ||
        !(current.isOwner || current.isSupervisor)) {
      throw const KioskUnlockFailure('access_denied');
    }
    await service.lock(currentEmail: email, currentPassword: password);
    kioskLocked = true;
    unawaited(KioskNative.setLockTask(true));
    unawaited(_auditKiosk('kiosk_lock'));
    _notify();
  }

  /// Appelé par la page kiosque pour (dés)activer l'épinglage natif.
  void setKioskNativeLock(bool locked) =>
      unawaited(KioskNative.setLockTask(locked));

  /// Déverrouillage kiosque : email + mot de passe owner/supervisor.
  Future<void> unlockKiosk({
    required String email,
    required String password,
  }) async {
    final service = kiosk;
    if (service == null) throw const KioskUnlockFailure('access_denied');
    final online = sync?.state.value.phase != SyncPhase.offline;
    await service.unlock(email: email, password: password, isOnline: online);
    kioskLocked = false;
    unawaited(KioskNative.setLockTask(false));
    unawaited(_auditKiosk('kiosk_unlock'));
    _notify();
  }

  Future<void> _auditKiosk(String action) async {
    try {
      await client.rpc(
        'audit',
        params: {
          'p_action': action,
          'p_entity': 'gyms',
          'p_entity_id': session?.gymId,
          'p_details': {'actor': session?.staffId},
        },
      );
    } catch (_) {}
  }

  Future<void> signOut() async {
    final user = client.auth.currentUser;
    if (user != null) await _secure.delete(key: _cacheKey(user.id));
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      errorCode = 'logout_failed';
      phase = SessionPhase.blocked;
      _notify();
      return;
    }
    await _schedule(_reset);
  }

  Future<void> finishPasswordRecovery(String password) async {
    if (busy || phase != SessionPhase.recovery) return;
    if (password.length < 12 || password.length > 128) {
      errorCode = 'weak_password';
      _notify();
      return;
    }
    busy = true;
    errorCode = null;
    _notify();
    try {
      await client.auth
          .updateUser(UserAttributes(password: password))
          .timeout(const Duration(seconds: 30));
      _recoveringPassword = false;
      await signOut();
    } on AuthException {
      errorCode = 'password_update_failed';
    } catch (_) {
      errorCode = 'network';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _reset() async {
    _recoveringPassword = false;
    phase = SessionPhase.signedOut;
    session = null;
    pin = null;
    _passwordLoginAt = null;
    errorCode = null;
    await _closeWorkspace();
    _notify();
  }

  Future<void> shutdown() async {
    _disposed = true;
    _idleTimer?.cancel();
    await _auth?.cancel();
    await _serial;
    await _closeWorkspace();
    super.dispose();
  }
}
