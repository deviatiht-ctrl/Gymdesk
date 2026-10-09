import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_desk/core/access_control/fstw_access_control_service.dart';
import 'package:gym_desk/core/access_control/fstw_socket_adapter.dart';

class MockFstwSocketAdapter implements FstwSocketAdapter {
  bool shouldFail = false;
  bool _connected = false;
  final List<Uint8List> sentPackets = [];

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect({
    required String ip,
    required int port,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (shouldFail) {
      _connected = false;
      return false;
    }
    _connected = true;
    return true;
  }

  @override
  Future<String?> sendAndReceive(
    Uint8List data, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (shouldFail || !_connected) return null;
    sentPackets.add(data);
    return '{"status":"ok","result":true,"msg":"ACK"}';
  }

  @override
  void disconnect() {
    _connected = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FSTW F30 Access Control Service', () {
    late MockFstwSocketAdapter mockSocket;
    late FstwAccessControlService service;

    setUp(() {
      mockSocket = MockFstwSocketAdapter();
      service = FstwAccessControlService(socketAdapter: mockSocket);
      service.configure(gymId: 'gym-123', ip: '192.168.1.200', port: 5005);
    });

    tearDown(() {
      service.dispose();
    });

    test('connectDevice successfully establishes connection', () async {
      final ok = await service.connectDevice('192.168.1.200', 5005);
      expect(ok, isTrue);
      expect(service.isConnected, isTrue);
      expect(service.state.value, FstwDeviceState.connected);
    });

    test('connectDevice handles offline / connection refusal gracefully', () async {
      mockSocket.shouldFail = true;
      final ok = await service.connectDevice('192.168.1.200', 5005);
      expect(ok, isFalse);
      expect(service.isConnected, isFalse);
      expect(service.state.value, FstwDeviceState.disconnected);
    });

    test('sendUserFingerprint sends payload and handles success', () async {
      final success = await service.sendUserFingerprint(
        'user-abc',
        'TEMPLATE_BASE64_BYTES==',
        'Jean Baptiste',
      );
      expect(success, isTrue);
      expect(mockSocket.sentPackets.length, 1);
    });

    test('sendUserFingerprint handles offline error without crashing', () async {
      mockSocket.shouldFail = true;
      final success = await service.sendUserFingerprint(
        'user-abc',
        'TEMPLATE_BASE64_BYTES==',
        'Jean Baptiste',
      );
      expect(success, isFalse);
      // Socket failed but did not throw unhandled exception
    });

    test('deleteUser sends deletion command over TCP socket', () async {
      final success = await service.deleteUser('user-abc');
      expect(success, isTrue);
      expect(mockSocket.sentPackets.length, 1);
    });

    test('setTemporaryPin sends temporary pin with expiration', () async {
      final expiration = DateTime.now().add(const Duration(hours: 12));
      final success = await service.setTemporaryPin('user-guest', '849201', expiration);
      expect(success, isTrue);
      expect(mockSocket.sentPackets.length, 1);
    });
  });
}
