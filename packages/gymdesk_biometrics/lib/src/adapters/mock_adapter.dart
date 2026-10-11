import 'dart:async';
import 'dart:convert';
import '../fingerprint_reader.dart';
import '../models.dart';

class MockReaderAdapter implements ReaderVendorAdapter {
  @override
  String get vendorId => 'mock';

  @override
  String get displayName => 'Simulateur / Lecteur Virtuel';

  @override
  bool supports(UsbIdentity id) {
    return id.vid.toLowerCase() == '0x0000' || id.vendorName == 'Mock';
  }

  @override
  Future<FingerprintReader> create(UsbIdentity id) async {
    return MockFingerprintReader(id);
  }
}

class MockFingerprintReader implements FingerprintReader {
  MockFingerprintReader([UsbIdentity? id])
      : identity = id ??
            const UsbIdentity(
              vid: '0x0000',
              pid: '0x0000',
              vendorName: 'Mock',
              productName: 'Simulateur Empreinte',
            );

  final UsbIdentity identity;
  final _eventController = StreamController<ReaderEvent>.broadcast();
  bool _isOpen = false;

  @override
  ReaderInfo get info => ReaderInfo(
        vendor: 'Simulateur',
        model: 'Lecteur Virtuel GymDesk',
        vid: identity.vid,
        pid: identity.pid,
        serial: 'SIM-001',
        firmware: 'v1.0.0',
      );

  @override
  ReaderCapabilities get capabilities => const ReaderCapabilities(
        hasLivePreview: true,
        hasLivenessDetection: true,
        supportedFormats: ['raw_mock', 'iso_19794_2'],
        hasNative1N: true,
        max1NCandidates: 50000,
      );

  @override
  Stream<ReaderEvent> get events => _eventController.stream;

  @override
  Future<void> open() async {
    _isOpen = true;
    _eventController.add(const ReaderEvent(
      type: ReaderEventType.connected,
      message: 'Simulateur d’empreinte connecté.',
    ));
  }

  @override
  Future<void> close() async {
    _isOpen = false;
    _eventController.add(const ReaderEvent(
      type: ReaderEventType.disconnected,
      message: 'Simulateur déconnecté.',
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
      message: 'Doigt posé sur le simulateur.',
    ));

    await Future<void>.delayed(const Duration(milliseconds: 200));

    final sampleBytes = utf8.encode('MOCK_TEMPLATE_${DateTime.now().millisecondsSinceEpoch}');
    final template = base64Encode(sampleBytes);

    _eventController.add(const ReaderEvent(
      type: ReaderEventType.imageCaptured,
      message: 'Capture virtuelle réussie.',
      quality: 95,
    ));

    return Capture(
      template: template,
      quality: 95,
      isoTemplate: 'ISO_$template',
    );
  }

  @override
  Future<bool> verify(
    Template enrolled,
    Capture probe, {
    MatchLevel level = MatchLevel.normal,
  }) async {
    return enrolled.data == probe.template;
  }

  @override
  Future<IdentifyResult?> identify(
    Capture probe,
    Iterable<Template> candidates, {
    MatchLevel level = MatchLevel.normal,
  }) async {
    for (final c in candidates) {
      if (c.data == probe.template) {
        return IdentifyResult(
          memberId: c.memberId ?? '',
          score: 1.0,
          fingerIndex: c.fingerIndex,
          matchedTemplate: c,
        );
      }
    }
    return null;
  }
}
