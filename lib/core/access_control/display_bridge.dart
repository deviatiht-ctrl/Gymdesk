import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'display_bridge_platform_stub.dart'
    if (dart.library.io) 'display_bridge_platform_io.dart'
    if (dart.library.js_interop) 'display_bridge_platform_web.dart';
import 'terminal_access_service.dart';

/// Lien temps réel entre la fenêtre principale (qui surveille le terminal W2 et
/// décide) et la fenêtre « 2e écran » (affichage devant la porte).
///
/// * Hôte : publie chaque décision dès qu'elle est prise + un battement d'état
///   (agent/terminal) toutes les 2 s.
/// * Écran : affiche les décisions reçues ; s'il n'y a aucun hôte (fenêtre
///   principale fermée), il démarre lui-même la surveillance.
class AccessDisplayBridge {
  AccessDisplayBridge._();
  static final instance = AccessDisplayBridge._();

  final _platform = DisplayBridgePlatform();
  final String _sid = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

  bool get launchedAsDisplay => _platform.launchedAsDisplay;
  String? get launchRoute => _platform.launchRoute;
  void setLaunchArgs(List<String> args) => _platform.setLaunchArgs(args);

  // ---------------------------------------------------------------- hôte
  Timer? _heartbeat;
  bool Function()? _agentOnline;
  bool Function()? _terminalOnline;

  Future<void> startHost({required bool Function() agentOnline, required bool Function() terminalOnline}) async {
    _agentOnline = agentOnline;
    _terminalOnline = terminalOnline;
    await _platform.startHost((raw) {
      final msg = _decode(raw);
      if (msg != null && msg['type'] == 'ping' && msg['sid'] != _sid) _sendStatus();
    });
    _heartbeat ??= Timer.periodic(const Duration(seconds: 2), (_) => _sendStatus());
    _sendStatus();
  }

  void stopHost() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _platform.hostPost(jsonEncode({'type': 'bye', 'sid': _sid}));
    _platform.stopHost();
  }

  void _sendStatus() {
    if (_heartbeat == null && _agentOnline == null) return;
    _platform.hostPost(jsonEncode({
      'type': 'status',
      'sid': _sid,
      'agent': _agentOnline?.call() ?? false,
      'terminal': _terminalOnline?.call() ?? false,
    }));
  }

  void publishDecision(AccessDecision decision) {
    if (_heartbeat == null) return;
    _platform.hostPost(jsonEncode({
      'type': 'decision',
      'sid': _sid,
      'outcome': decision.outcome.name,
      'has_person': decision.person != null,
      'opened_by_app': decision.openedByApp,
      'uid': decision.uid,
      'row': TerminalAccessService.eventRowFor(decision),
    }));
  }

  // ---------------------------------------------------------------- écran
  final hostAlive = ValueNotifier<bool>(false);
  final hostAgentOnline = ValueNotifier<bool>(false);
  final hostTerminalOnline = ValueNotifier<bool>(false);
  final _decisions = StreamController<AccessDecision>.broadcast();
  DateTime? _lastStatus;
  bool _listening = false;

  Stream<AccessDecision> get decisions => _decisions.stream;

  void startDisplay() {
    if (_listening) return;
    _listening = true;
    _platform.listen(_onDisplayMessage, (connected) {
      if (!connected) _markAlive(false);
    });
    _platform.post(jsonEncode({'type': 'ping', 'sid': _sid}));
    Timer.periodic(const Duration(seconds: 2), (_) {
      final last = _lastStatus;
      if (last == null || DateTime.now().difference(last) > const Duration(seconds: 7)) _markAlive(false);
    });
  }

  void _markAlive(bool alive) {
    if (hostAlive.value != alive) hostAlive.value = alive;
  }

  void _onDisplayMessage(String raw) {
    final msg = _decode(raw);
    if (msg == null || msg['sid'] == _sid) return;
    switch (msg['type']) {
      case 'status':
        _lastStatus = DateTime.now();
        _markAlive(true);
        hostAgentOnline.value = msg['agent'] == true;
        hostTerminalOnline.value = msg['terminal'] == true;
      case 'bye':
        _lastStatus = null;
        _markAlive(false);
      case 'decision':
        _lastStatus = DateTime.now();
        _markAlive(true);
        final decision = decisionFromMessage(msg);
        if (decision != null && !_decisions.isClosed) _decisions.add(decision);
    }
  }

  @visibleForTesting
  static AccessDecision? decisionFromMessage(Map<String, dynamic> msg) {
    final outcome = AccessOutcome.values.where((o) => o.name == msg['outcome']).firstOrNull;
    if (outcome == null) return null;
    final row = Map<String, dynamic>.from(msg['row'] as Map? ?? const {});
    final snapshot = Map<String, dynamic>.from(row['member_snapshot'] as Map? ?? const {});
    if (row['member_id'] != null) snapshot.putIfAbsent('member_id', () => row['member_id']);
    return AccessDecision(
      outcome,
      person: msg['has_person'] == true && snapshot.isNotEmpty ? AccessPerson.fromSnapshot(snapshot) : null,
      openedByApp: msg['opened_by_app'] == true,
      uid: msg['uid'] as String?,
    );
  }

  Future<bool> openDisplayWindow(String route) => _platform.openDisplayWindow(route);
  String? displayUrlFor(String route) => _platform.displayUrlFor(route);
  void closeCurrentWindow() => _platform.closeCurrentWindow();

  static Map<String, dynamic>? _decode(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }
}
