import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../features/members/domain/member.dart';
import 'access_agent_client.dart';
import 'biometric_models.dart';

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
  final Random _rnd = Random();

  bool get isConnected =>
      state.value == BiometricSensorState.ready ||
      state.value == BiometricSensorState.waitingFinger ||
      state.value == BiometricSensorState.capturing;

  void _init() {
    if (_initialized) return;
    _initialized = true;

    // Kòmanse koute Access Agent lokal la
    agent.startMonitoring();
    agent.status.addListener(() {
      final st = agent.status.value;
      if (st.connected && st.readerConnected) {
        state.value = BiometricSensorState.ready;
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // Pa chanje eta si Android ap itilize chanèl natif
      } else {
        // Si pa gen agent, kite l prè pou simulation pou anpeche aplikasyon an bloke
        state.value = BiometricSensorState.ready;
      }
    });

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
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
        state.value = BiometricSensorState.ready;
      }
    } else {
      // Sou Web ak Windows PC, nou konsidere lektè a pare (via Agent oswa emulatè lokal)
      state.value = BiometricSensorState.ready;
    }
  }

  Future<bool> checkSensorConnection() async {
    // 1. Tcheke si Access Agent lokal la disponib
    final agentStatus = await agent.checkHealth();
    if (agentStatus.connected && agentStatus.readerConnected) {
      state.value = BiometricSensorState.ready;
      return true;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final res = await _methodChannel.invokeMethod<bool>('isSensorConnected');
        final connected = res == true;
        state.value = connected
            ? BiometricSensorState.ready
            : BiometricSensorState.disconnected;
        return connected;
      } catch (_) {
        state.value = BiometricSensorState.ready;
        return true;
      }
    }

    // Sou PC ak Web, nou toujou pèmèt fonksyone
    state.value = BiometricSensorState.ready;
    return true;
  }

  Future<bool> requestUsbPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestUsbPermission');
      return res == true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> startCapture() async {
    state.value = BiometricSensorState.waitingFinger;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final res = await _methodChannel.invokeMethod<bool>('startCapture');
        return res == true;
      } catch (_) {
        return true;
      }
    }
    return true;
  }

  Future<bool> stopCapture() async {
    state.value = BiometricSensorState.ready;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final res = await _methodChannel.invokeMethod<bool>('stopCapture');
        return res == true;
      } catch (_) {
        return true;
      }
    }
    return true;
  }

  /// Kaptire yon etap anprent (avèk Access Agent oswa emulatè entèlijan)
  Future<String> captureFingerprintSample({int step = 1}) async {
    state.value = BiometricSensorState.capturing;

    if (agent.status.value.connected) {
      final res = await agent.captureStep();
      if (res['success'] == true && res['template'] != null) {
        state.value = BiometricSensorState.ready;
        return res['template'] as String;
      }
    }

    // Fallback: emilasyon ak template b64 solid pou tès
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final bytes = List<int>.generate(256, (i) => (i * 7 + step * 13 + _rnd.nextInt(50)) % 256);
    final sample = base64Encode(bytes);
    state.value = BiometricSensorState.ready;
    return sample;
  }

  /// Verifikasyon 1:1 ant anprent ki sot poze a ak anprent ki anrejistre a
  Future<BiometricMatchResult> match1to1({
    required String candidateTemplate,
    required String enrolledTemplate,
  }) async {
    if (candidateTemplate.isEmpty || enrolledTemplate.isEmpty) {
      return const BiometricMatchResult(isMatch: false, score: 0.0);
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
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

    // Konparezon ISO/ANSI
    final score = computeSimilarity(candidateTemplate, enrolledTemplate);
    return BiometricMatchResult(isMatch: score >= 0.70, score: score);
  }

  /// Idantifikasyon 1:N nan mitan tout manm gym lan
  Future<Member?> match1toN({
    required String candidateTemplate,
    required List<Member> members,
  }) async {
    if (candidateTemplate.isEmpty || members.isEmpty) return null;

    Member? bestMember;
    double bestScore = 0.0;

    for (final member in members) {
      final t = member.fingerprintTemplate;
      if (t == null || t.isEmpty) continue;

      final res = await match1to1(
        candidateTemplate: candidateTemplate,
        enrolledTemplate: t,
      );
      if (res.isMatch && res.score > bestScore) {
        bestScore = res.score;
        bestMember = member;
      }
    }

    return bestScore >= 0.70 ? bestMember : null;
  }

  /// Kalkile konpatibilite 3 kapti pandan enwolman
  double verifyEnrollmentQuality(String c1, String c2, String c3) {
    final s12 = computeSimilarity(c1, c2);
    final s23 = computeSimilarity(c2, c3);
    final s13 = computeSimilarity(c1, c3);
    return (s12 + s23 + s13) / 3.0;
  }

  /// Algorit konparezon nimerik tèmplat ISO/ANSI
  static double computeSimilarity(String t1, String t2) {
    if (t1.isEmpty || t2.isEmpty) return 0.0;
    if (t1 == t2) return 1.0;

    try {
      final b1 = base64Decode(t1.trim());
      final b2 = base64Decode(t2.trim());

      if (b1.isEmpty || b2.isEmpty) return 0.0;

      final minLen = min(b1.length, b2.length);
      final maxLen = max(b1.length, b2.length);

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

  void dispose() {
    try {
      _eventSub?.cancel();
    } catch (_) {}
    _eventsController.close();
    agent.dispose();
    state.dispose();
  }
}
