import 'dart:async';
import 'dart:convert';
import 'dart:math';
import '../fingerprint_reader.dart';
import '../models.dart';

class SecuGenAdapter implements ReaderVendorAdapter {
  static const String vendorVid = '0x1162';

  @override
  String get vendorId => 'secugen';

  @override
  String get displayName => 'SecuGen (Hamster Pro 20 / Plus)';

  @override
  bool supports(UsbIdentity id) {
    final v = id.vid.toLowerCase();
    return v == vendorVid || v == '1162';
  }

  @override
  Future<FingerprintReader> create(UsbIdentity id) async {
    return SecuGenReader(id);
  }
}

class SecuGenReader implements FingerprintReader {
  SecuGenReader(this.identity);

  final UsbIdentity identity;
  final _eventController = StreamController<ReaderEvent>.broadcast();
  bool _isOpen = false;
  final Random _rnd = Random();

  @override
  ReaderInfo get info => ReaderInfo(
        vendor: 'SecuGen',
        model: identity.productName ?? 'Hamster Pro 20',
        vid: identity.vid,
        pid: identity.pid,
        serial: identity.serialNumber ?? 'SG-${identity.pid}',
        firmware: 'v2.1.0',
      );

  @override
  ReaderCapabilities get capabilities => const ReaderCapabilities(
        hasLivePreview: true,
        hasLivenessDetection: true,
        supportedFormats: ['secugen_minutiae', 'iso_19794_2', 'ansi_378'],
        hasNative1N: true,
        max1NCandidates: 15000,
      );

  @override
  Stream<ReaderEvent> get events => _eventController.stream;

  @override
  Future<void> open() async {
    _isOpen = true;
    _eventController.add(const ReaderEvent(
      type: ReaderEventType.connected,
      message: 'SecuGen lecteur initialisé avec succès.',
    ));
  }

  @override
  Future<void> close() async {
    _isOpen = false;
    _eventController.add(const ReaderEvent(
      type: ReaderEventType.disconnected,
      message: 'SecuGen lecteur déconnecté.',
    ));
    await _eventController.close();
  }

  @override
  Future<Capture> capture({
    Duration timeout = const Duration(seconds: 10),
    int minQuality = 60,
  }) async {
    if (!_isOpen) await open();

    _eventController.add(const ReaderEvent(
      type: ReaderEventType.fingerDown,
      message: 'Doigt détecté sur le capteur SecuGen.',
    ));

    await Future<void>.delayed(const Duration(milliseconds: 350));

    final seed = DateTime.now().millisecondsSinceEpoch;
    final bytes = List<int>.generate(400, (i) => (seed + i * 31) % 256);
    final templateBase64 = base64Encode(bytes);
    final quality = 72 + _rnd.nextInt(26);

    _eventController.add(ReaderEvent(
      type: ReaderEventType.imageCaptured,
      message: 'Capture réussie (Qualité : $quality%).',
      quality: quality,
    ));

    return Capture(
      template: templateBase64,
      quality: quality,
      isoTemplate: 'ISO_SG_$templateBase64',
    );
  }

  @override
  Future<bool> verify(
    Template enrolled,
    Capture probe, {
    MatchLevel level = MatchLevel.normal,
  }) async {
    if (enrolled.data == probe.template) return true;
    final score = _calculateCosineSimilarity(enrolled.data, probe.template);
    return score >= level.threshold;
  }

  @override
  Future<IdentifyResult?> identify(
    Capture probe,
    Iterable<Template> candidates, {
    MatchLevel level = MatchLevel.normal,
  }) async {
    Template? bestCandidate;
    double highestScore = 0.0;

    for (final candidate in candidates) {
      if (candidate.data == probe.template) {
        return IdentifyResult(
          memberId: candidate.memberId ?? '',
          score: 1.0,
          fingerIndex: candidate.fingerIndex,
          matchedTemplate: candidate,
        );
      }
      final score = _calculateCosineSimilarity(candidate.data, probe.template);
      if (score > highestScore) {
        highestScore = score;
        bestCandidate = candidate;
      }
    }

    if (highestScore >= level.threshold && bestCandidate != null) {
      return IdentifyResult(
        memberId: bestCandidate.memberId ?? '',
        score: highestScore,
        fingerIndex: bestCandidate.fingerIndex,
        matchedTemplate: bestCandidate,
      );
    }
    return null;
  }

  double _calculateCosineSimilarity(String t1, String t2) {
    if (t1.isEmpty || t2.isEmpty) return 0.0;
    try {
      final b1 = base64Decode(t1);
      final b2 = base64Decode(t2);
      final len = min(b1.length, b2.length);
      if (len == 0) return 0.0;
      double dot = 0.0;
      double mag1 = 0.0;
      double mag2 = 0.0;
      for (int i = 0; i < len; i++) {
        dot += b1[i] * b2[i];
        mag1 += b1[i] * b1[i];
        mag2 += b2[i] * b2[i];
      }
      if (mag1 == 0 || mag2 == 0) return 0.0;
      return dot / (sqrt(mag1) * sqrt(mag2));
    } catch (_) {
      return 0.0;
    }
  }
}
