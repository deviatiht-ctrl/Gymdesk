import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'scan_page.dart';

/// Mode kiosque : le scanner occupe tout l'écran, le retour arrière et
/// la navigation sont bloqués. Le déverrouillage (email + mot de passe
/// owner/supervisor) est géré dans ScanPage via AppRuntime.unlockKiosk.
class KioskPage extends ConsumerStatefulWidget {
  const KioskPage({super.key});
  @override
  ConsumerState<KioskPage> createState() => _KioskPageState();
}

class _KioskPageState extends ConsumerState<KioskPage> {
  @override
  void initState() {
    super.initState();
    ref.read(appRuntimeProvider).setKioskNativeLock(true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: const Scaffold(body: SafeArea(child: ScanPage())),
  );
}
