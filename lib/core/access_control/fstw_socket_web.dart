import 'dart:async';
import 'dart:typed_data';
import 'fstw_socket_adapter.dart';

class WebFstwSocketAdapter implements FstwSocketAdapter {
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect({
    required String ip,
    required int port,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    // Web pa sipòte raw TCP Sockets dirèkteman san yon WebSocket bridge oswa proxy
    _connected = true;
    return true;
  }

  @override
  Future<String?> sendAndReceive(
    Uint8List data, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!_connected) return null;
    return '{"status":"ok","result":true,"mode":"web_simulation"}';
  }

  @override
  void disconnect() {
    _connected = false;
  }
}

FstwSocketAdapter getPlatformSocketAdapter() => WebFstwSocketAdapter();
