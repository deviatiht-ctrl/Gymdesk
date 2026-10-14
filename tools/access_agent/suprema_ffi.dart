// ignore_for_file: avoid_print, non_constant_identifier_names
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Binding FFI pou Suprema BioMini SDK (Windows).
///
/// Bezwen `UFScanner.dll` + `UFMatcher.dll` (ak DLL depandans yo) ki vini
/// avèk "Suprema BioMini SDK for Windows". Mete yo bò kote `access_agent.exe`
/// oswa nan yon sou-dosye `sdk/`.
///
/// Tout template yo an fòma ISO 19794-2 pou yo rete konpatib ant lektè.

const int ufsOk = 0;
const int ufsParamTimeout = 201;
const int templateTypeIso19794_2 = 2002;
const int templateTypeSuprema = 2001;
const int maxTemplateSize = 1024;

// ---------------------------------------------------------------------------
// Alokasyon memwa natif san pakè `ffi` (ole32 CoTaskMemAlloc / CoTaskMemFree).
// ---------------------------------------------------------------------------
final DynamicLibrary _ole32 = DynamicLibrary.open('ole32.dll');
final Pointer<Void> Function(int) _coAlloc = _ole32
    .lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('CoTaskMemAlloc');
final void Function(Pointer<Void>) _coFree = _ole32
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('CoTaskMemFree');

Pointer<T> _alloc<T extends NativeType>(int bytes) {
  final p = _coAlloc(bytes);
  if (p == nullptr) throw StateError('CoTaskMemAlloc($bytes) failed');
  final u8 = p.cast<Uint8>();
  for (var i = 0; i < bytes; i++) {
    u8[i] = 0;
  }
  return p.cast<T>();
}

void _free(Pointer p) => _coFree(p.cast<Void>());

Pointer<Uint8> _bytesToNative(Uint8List data) {
  final p = _alloc<Uint8>(data.isEmpty ? 1 : data.length);
  p.asTypedList(data.length).setAll(0, data);
  return p;
}

String _cString(Pointer<Uint8> p, int max) {
  final bytes = <int>[];
  for (var i = 0; i < max; i++) {
    final b = p[i];
    if (b == 0) break;
    bytes.add(b);
  }
  return latin1.decode(bytes).trim();
}

void _setDllDirectory(String dir) {
  try {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final setDir = k32.lookupFunction<Int32 Function(Pointer<Uint16>), int Function(Pointer<Uint16>)>(
        'SetDllDirectoryW');
    final units = dir.codeUnits;
    final p = _alloc<Uint16>((units.length + 1) * 2);
    for (var i = 0; i < units.length; i++) {
      p[i] = units[i];
    }
    p[units.length] = 0;
    setDir(p);
    _free(p);
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Siyati fonksyon SDK yo (UFScanner.h / UFMatcher.h)
// ---------------------------------------------------------------------------
typedef _NoArgN = Int32 Function();
typedef _NoArgD = int Function();
typedef _IntPtrArgN = Int32 Function(Pointer<Int32>);
typedef _IntPtrArgD = int Function(Pointer<Int32>);
typedef _GetHandleN = Int32 Function(Int32, Pointer<Pointer<Void>>);
typedef _GetHandleD = int Function(int, Pointer<Pointer<Void>>);
typedef _HandleN = Int32 Function(Pointer<Void>);
typedef _HandleD = int Function(Pointer<Void>);
typedef _HandleIntN = Int32 Function(Pointer<Void>, Int32);
typedef _HandleIntD = int Function(Pointer<Void>, int);
typedef _HandleStrN = Int32 Function(Pointer<Void>, Pointer<Uint8>);
typedef _HandleStrD = int Function(Pointer<Void>, Pointer<Uint8>);
typedef _SetParamN = Int32 Function(Pointer<Void>, Int32, Pointer<Void>);
typedef _SetParamD = int Function(Pointer<Void>, int, Pointer<Void>);
typedef _ExtractExN = Int32 Function(Pointer<Void>, Int32, Pointer<Uint8>, Pointer<Int32>, Pointer<Int32>);
typedef _ExtractExD = int Function(Pointer<Void>, int, Pointer<Uint8>, Pointer<Int32>, Pointer<Int32>);
typedef _ExtractN = Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int32>, Pointer<Int32>);
typedef _ExtractD = int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int32>, Pointer<Int32>);
typedef _ErrStrN = Int32 Function(Int32, Pointer<Uint8>);
typedef _ErrStrD = int Function(int, Pointer<Uint8>);
typedef _CreateN = Int32 Function(Pointer<Pointer<Void>>);
typedef _CreateD = int Function(Pointer<Pointer<Void>>);
typedef _VerifyN = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Uint8>, Int32, Pointer<Int32>);
typedef _VerifyD = int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Int32>);

class _Api {
  _Api(String dir) {
    _setDllDirectory(dir);
    scanner = DynamicLibrary.open('$dir${Platform.pathSeparator}UFScanner.dll');
    matcher = DynamicLibrary.open('$dir${Platform.pathSeparator}UFMatcher.dll');

    init = scanner.lookupFunction<_NoArgN, _NoArgD>('UFS_Init');
    update = scanner.lookupFunction<_NoArgN, _NoArgD>('UFS_Update');
    getScannerNumber = scanner.lookupFunction<_IntPtrArgN, _IntPtrArgD>('UFS_GetScannerNumber');
    getScannerHandle = scanner.lookupFunction<_GetHandleN, _GetHandleD>('UFS_GetScannerHandle');
    getScannerId = scanner.lookupFunction<_HandleStrN, _HandleStrD>('UFS_GetScannerID');
    setParameter = scanner.lookupFunction<_SetParamN, _SetParamD>('UFS_SetParameter');
    clearBuffer = scanner.lookupFunction<_HandleN, _HandleD>('UFS_ClearCaptureImageBuffer');
    captureSingle = scanner.lookupFunction<_HandleN, _HandleD>('UFS_CaptureSingleImage');
    errorString = scanner.lookupFunction<_ErrStrN, _ErrStrD>('UFS_GetErrorString');
    try {
      setTemplateType = scanner.lookupFunction<_HandleIntN, _HandleIntD>('UFS_SetTemplateType');
    } catch (_) {
      setTemplateType = null;
    }
    try {
      extractEx = scanner.lookupFunction<_ExtractExN, _ExtractExD>('UFS_ExtractEx');
    } catch (_) {
      extractEx = null;
    }
    try {
      extract = scanner.lookupFunction<_ExtractN, _ExtractD>('UFS_Extract');
    } catch (_) {
      extract = null;
    }

    ufmCreate = matcher.lookupFunction<_CreateN, _CreateD>('UFM_Create');
    ufmVerify = matcher.lookupFunction<_VerifyN, _VerifyD>('UFM_Verify');
    try {
      ufmSetTemplateType = matcher.lookupFunction<_HandleIntN, _HandleIntD>('UFM_SetTemplateType');
    } catch (_) {
      ufmSetTemplateType = null;
    }
  }

  late final DynamicLibrary scanner;
  late final DynamicLibrary matcher;
  late final _NoArgD init;
  late final _NoArgD update;
  late final _IntPtrArgD getScannerNumber;
  late final _GetHandleD getScannerHandle;
  late final _HandleStrD getScannerId;
  late final _SetParamD setParameter;
  late final _HandleD clearBuffer;
  late final _HandleD captureSingle;
  late final _ErrStrD errorString;
  late final _HandleIntD? setTemplateType;
  late final _ExtractExD? extractEx;
  late final _ExtractD? extract;
  late final _CreateD ufmCreate;
  late final _VerifyD ufmVerify;
  late final _HandleIntD? ufmSetTemplateType;

  String describe(int code) {
    final buf = _alloc<Uint8>(256);
    try {
      errorString(code, buf);
      final s = _cString(buf, 256);
      return s.isEmpty ? 'code $code' : '$s (code $code)';
    } catch (_) {
      return 'code $code';
    } finally {
      _free(buf);
    }
  }
}

/// Rezilta yon kapti reyèl.
class SupremaCapture {
  const SupremaCapture({required this.templateB64, required this.quality});
  final String templateB64;
  final int quality;
}

/// Sa agent la bezwen nan yon lektè, kit DLL yo chaje dirèkteman (x64),
/// kit atravè pon 32-bit la (`suprema_bridge32.exe`).
abstract class ReaderBackend {
  String? get scannerId;
  int get scannerCount;
  bool get readerConnected => scannerCount > 0;
  String get mode;
  Future<void> refresh();
  Future<SupremaCapture> capture({int timeoutMs = 10000, int minQuality = 50, int tplType = templateTypeIso19794_2});
  Future<bool> verify(String aB64, String bB64);

  /// Endèks premye kandida ki koresponn, oswa -1.
  Future<int> identify(String probeB64, List<String> candidatesB64) async {
    for (var i = 0; i < candidatesB64.length; i++) {
      if (candidatesB64[i].isNotEmpty && await verify(probeB64, candidatesB64[i])) return i;
    }
    return -1;
  }
}

/// Achitekti yon DLL Windows (lekti antèt PE a): 32 oswa 64, null si enkoni.
int? dllBits(String path) {
  try {
    final b = File(path).readAsBytesSync();
    final pe = ByteData.sublistView(b).getUint32(0x3c, Endian.little);
    final machine = ByteData.sublistView(b).getUint16(pe + 4, Endian.little);
    return machine == 0x8664 ? 64 : machine == 0x14c ? 32 : null;
  } catch (_) {
    return null;
  }
}

class SupremaException implements Exception {
  SupremaException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Kontwolè SDK Suprema pou agent la (DLL ki gen menm achitekti ak agent la).
class SupremaSdk extends ReaderBackend {
  SupremaSdk._(this.dir, this._api);

  final String dir;
  final _Api _api;
  Pointer<Void> _matcher = nullptr;
  @override
  String? scannerId;
  @override
  int scannerCount = 0;
  @override
  String get mode => 'ffi';

  /// Erè chajman dènye tantativ la (pou /health).
  static String? lastLoadError;

  /// Chèche DLL yo nan kandida yo epi inisyalize SDK a.
  static SupremaSdk? load(List<String> candidateDirs) {
    final agentBits = sizeOf<IntPtr>() * 8;
    for (final dir in candidateDirs) {
      final f = File('$dir${Platform.pathSeparator}UFScanner.dll');
      if (!f.existsSync()) continue;
      final bits = dllBits(f.path);
      if (bits != null && bits != agentBits) {
        lastLoadError = 'UFScanner.dll ($dir) se $bits-bit, agent la se $agentBits-bit.';
        continue;
      }
      try {
        final api = _Api(dir);
        final rc = api.init();
        if (rc != ufsOk) {
          lastLoadError = 'UFS_Init: ${api.describe(rc)}';
          continue;
        }
        final sdk = SupremaSdk._(dir, api);
        sdk._initMatcher();
        sdk._refreshSync();
        lastLoadError = null;
        print('[SUPREMA] SDK chaje depi $dir');
        return sdk;
      } catch (e) {
        lastLoadError = 'Chajman SDK echwe ($dir): $e';
      }
    }
    lastLoadError ??= 'UFScanner.dll / UFMatcher.dll pa jwenn. Kopye SDK Suprema a bò kote access_agent.exe.';
    return null;
  }

  void _initMatcher() {
    final pp = _alloc<Pointer<Void>>(sizeOf<Pointer<Void>>());
    try {
      final rc = _api.ufmCreate(pp);
      if (rc != ufsOk) throw SupremaException('matcher_init', 'UFM_Create: $rc');
      _matcher = pp.value;
      _api.ufmSetTemplateType?.call(_matcher, templateTypeIso19794_2);
    } finally {
      _free(pp);
    }
  }

  @override
  Future<void> refresh() async => _refreshSync();

  /// Rafrechi lis lektè yo (USB plug-and-play).
  void _refreshSync() {
    final pn = _alloc<Int32>(4);
    try {
      _api.update();
      _api.getScannerNumber(pn);
      scannerCount = pn.value;
      scannerId = null;
      if (scannerCount > 0) {
        final ph = _alloc<Pointer<Void>>(sizeOf<Pointer<Void>>());
        final buf = _alloc<Uint8>(128);
        try {
          if (_api.getScannerHandle(0, ph) == ufsOk) {
            _api.getScannerId(ph.value, buf);
            scannerId = _cString(buf, 128);
          }
        } finally {
          _free(ph);
          _free(buf);
        }
      }
    } catch (e) {
      scannerCount = 0;
    } finally {
      _free(pn);
    }
  }

  /// Kaptire yon anprent. Bloke jiskaske yon dwèt poze oswa timeout.
  /// Egzekite nan yon isolate separe pou sèvè HTTP a pa bloke.
  @override
  Future<SupremaCapture> capture({int timeoutMs = 10000, int minQuality = 50, int tplType = templateTypeIso19794_2}) async {
    final dirCopy = dir;
    final result = await Isolate.run(() => _captureWorker(dirCopy, timeoutMs, tplType));
    if (result['ok'] != true) {
      throw SupremaException(result['code'] as String, result['message'] as String);
    }
    final quality = result['quality'] as int;
    if (quality < minQuality) {
      throw SupremaException('low_quality', 'Qualité insuffisante ($quality%). Reposez le doigt bien à plat.');
    }
    return SupremaCapture(templateB64: result['template'] as String, quality: quality);
  }

  @override
  Future<bool> verify(String aB64, String bB64) async => _verifySync(aB64, bB64);

  /// Verifikasyon 1:1 pa algorit Suprema a.
  bool _verifySync(String aB64, String bB64) {
    final a = base64Decode(aB64.trim());
    final b = base64Decode(bB64.trim());
    if (a.isEmpty || b.isEmpty) return false;
    final pa = _bytesToNative(a);
    final pb = _bytesToNative(b);
    final pr = _alloc<Int32>(4);
    try {
      final rc = _api.ufmVerify(_matcher, pa, a.length, pb, b.length, pr);
      if (rc != ufsOk) return false;
      return pr.value != 0;
    } finally {
      _free(pa);
      _free(pb);
      _free(pr);
    }
  }
}

/// Travay kapti nan isolate. DLL yo deja chaje nan pwosesis la, kidonk
/// `DynamicLibrary.open` retounen menm modil la epi eta UFS_Init pataje.
Map<String, Object> _captureWorker(String dir, int timeoutMs, int tplType) {
  final api = _Api(dir);
  final ph = _alloc<Pointer<Void>>(sizeOf<Pointer<Void>>());
  final pTimeout = _alloc<Int32>(4);
  final tpl = _alloc<Uint8>(maxTemplateSize);
  final pSize = _alloc<Int32>(4);
  final pQuality = _alloc<Int32>(4);
  try {
    var rc = api.getScannerHandle(0, ph);
    if (rc != ufsOk) {
      return {'ok': false, 'code': 'no_reader', 'message': 'Lecteur non détecté (${api.describe(rc)}).'};
    }
    final h = ph.value;
    pTimeout.value = timeoutMs;
    api.setParameter(h, ufsParamTimeout, pTimeout.cast<Void>());
    api.setTemplateType?.call(h, tplType);
    api.clearBuffer(h);

    rc = api.captureSingle(h);
    if (rc != ufsOk) {
      return {'ok': false, 'code': 'capture_failed', 'message': 'Aucun doigt détecté ou capture échouée: ${api.describe(rc)}'};
    }

    if (api.extractEx != null) {
      rc = api.extractEx!(h, maxTemplateSize, tpl, pSize, pQuality);
    } else if (api.extract != null) {
      rc = api.extract!(h, tpl, pSize, pQuality);
    } else {
      return {'ok': false, 'code': 'sdk_incompatible', 'message': 'UFS_Extract introuvable dans UFScanner.dll.'};
    }
    if (rc != ufsOk || pSize.value <= 0) {
      return {'ok': false, 'code': 'extract_failed', 'message': 'Extraction impossible: ${api.describe(rc)}'};
    }
    final bytes = Uint8List.fromList(tpl.asTypedList(pSize.value));
    return {'ok': true, 'template': base64Encode(bytes), 'quality': pQuality.value};
  } catch (e) {
    return {'ok': false, 'code': 'sdk_error', 'message': '$e'};
  } finally {
    _free(ph);
    _free(pTimeout);
    _free(tpl);
    _free(pSize);
    _free(pQuality);
  }
}
