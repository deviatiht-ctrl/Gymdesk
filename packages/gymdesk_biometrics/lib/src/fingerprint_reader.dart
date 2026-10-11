import 'dart:async';
import 'models.dart';

abstract class FingerprintReader {
  ReaderInfo get info;
  ReaderCapabilities get capabilities;

  Future<void> open();
  Future<void> close();

  Stream<ReaderEvent> get events;

  Future<Capture> capture({
    Duration timeout = const Duration(seconds: 10),
    int minQuality = 60,
  });

  Future<bool> verify(
    Template enrolled,
    Capture probe, {
    MatchLevel level = MatchLevel.normal,
  });

  Future<IdentifyResult?> identify(
    Capture probe,
    Iterable<Template> candidates, {
    MatchLevel level = MatchLevel.normal,
  });
}

abstract class ReaderVendorAdapter {
  String get vendorId;
  String get displayName;

  bool supports(UsbIdentity id);

  Future<FingerprintReader> create(UsbIdentity id);
}
