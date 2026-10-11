import 'dart:async';
import 'package:http/http.dart' as http;

enum DoorState { closed, open, unlocking, error }

abstract class DoorController {
  String get type;
  Future<bool> openDoor({Duration pulseDuration = const Duration(seconds: 3)});
  Future<DoorState> getStatus();
}

class NoopDoorController implements DoorController {
  const NoopDoorController();

  @override
  String get type => 'none';

  @override
  Future<bool> openDoor({Duration pulseDuration = const Duration(seconds: 3)}) async {
    // Mode sans relais : simple simulation logicielle
    return true;
  }

  @override
  Future<DoorState> getStatus() async => DoorState.closed;
}

class UsbSerialRelayDoorController implements DoorController {
  UsbSerialRelayDoorController({
    required this.port,
    this.baudRate = 9600,
    this.agentBaseUrl = 'http://127.0.0.1:47811',
  });

  final String port; // e.g. "COM3"
  final int baudRate;
  final String agentBaseUrl;

  @override
  String get type => 'usb_serial_relay';

  @override
  Future<bool> openDoor({Duration pulseDuration = const Duration(seconds: 3)}) async {
    try {
      final uri = Uri.parse('$agentBaseUrl/api/relay/pulse');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: '''{
          "port": "$port",
          "baudRate": $baudRate,
          "durationMs": ${pulseDuration.inMilliseconds}
        }''',
      ).timeout(const Duration(seconds: 4));

      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DoorState> getStatus() async {
    try {
      final uri = Uri.parse('$agentBaseUrl/api/relay/status?port=$port');
      final res = await http.get(uri).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) return DoorState.closed;
      return DoorState.error;
    } catch (_) {
      return DoorState.error;
    }
  }
}

class HttpRelayDoorController implements DoorController {
  HttpRelayDoorController({
    required this.endpointUrl,
    this.httpMethod = 'POST',
    this.authToken,
  });

  final String endpointUrl; // e.g. "http://192.168.1.50/relay/0?turn=on"
  final String httpMethod;
  final String? authToken;

  @override
  String get type => 'http_relay';

  @override
  Future<bool> openDoor({Duration pulseDuration = const Duration(seconds: 3)}) async {
    try {
      final uri = Uri.parse(endpointUrl);
      final headers = <String, String>{
        if (authToken != null && authToken!.isNotEmpty) 'Authorization': 'Bearer $authToken',
      };

      http.Response res;
      if (httpMethod.toUpperCase() == 'POST') {
        res = await http.post(
          uri,
          headers: headers,
          body: '{"duration": ${pulseDuration.inSeconds}}',
        ).timeout(const Duration(seconds: 4));
      } else {
        res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 4));
      }

      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DoorState> getStatus() async => DoorState.closed;
}
