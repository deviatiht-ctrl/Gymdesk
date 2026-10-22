import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/runtime.dart';
import '../biometrics/access_agent_client.dart';
import '../biometrics/agent_launcher.dart';
import '../sync/sync_models.dart';
import 'terminal_access_service.dart';

/// Yon sèl siveyan tèminal W2 pou tout app la (Windows Desktop ak Web sou PC resepsyon).
/// Li kouri depi sesyon an pare, kèlkeswa paj ki louvri: evènman yo trete,
/// pòt la ouvri (mòd app), evènman an pibliye sou Supabase, epi tout ekran
/// (popup global, Kontwòl aksè, 2yèm ekran) resevwa menm desizyon an.
/// Chak fwa yon manm, anprent, abònman oswa peman chanje, li pouse mizajou a
/// sou tèminal W2 a otomatikman an < 1 segonn (delta sync).
class AccessMonitor {
  AccessMonitor._();
  static final instance = AccessMonitor._();

  final agent = AccessAgentClient();
  final _decisions = StreamController<AccessDecision>.broadcast();
  final agentOnline = ValueNotifier<bool>(false);
  final terminalOnline = ValueNotifier<bool>(false);

  TerminalAccessService? _service;
  TerminalAccessConfig config = const TerminalAccessConfig();
  StreamSubscription<Map<String, dynamic>>? _events;
  final List<StreamSubscription<dynamic>> _dbSubs = [];
  Timer? _syncTimer;
  Timer? _debounceSync;
  String? _gymId;
  bool _syncing = false;
  bool _pendingSync = false;
  bool _pendingForceFull = false;
  bool _relaunching = false;

  Stream<AccessDecision> get decisions => _decisions.stream;
  TerminalAccessService? get service => _service;

  /// Vre lè PC sa a konekte ak ajan lokal la epi trete evènman tèminal la li menm —
  /// ekran yo dwe inyore evènman realtime `source=terminal` (se PC sa a ki te pibliye yo).
  bool get active => _events != null && agentOnline.value;

  Future<void> start(AppRuntime runtime) async {
    final session = runtime.session;
    final db = runtime.database;
    if (session == null ||
        db == null ||
        session.gymId == null ||
        !{'owner', 'supervisor', 'reception'}.contains(session.role)) {
      stop();
      return;
    }
    if (_gymId == session.gymId && _events != null) return;
    stop();
    _gymId = session.gymId;
    _service = TerminalAccessService(runtime.client, db, session, agent: agent);
    _events = agent.terminalEvents().listen(_onEvent);

    // Siveye tout chanjman lokal (manm, anprent, abònman, peman, anplwaye) pou
    // pouse nouvo anprent ak dat ekspirasyon sou pòt W2 a otomatikman san bouton.
    for (final entity in const [
      SyncEntity.members,
      SyncEntity.subscriptions,
      SyncEntity.payments,
      SyncEntity.employees,
    ]) {
      _dbSubs.add(
        db.watchRecords(entity, limit: 50000).skip(1).listen((_) {
          notifyDataChanged();
        }),
      );
    }

    unawaited(_initConnection(runtime));
    _syncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(syncNow()),
    );
  }

  Future<void> _initConnection(AppRuntime runtime) async {
    final session = runtime.session;
    if (session == null) return;
    final running = await ensureAccessAgentRunning();
    agentOnline.value = running;
    config = await TerminalAccessService.loadConfig(runtime.client, session);
    if (running) {
      terminalOnline.value = await agent.watchTerminal(terminalIp: config.terminalIp);
      unawaited(syncNow());
    }
  }

  void stop() {
    _events?.cancel();
    _events = null;
    for (final sub in _dbSubs) {
      sub.cancel();
    }
    _dbSubs.clear();
    _debounceSync?.cancel();
    _debounceSync = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _service = null;
    _gymId = null;
    agentOnline.value = false;
    terminalOnline.value = false;
  }

  /// Dat abònman (renouvèlman, ekspirasyon) ak nouvo anprent yo rive sou W2 a.
  Future<TerminalSyncResult?> syncNow({bool forceFull = false}) async {
    final service = _service;
    if (service == null) return null;
    service.invalidate();
    if (_syncing) {
      _pendingSync = true;
      _pendingForceFull = _pendingForceFull || forceFull;
      return null;
    }
    _syncing = true;
    try {
      return await service.syncToTerminal(config, forceFull: forceFull);
    } catch (_) {
      return null;
    } finally {
      _syncing = false;
      if (_pendingSync) {
        final nextForce = _pendingForceFull;
        _pendingSync = false;
        _pendingForceFull = false;
        unawaited(syncNow(forceFull: nextForce));
      }
    }
  }

  /// Manm/anplwaye/abònman fenk modifye: rechaje kach la epi pouse chanjman an sou W2 a an < 400ms.
  void notifyDataChanged() {
    _service?.invalidate();
    _debounceSync?.cancel();
    _debounceSync = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(syncNow(forceFull: false)),
    );
  }

  /// Manm/anplwaye fenk modifye: rechaje kach la pou pwochen scan an.
  void invalidate() => notifyDataChanged();

  Future<void> _onEvent(Map<String, dynamic> event) async {
    switch (event['type']) {
      case 'agent_status':
        final online = event['online'] == true;
        final wasWatch = terminalOnline.value;
        final nowWatch = event['terminal_watch'] == true;
        agentOnline.value = online;
        terminalOnline.value = nowWatch;
        if (!online || !nowWatch) {
          unawaited(_relaunch());
        } else if (!wasWatch && nowWatch) {
          unawaited(syncNow());
        }
        return;
      case 'terminal_watch':
        final wasWatch = terminalOnline.value;
        final nowWatch = event['online'] == true;
        terminalOnline.value = nowWatch;
        if (!wasWatch && nowWatch) {
          unawaited(syncNow());
        }
        return;
      case 'usb_reader':
        agent.checkHealth();
        return;
    }
    final service = _service;
    if (service == null) return;
    final decision = await service.handleTerminalEvent(event, config);
    if (decision != null && !_decisions.isClosed) _decisions.add(decision);
  }

  Future<void> _relaunch() async {
    if (_relaunching || _service == null) return;
    _relaunching = true;
    try {
      if (await ensureAccessAgentRunning() && _service != null) {
        agentOnline.value = true;
        final online = await agent.watchTerminal(terminalIp: config.terminalIp);
        final wasOnline = terminalOnline.value;
        terminalOnline.value = online;
        if (!wasOnline && online) {
          unawaited(syncNow());
        }
      }
    } finally {
      _relaunching = false;
    }
  }
}
