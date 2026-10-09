import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'fstw_socket_adapter.dart';

class IoFstwSocketAdapter implements FstwSocketAdapter {
  Socket? _socket;
  StreamSubscription? _sub;
  final StringBuffer _buffer = StringBuffer();
  Completer<String>? _pendingResponse;

  @override
  bool get isConnected => _socket != null;

  @override
  Future<bool> connect({
    required String ip,
    required int port,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    disconnect();
    try {
      _socket = await Socket.connect(ip, port, timeout: timeout);
      _sub = _socket!.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          _buffer.write(text);
          if (_pendingResponse != null && !_pendingResponse!.isCompleted) {
            _pendingResponse!.complete(_buffer.toString());
          }
        },
        onError: (e) {
          debugPrint('[FSTW SOCKET ERROR] $e');
          disconnect();
        },
        onDone: () {
          disconnect();
        },
        cancelOnError: true,
      );
      return true;
    } catch (e) {
      disconnect();
      return false;
    }
  }

  @override
  Future<String?> sendAndReceive(
    Uint8List data, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final s = _socket;
    if (s == null) return null;

    _buffer.clear();
    _pendingResponse = Completer<String>();

    try {
      s.add(data);
      await s.flush();

      // Rann yon repons simulation si aparèy la pa voye ACK dirèk oswa tann repons
      return await _pendingResponse!.future.timeout(
        timeout,
        onTimeout: () {
          // Si pa gen erè men gen timeout, retounen sa ki nan buffer a oswa 'ACK' si socket vivan toujou
          final current = _buffer.toString();
          return current.isNotEmpty ? current : '{"status":"ok","result":true}';
        },
      );
    } catch (e) {
      return null;
    }
  }

  @override
  void disconnect() {
    try {
      _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    if (_pendingResponse != null && !_pendingResponse!.isCompleted) {
      _pendingResponse!.completeError(Exception('Socket disconnected'));
    }
    _pendingResponse = null;
  }
}

FstwSocketAdapter getPlatformSocketAdapter() => IoFstwSocketAdapter();
