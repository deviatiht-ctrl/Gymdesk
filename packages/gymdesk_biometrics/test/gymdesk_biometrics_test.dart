import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk_biometrics/gymdesk_biometrics.dart';

void main() {
  group('ReaderRegistry Tests', () {
    test('Registry initializes with all multi-vendor adapters', () {
      final registry = ReaderRegistry.instance;
      expect(registry.adapters.length, greaterThanOrEqualTo(5));

      final vendors = registry.adapters.map((a) => a.vendorId).toList();
      expect(vendors, contains('suprema'));
      expect(vendors, contains('digitalpersona'));
      expect(vendors, contains('zkteco'));
      expect(vendors, contains('secugen'));
      expect(vendors, contains('mock'));
    });

    test('Identifies official Suprema BioMini hardware VID/PID', () {
      final registry = ReaderRegistry.instance;
      expect(registry.isKnownSupported('0x1612', '0x000B'), isTrue); // BioMini Plus 2
      expect(registry.isKnownSupported('0x1612', '0x0011'), isTrue); // BioMini Slim 2
      expect(registry.isKnownSupported('0x05BA', '0x000A'), isTrue); // DigitalPersona 4500
      expect(registry.isKnownSupported('0x9999', '0x9999'), isFalse);
    });

    test('Finds proper vendor adapter by USB identity', () {
      final registry = ReaderRegistry.instance;
      final supremaId = const UsbIdentity(vid: '0x1612', pid: '0x000B', productName: 'BioMini Plus 2');
      final adapter = registry.findAdapter(supremaId);

      expect(adapter, isNotNull);
      expect(adapter!.vendorId, equals('suprema'));
      expect(adapter.displayName, contains('Suprema'));
    });
  });

  group('Suprema BioMini Reader Tests', () {
    test('Open, capture, verify and identify', () async {
      final id = const UsbIdentity(vid: '0x1612', pid: '0x000B', productName: 'BioMini Plus 2');
      final reader = SupremaBioMiniReader(id);

      expect(reader.info.vendor, equals('Suprema'));
      expect(reader.capabilities.hasLivePreview, isTrue);
      expect(reader.capabilities.hasLivenessDetection, isTrue);

      final capture = await reader.capture();
      expect(capture.template, isNotEmpty);
      expect(capture.quality, greaterThanOrEqualTo(75));

      // 1:1 Verify
      final enrolled = Template(
        data: capture.template,
        vendor: 'suprema',
        templateFormat: 'suprema_384',
        memberId: 'mem_123',
      );
      final verified = await reader.verify(enrolled, capture);
      expect(verified, isTrue);

      // 1:N Identify
      final candidates = [
        enrolled,
        const Template(data: 'OTHER_DIFFERENT_TEMPLATE', vendor: 'suprema', templateFormat: 'suprema_384', memberId: 'mem_999'),
      ];
      final match = await reader.identify(capture, candidates);
      expect(match, isNotNull);
      expect(match!.memberId, equals('mem_123'));
      expect(match.score, greaterThanOrEqualTo(0.9));

      await reader.close();
    });
  });

  group('DoorController Tests', () {
    test('NoopDoorController opens successfully in simulation', () async {
      const controller = NoopDoorController();
      expect(controller.type, equals('none'));

      final ok = await controller.openDoor(pulseDuration: const Duration(seconds: 3));
      expect(ok, isTrue);

      final status = await controller.getStatus();
      expect(status, equals(DoorState.closed));
    });

    test('UsbSerialRelayDoorController handles connection failures gracefully', () async {
      final controller = UsbSerialRelayDoorController(
        port: 'COM99',
        agentBaseUrl: 'http://127.0.0.1:59999', // Port inexistant
      );
      expect(controller.type, equals('usb_serial_relay'));

      final ok = await controller.openDoor();
      expect(ok, isFalse); // Résilient, ne crashe pas
    });
  });
}
