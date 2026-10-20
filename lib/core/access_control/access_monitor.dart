import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/runtime.dart';
import '../biometrics/access_agent_client.dart';
import '../biometrics/agent_launcher.dart';
import 'terminal_access_service.dart';

/// Yon sèl siveyan tèminal W2 pou tout app la (PC Windows sèlman).
/// Li kouri depi sesyon an pare, kèlkeswa paj ki louvri: evènman yo trete,
/// pòt la ouvri (mòd app), evènman an pibliye sou Supabase, epi tout ekran
/// (popup global, Kontwòl aksè, 2yèm ekran) resevwa menm desizyon an.
class AccessMonitor {
  AccessMonitor._();
  static final instance = AccessMonitor._();

  final agent = AccessAgentClient();
  final _decisions = StreamController<AccessDecision>.broadcast();
  final agentOnline = ValueNotifier<bool>(true);
  final terminalOnline = ValueNotifier<bool>(false);

  TerminalAccessService? _service;
  TerminalAccessConfig config = const TerminalAccessConfig();
  StreamSubscription<Map<String, dynamic>>? _events;
  Timer? _syncTimer;
  String? _gymId;
  bool _syncing = false;
  bool _relaunching = false;

  Stream<AccessDecision> get decisions => _decisions.stream;
  TerminalAccessService? get service => _service;

  /// Vre lè PC sa a trete evènman tèminal la li menm — ekran yo dwe inyore
  /// evènman realtime `source=terminal` (se PC sa a ki te pibliye yo).
  bool get active => _events != null;

  Future<void> start(AppRuntime runtime) async {
    final session = runtime.session;
    final db = runtime.database;
    if (kIsWeb) return;
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
    await ensureAccessAgentRunning();
    config = await TerminalAccessService.loadConfig(runtime.client, session);
    terminalOnline.value = await agent.watchTerminal(terminalIp: config.terminalIp);
    unawaited(syncNow());
    _syncTimer = Timer.periodic(const Duration(minutes: 10), (_) => unawaited(syncNow()));
  }

  void stop() {
    _events?.cancel();
    _events = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _service = null;
    _gymId = null;
  }

  /// Dat abònman (renouvèlman, ekspirasyon) ak nouvo anprent yo rive sou W2 a.
  Future<TerminalSyncResult?> syncNow() async {
    final service = _service;
    if (service == null || _syncing) return null;
    _syncing = true;
    try {
      return await service.syncToTerminal(config);
    } catch (_) {
      return null;
    } finally {
      _syncing = false;
    }
  }

  /// Manm/anplwaye fenk modifye: rechaje kach la pou pwochen scan an.
  void invalidate() => _service?.invalidate();

  Future<void> _onEvent(Map<String, dynamic> event) async {
    switch (event['type']) {
      case 'agent_status':
        final online = event['online'] == true;
        agentOnline.value = online;
        terminalOnline.value = event['terminal_watch'] == true;
        if (!online || !terminalOnline.value) unawaited(_relaunch());
        return;
      case 'terminal_watch':
        terminalOnline.value = event['online'] == true;
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
        terminalOnline.value = await agent.watchTerminal(terminalIp: config.terminalIp);
      }
    } finally {
      _relaunching = false;
    }
  }
}
