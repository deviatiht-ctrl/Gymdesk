package com.example.gym_desk

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "gymdesk/kiosk"
    private val systemChannel = "gymdesk/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "startLockTask" -> {
                    try {
                        startLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("lock_task_failed", e.message, null)
                    }
                }
                "stopLockTask" -> {
                    try {
                        stopLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("lock_task_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // Ouvre la fiche « Infos sur l'appli » pour que l'utilisateur puisse
        // accorder la caméra de façon permanente (« Autoriser pendant
        // l'utilisation ») après un refus ou une autorisation ponctuelle.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("open_settings_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
