// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'suprema_ffi.dart';

/// Lektè Suprema atravè `suprema_bridge32.exe` (DLL SDK 32-bit, agent 64-bit).
///
/// stdin pa janm rive lè Dart lanse yon pwosesis .NET sou Windows, kidonk
/// chak kòmand lanse pon an yon fwa ak argiman yo epi li sòti apre repons lan:
///   `suprema_bridge32.exe dllDir kòmand [arg...]`  ->  yon liy sou stdout
/// Apèl yo seyansyalize pa [_queue] pou de apèl SDK a pa janm fè an menm tan.
class SupremaBridge extends ReaderBackend {
  SupremaBridge._(this._exe, this._dir);

  final String _exe;
  final String _dir;
  Future<void> _queue = Future.value();
  bool _alive = true;

  @override
  String? scannerId;
  @override
  int scannerCount = 0;
  @override
  String get mode => 'bridge32';
  bool get alive => _alive;

  static const exeName = 'suprema_bridge32.exe';

  /// Verifye pon an mache (li inisyalize SDK a epi reponn `status`).
  /// Retounen null (ak rezon an nan [SupremaSdk.lastLoadError]) sinon.
  static Future<SupremaBridge?> start(String bridgePath, String dllDir) async {
    final bridge = SupremaBridge._(bridgePath, dllDir);
    try {
      await bridge._status();
      print('[SUPREMA] SDK 32-bit chaje atravè $exeName depi $dllDir');
      return bridge;
    } on SupremaException catch (e) {
      SupremaSdk.lastLoadError = 'Pon 32-bit: ${e.message}';
      return null;
    } catch (e) {
      SupremaSdk.lastLoadError = 'Pon 32-bit pa ka lanse ($bridgePath): $e';
      return null;
    }
  }

  /// Lanse pon an pou yon sèl kòmand; retounen chan repons lan (separe pa TAB).
  Future<List<String>> _call(List<String> command, {Duration timeout = const Duration(seconds: 15)}) {
    final result = _queue.then((_) => _run(command, timeout));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<String>> _run(List<String> command, Duration timeout) async {
    Process process;
    try {
      process = await Process.start(_exe, [_dir, ...command], workingDirectory: _dir);
    } catch (e) {
      _alive = false;
      throw SupremaException('sdk_error', 'Pon 32-bit pa ka lanse: $e');
    }
    final out = StringBuffer();
    unawaited(process.stderr.drain<void>());
    final sub = process.stdout.transform(utf8.decoder).listen(out.write);
    var killed = false;
    final timer = Timer(timeout, () {
      killed = true;
      process.kill();
    });
    await process.exitCode;
    timer.cancel();
    await sub.cancel();
    if (killed) {
      _alive = false;
      throw SupremaException('sdk_error', 'Pon 32-bit la pa reponn (timeout).');
    }
    final line = out.toString().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
    if (line.isEmpty) throw SupremaException('sdk_error', 'Pon 32-bit la pa t bay okenn repons.');
    final parts = line.split('\t');
    if (parts.first == 'err') {
      throw SupremaException(parts.length > 1 ? parts[1] : 'sdk_error', parts.length > 2 ? parts[2] : 'Erreur SDK');
    }
    return parts;
  }

  Future<void> _status() async {
    final r = await _call(['status']);
    scannerCount = int.tryParse(r[1]) ?? 0;
    scannerId = r.length > 2 && r[2].isNotEmpty ? r[2] : null;
  }

  @override
  Future<void> refresh() async {
    try {
      await _status();
    } catch (_) {
      scannerCount = 0;
      scannerId = null;
    }
  }

  @override
  Future<SupremaCapture> capture({int timeoutMs = 10000, int minQuality = 50}) async {
    final r = await _call(['capture', '$timeoutMs'], timeout: Duration(milliseconds: timeoutMs + 15000));
    final quality = int.tryParse(r[2]) ?? 0;
    if (quality < minQuality) {
      throw SupremaException('low_quality', 'Qualité insuffisante ($quality%). Reposez le doigt bien à plat.');
    }
    return SupremaCapture(templateB64: r[1], quality: quality);
  }

  @override
  Future<bool> verify(String aB64, String bB64) async =>
      (await _call(['verify', aB64.trim(), bB64.trim()]))[1] == '1';

  @override
  Future<int> identify(String probeB64, List<String> candidatesB64) async {
    // Kandida yo ka twò long pou liy kòmand lan: pase yo nan yon fichye tanporè.
    final tmp = File('$_dir${Platform.pathSeparator}bridge_candidates_${DateTime.now().microsecondsSinceEpoch}.txt');
    try {
      await tmp.writeAsString(candidatesB64.map((c) => c.trim()).join('\n'), flush: true);
      final r = await _call(['identify', probeB64.trim(), tmp.path], timeout: const Duration(seconds: 90));
      return int.tryParse(r[1]) ?? -1;
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}
