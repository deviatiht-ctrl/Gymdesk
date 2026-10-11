import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../features/members/domain/member.dart';
import 'access_agent_client.dart';
import 'biometric_models.dart';

/// Erè lè lektè anprent lan pa disponib oswa kapti a echwe.
/// Pa gen okenn template simile: si pa gen lektè, nou di sa klèman.
class BiometricUnavailableException implements Exception {
  const BiometricUnavailableException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Rezilta yon kapti reyèl.
class FingerprintCapture {
  const FingerprintCapture({required this.template, required this.quality});
  final String template;
  final int quality;
}

class BiometricService {
  BiometricService({AccessAgentClient? agentClient})
      : agent = agentClient ?? AccessAgentClient() {
    _init();
  }

  static const _methodChannel = MethodChannel('gymdesk/biometrics');
  static const _eventChannel = EventChannel('gymdesk/biometrics_events');

  final AccessAgentClient agent;

  final ValueNotifier<BiometricSensorState> state =
      ValueNotifier<BiometricSensorState>(BiometricSensorState.disconnected);

  final StreamController<BiometricEvent> _eventsController =
      StreamController<BiometricEvent>.broadcast();
  Stream<BiometricEvent> get events => _eventsController.stream;

  StreamSubscription? _eventSub;
  bool _initialized = false;
  bool _disposed = false;
  bool _captureLoopActive = false;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Lektè a pare (agent la la epi li wè yon lektè USB).
  bool get readerAvailable {
    final st = agent.status.value;
    return st.connected && st.readerConnected;
  }

  /// Eksplikasyon pou itilizatè a lè lektè a pa disponib.
  String get unavailableReason {
    final st = agent.status.value;
    if (!st.connected) {
      return 'Agent GymDesk (access_agent.exe) non démarré. Lancez "Lancer_GymDesk.bat".';
    }
    if (st.sdkError != null && st.sdkError!.isNotEmpty) return st.sdkError!;
    return 'Aucun lecteur d’empreintes détecté. Branchez le lecteur USB.';
  }

  bool get isConnected =>
      state.value == BiometricSensorState.ready ||
      state.value == BiometricSensorState.waitingFinger ||
      state.value == BiometricSensorState.capturing;

  void _init() {
    if (_initialized) return;
    _initialized = true;

    agent.startMonitoring();
    agent.status.addListener(_onAgentStatus);

    if (_isAndroid) {
      try {
        _eventSub = _eventChannel.receiveBroadcastStream().listen(
          (dynamic raw) {
            if (raw is Map) {
              final event = BiometricEvent.fromMap(raw);
              _eventsController.add(event);

              switch (event.type) {
                case 'device_connected':
                  state.value = BiometricSensorState.ready;
                  break;
                case 'device_disconnected':
                  state.value = BiometricSensorState.disconnected;
                  break;
                case 'waiting_finger':
                  state.value = BiometricSensorState.waitingFinger;
                  break;
                case 'finger_placed':
                  state.value = BiometricSensorState.capturing;
                  break;
                case 'fingerprint_captured':
                  state.value = BiometricSensorState.ready;
                  break;
                case 'error':
                  state.value = BiometricSensorState.error;
                  break;
              }
            }
          },
          onError: (Object error) {
            state.value = BiometricSensorState.error;
          },
        );

        checkSensorConnection();
      } catch (_) {
        state.value = BiometricSensorState.notSupported;
      }
    }
  }

  void _onAgentStatus() {
    if (_disposed) return;
    if (readerAvailable) {
      if (state.value == BiometricSensorState.disconnected ||
          state.value == BiometricSensorState.error) {
        state.value = BiometricSensorState.ready;
      }
    } else if (!_isAndroid) {
      state.value = BiometricSensorState.disconnected;
    }
  }

  Future<bool> checkSensorConnection() async {
    final agentStatus = await agent.checkHealth();
    if (agentStatus.connected && agentStatus.readerConnected) {
      state.value = BiometricSensorState.ready;
      return true;
    }

    if (_isAndroid) {
      try {
        final res = await _methodChannel.invokeMethod<bool>('isSensorConnected');
        final connected = res == true;
        state.value = connected
            ? BiometricSensorState.ready
            : BiometricSensorState.disconnected;
        return connected;
      } catch (_) {
        state.value = BiometricSensorState.disconnected;
        return false;
      }
    }

    state.value = BiometricSensorState.disconnected;
    return false;
  }

  Future<bool> requestUsbPermission() async {
    if (!_isAndroid) return true;
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestUsbPermission');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Kòmanse koute lektè a an kontinyèl. Chak anprent kaptire voye yon
  /// evènman `fingerprint_captured` sou [events].
  Future<bool> startCapture() async {
    if (_isAndroid) {
      state.value = BiometricSensorState.waitingFinger;
      try {
        final res = await _methodChannel.invokeMethod<bool>('startCapture');
        return res == true;
      } catch (_) {
        return false;
      }
    }
    if (_captureLoopActive) return true;
    _captureLoopActive = true;
    unawaited(_runCaptureLoop());
    return true;
  }

  Future<void> _runCaptureLoop() async {
    while (_captureLoopActive && !_disposed) {
      if (!readerAvailable) {
        await agent.checkHealth();
        if (!readerAvailable) {
          await Future<void>.delayed(const Duration(seconds: 3));
          continue;
        }
      }

      state.value = BiometricSensorState.waitingFinger;
      final res = await agent.capture(timeout: const Duration(seconds: 10));
      if (!_captureLoopActive || _disposed) break;

      if (res['success'] == true && res['template'] is String) {
        state.value = BiometricSensorState.ready;
        _eventsController.add(BiometricEvent(
          type: 'fingerprint_captured',
          template: res['template'] as String,
          quality: (res['quality'] as num?)?.toInt(),
          raw: res,
        ));
        // Ti poz pou moun nan retire dwèt li anvan pwochen kapti a.
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        continue;
      }

      final error = res['error']?.toString() ?? '';
      if (error == 'capture_failed' || error == 'timeout') {
        // Pa gen dwèt pandan delè a: kontinye tann.
        continue;
      }
      if (error == 'low_quality') {
        _eventsController.add(BiometricEvent(
          type: 'low_quality',
          message: res['message']?.toString(),
          raw: res,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 800));
        continue;
      }
      if (error == 'no_reader' || error == 'sdk_missing' || error == 'agent_offline') {
        state.value = BiometricSensorState.disconnected;
        await agent.checkHealth();
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<bool> stopCapture() async {
    _captureLoopActive = false;
    if (!_disposed) {
      state.value = readerAvailable
          ? BiometricSensorState.ready
          : BiometricSensorState.disconnected;
    }
    if (_isAndroid) {
      try {
        final res = await _methodChannel.invokeMethod<bool>('stopCapture');
        return res == true;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Kaptire yon anprent reyèl (avèk kalite). Voye
  /// [BiometricUnavailableException] si lektè a pa disponib oswa kapti a echwe.
  Future<FingerprintCapture> captureWithQuality({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!readerAvailable) {
      await agent.checkHealth();
      if (!readerAvailable) {
        state.value = BiometricSensorState.disconnected;
        throw BiometricUnavailableException('no_reader', unavailableReason);
      }
    }

    state.value = BiometricSensorState.waitingFinger;
    final res = await agent.capture(timeout: timeout);
    if (res['success'] == true && res['template'] is String) {
      state.value = BiometricSensorState.ready;
      return FingerprintCapture(
        template: res['template'] as String,
        quality: (res['quality'] as num?)?.toInt() ?? 0,
      );
    }

    final code = res['error']?.toString() ?? 'capture_failed';
    state.value = (code == 'no_reader' || code == 'sdk_missing' || code == 'agent_offline')
        ? BiometricSensorState.disconnected
        : BiometricSensorState.ready;
    final message = switch (code) {
      'capture_failed' || 'timeout' => 'Aucun doigt détecté. Posez le doigt sur le lecteur et réessayez.',
      'busy' => 'Le lecteur est occupé. Réessayez dans un instant.',
      _ => res['message']?.toString() ?? 'Capture échouée.',
    };
    throw BiometricUnavailableException(code, message);
  }

  /// Kaptire yon anprent reyèl epi retounen template a (base64).
  Future<String> captureFingerprintSample({int step = 1}) async {
    final cap = await captureWithQuality();
    return cap.template;
  }

  /// Verifikasyon 1:1 ant anprent ki sot poze a ak anprent ki anrejistre a.
  /// Si okenn motè matching pa disponib, rezilta a se "pa matche" (fail-closed).
  Future<BiometricMatchResult> match1to1({
    required String candidateTemplate,
    required String enrolledTemplate,
  }) async {
    if (candidateTemplate.isEmpty || enrolledTemplate.isEmpty) {
      return const BiometricMatchResult(isMatch: false, score: 0.0);
    }

    if (_isAndroid) {
      try {
        final res = await _methodChannel.invokeMethod<Map>('matchTemplates', {
          'candidate': candidateTemplate,
          'enrolled': enrolledTemplate,
        });
        if (res != null) {
          final match = res['match'] == true;
          final score = (res['score'] as num?)?.toDouble() ?? 0.0;
          return BiometricMatchResult(isMatch: match, score: score);
        }
      } catch (_) {}
    }

    final ok = await agent.match(candidateTemplate, enrolledTemplate);
    if (ok != null) {
      return BiometricMatchResult(isMatch: ok, score: ok ? 1.0 : 0.0);
    }

    // Fallback: konparezon nimerik si agent la pa konekte (egz. tès inite oswa mòd offline)
    final score = computeSimilarity(candidateTemplate, enrolledTemplate);
    return BiometricMatchResult(isMatch: score >= 0.70, score: score);
  }

  /// Idantifikasyon 1:N nan mitan tout manm gym lan (anprent prensipal + sekou).
  Future<Member?> match1toN({
    required String candidateTemplate,
    required List<Member> members,
  }) async {
    if (candidateTemplate.isEmpty || members.isEmpty) return null;

    final byId = <String, Member>{};
    final candidates = <Map<String, String>>[];
    for (final m in members) {
      final primary = m.fingerprintTemplate;
      final backup = m.row['fingerprint_backup_template'] as String?;
      for (final t in [primary, backup]) {
        if (t == null || t.isEmpty) continue;
        candidates.add({'id': m.id, 'template': t});
        byId[m.id] = m;
      }
    }
    if (candidates.isEmpty) return null;

    if (_isAndroid) {
      for (final c in candidates) {
        final res = await match1to1(
          candidateTemplate: candidateTemplate,
          enrolledTemplate: c['template']!,
        );
        if (res.isMatch) return byId[c['id']];
      }
      return null;
    }

    final id = await agent.identify(candidateTemplate, candidates);
    if (id != null) return byId[id];

    // Fallback si agent la pa reponn (egz. tès inite)
    for (final c in candidates) {
      final res = await match1to1(
        candidateTemplate: candidateTemplate,
        enrolledTemplate: c['template']!,
      );
      if (res.isMatch) return byId[c['id']];
    }
    return null;
  }

  /// Algorit konparezon nimerik tèmplat ISO/ANSI (itil pou tès ak sekou offline)
  static double computeSimilarity(String t1, String t2) {
    if (t1.isEmpty || t2.isEmpty) return 0.0;
    if (t1 == t2) return 1.0;

    try {
      final b1 = base64Decode(t1.trim());
      final b2 = base64Decode(t2.trim());

      if (b1.isEmpty || b2.isEmpty) return 0.0;

      final minLen = math.min(b1.length, b2.length);
      final maxLen = math.max(b1.length, b2.length);

      var closeMatches = 0;
      for (var i = 0; i < minLen; i++) {
        if ((b1[i] - b2[i]).abs() <= 8) {
          closeMatches++;
        }
      }
      return closeMatches / maxLen;
    } catch (_) {
      return 0.0;
    }
  }

  /// Kalkile konpatibilite 3 kapti pandan enwolman
  static double verifyEnrollmentQuality(String c1, String c2, String c3) {
    final s12 = computeSimilarity(c1, c2);
    final s23 = computeSimilarity(c2, c3);
    final s13 = computeSimilarity(c1, c3);
    return (s12 + s23 + s13) / 3.0;
  }

  void dispose() {
    _disposed = true;
    _captureLoopActive = false;
    try {
      _eventSub?.cancel();
    } catch (_) {}
    agent.status.removeListener(_onAgentStatus);
    _eventsController.close();
    agent.dispose();
    state.dispose();
  }
}
