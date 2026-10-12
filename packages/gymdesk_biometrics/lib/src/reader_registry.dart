import 'adapters/digital_persona_adapter.dart';
import 'adapters/mock_adapter.dart';
import 'adapters/secugen_adapter.dart';
import 'adapters/suprema_adapter.dart';
import 'adapters/zkteco_adapter.dart';
import 'fingerprint_reader.dart';
import 'models.dart';

class ReaderRegistry {
  ReaderRegistry() {
    registerAdapter(SupremaBioMiniAdapter());
    registerAdapter(DigitalPersonaAdapter());
    registerAdapter(ZKTecoAdapter());
    registerAdapter(SecuGenAdapter());
    registerAdapter(MockReaderAdapter());
  }

  static final ReaderRegistry instance = ReaderRegistry();

  final List<ReaderVendorAdapter> _adapters = [];

  List<ReaderVendorAdapter> get adapters => List.unmodifiable(_adapters);

  void registerAdapter(ReaderVendorAdapter adapter) {
    _adapters.removeWhere((a) => a.vendorId == adapter.vendorId);
    _adapters.add(adapter);
  }

  ReaderVendorAdapter? findAdapter(UsbIdentity identity) {
    for (final adapter in _adapters) {
      if (adapter.supports(identity)) {
        return adapter;
      }
    }
    return null;
  }

  Future<FingerprintReader?> createReaderFor(UsbIdentity identity) async {
    final adapter = findAdapter(identity);
    if (adapter == null) return null;
    return adapter.create(identity);
  }

  /// Vérifie si l'appareil USB correspond à la liste officielle des lecteurs supportés.
  bool isKnownSupported(String vid, String pid) {
    final v = vid.toLowerCase().replaceAll('0x', '');
    final p = pid.toLowerCase().replaceAll('0x', '');

    const knownPairs = {
      // Suprema
      '16d1:0409',
      '1612:0001', '1612:0002', '1612:0005', '1612:000b', '1612:000c', '1612:0011', '1612:0012',
      // DigitalPersona
      '05ba:000a', '05ba:000c',
      // ZKTeco
      '1b55:0120', '2724:0003',
      // SecuGen
      '1162:2200',
    };

    return knownPairs.contains('$v:$p');
  }

  /// Détecte les lecteurs branchés (supporte communication agent local 47811 ou fallback)
  Future<List<UsbIdentity>> detectConnectedDevices({
    List<Map<String, dynamic>>? rawDevices,
  }) async {
    final results = <UsbIdentity>[];

    if (rawDevices != null) {
      for (final dev in rawDevices) {
        final vid = (dev['vid'] ?? '').toString();
        final pid = (dev['pid'] ?? '').toString();
        final vendor = dev['vendor'] as String?;
        final product = dev['product'] as String?;
        final serial = dev['serial'] as String?;

        final id = UsbIdentity(
          vid: vid.startsWith('0x') ? vid : '0x$vid',
          pid: pid.startsWith('0x') ? pid : '0x$pid',
          vendorName: vendor,
          productName: product,
          serialNumber: serial,
        );
        results.add(id);
      }
    }

    return results;
  }
}
