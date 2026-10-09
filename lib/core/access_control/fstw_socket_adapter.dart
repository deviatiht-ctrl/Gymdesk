import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

// Kondisyonèl enpòt pou sipòte Web san erè konpilasyon sou dart:io
import 'fstw_socket_io.dart' if (dart.library.js_interop) 'fstw_socket_web.dart';

/// Koòdone abstrè pou kominikasyon socket FSTW F30
abstract class FstwSocketAdapter {
  bool get isConnected;
  Future<bool> connect({required String ip, required int port, Duration timeout = const Duration(seconds: 4)});
  Future<String?> sendAndReceive(Uint8List data, {Duration timeout = const Duration(seconds: 4)});
  void disconnect();
}

FstwSocketAdapter createFstwSocketAdapter() => getPlatformSocketAdapter();
