import 'package:flutter/services.dart';

/// Pont natif pour le mode kiosque (épinglage d'écran Android lock-task,
/// no-op silencieux sur les autres plateformes).
class KioskNative {
  static const _channel = MethodChannel('gymdesk/kiosk');

  static Future<void> setLockTask(bool locked) async {
    try {
      await _channel.invokeMethod(locked ? 'startLockTask' : 'stopLockTask');
    } catch (_) {}
  }
}
