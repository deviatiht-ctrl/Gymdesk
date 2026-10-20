import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<bool>? _pending;

/// Lè SecurGYM.exe lanse dirèkteman (ikòn epengle, raccourci), `Lancer_SecurGYM.bat`
/// pa t kouri: app la lanse `access_agent.exe` li menm si l pa reponn sou 47811.
Future<bool> ensureAccessAgentRunning() => _pending ??= _ensure().whenComplete(() => _pending = null);

Future<bool> _healthy() async {
  try {
    final res = await http
        .get(Uri.parse('http://127.0.0.1:47811/health'))
        .timeout(const Duration(milliseconds: 1500));
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

Future<bool> _ensure() async {
  if (!Platform.isWindows) return false;
  if (await _healthy()) return true;
  final exeDir = File(Platform.resolvedExecutable).parent;
  // Kle USB: GymDesk_USB\access_agent.exe (DLL Suprema, biostar_tool, terminal.json)
  // ak app la nan GymDesk_USB\app\. Enstalasyon: ajan an bò kote exe a.
  final agent = [exeDir.parent, exeDir]
      .map((dir) => File('${dir.path}${Platform.pathSeparator}access_agent.exe'))
      .where((file) => file.existsSync())
      .firstOrNull;
  if (agent == null) return false;
  try {
    await Process.start(
      agent.path,
      const [],
      workingDirectory: agent.parent.path,
      mode: ProcessStartMode.detached,
    );
  } catch (_) {
    return false;
  }
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (await _healthy()) return true;
  }
  return false;
}
