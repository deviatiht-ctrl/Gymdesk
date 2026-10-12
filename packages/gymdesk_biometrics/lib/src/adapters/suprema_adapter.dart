import 'dart:async';
import 'dart:convert';
import 'dart:math';
import '../fingerprint_reader.dart';
import '../models.dart';

class SupremaBioMiniAdapter implements ReaderVendorAdapter {
  static const String vendorVid = '0x16D1';

  @override
  String get vendorId => 'suprema';

  @override
  String get displayName => 'Suprema BioMini';

  @override
  bool supports(UsbIdentity id) {
    final v = id.vid.toLowerCase().replaceAll('0x', '');
    return v == '16d1' || v == '1612';
  }

  @override
  Future<FingerprintReader> create(UsbIdentity id) async {
    return SupremaBioMiniReader(id);
  }
}

class SupremaBioMiniReader implements FingerprintReader {
  SupremaBioMiniReader(this.identity);

  final UsbIdentity identity;
  final _eventController = StreamController<ReaderEvent>.broadcast();
  bool _isOpen = false;
  final Random _rnd = Random();

  @override
  ReaderInfo get info => ReaderInfo(
        vendor: 'Suprema',
        model: identity.productName ?? 'BioMini Plus 2',
        vid: identity.vid,
        pid: identity.pid,
        serial: identity.serialNumber ?? 'BM-SUP-${identity.pid}',
        firmware: 'v3.2.0-LFD',
      );

  @override
  ReaderCapabilities get capabilities => const ReaderCapabilities(
        hasLivePreview: true,
        hasLivenessDetection: true,
        supportedFormats: ['suprema_384', 'iso_19794_2', 'ansi_378'],
        hasNative1N: true,
        max1NCandidates: 100000,
      );

  @override
  Stream<ReaderEvent> get events => _eventController.stream;

  @override
  Future<void> open() async {
    _isOpen = true;
    _eventController.add(const ReaderEvent(
      type: ReaderEventType.connected,
      message: 'Suprema BioMini initialisé avec succès.',
    ));
  }

  @override
  Future<void> close() async {
    _isOpen = false;
    _eventController.add(const ReaderEvent(
      type: ReaderEventType.disconnected,
      message: 'Suprema BioMini déconnecté.',
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
      message: 'Doigt détecté sur le capteur Suprema.',
    ));

    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Simulation de template Suprema standard (384 bytes)
    final seed = DateTime.now().millisecondsSinceEpoch;
    final bytes = List<int>.generate(384, (i) => (seed + i * 17) % 256);
    final templateBase64 = base64Encode(bytes);
    final quality = 80 + _rnd.nextInt(18); // 80-97 score de qualité élevé Suprema

    _eventController.add(ReaderEvent(
      type: ReaderEventType.imageCaptured,
      message: 'Capture réussie (Qualité : $quality%).',
      quality: quality,
    ));

    return Capture(
      template: templateBase64,
      quality: quality,
      isoTemplate: 'ISO_19794_$templateBase64',
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
