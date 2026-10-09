package com.example.gym_desk

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class BiometricPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "GymDeskBiometrics"
        private const val METHOD_CHANNEL = "gymdesk/biometrics"
        private const val EVENT_CHANNEL = "gymdesk/biometrics_events"
        private const val ACTION_USB_PERMISSION = "com.example.gym_desk.USB_PERMISSION"

        // DigitalPersona 4500 VID / PID
        const val DP_VENDOR_ID = 1466 // 0x05BA
        val DP_PRODUCT_IDS = intArrayOf(10, 8, 12) // 4500, 4000, 4500B
    }

    private var context: Context? = null
    private var activity: Activity? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private var usbManager: UsbManager? = null
    private var isCapturing = false
    private val mainHandler = Handler(Looper.getMainLooper())

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            when (action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    val device: UsbDevice? = getDeviceExtra(intent)
                    if (device != null && isDigitalPersonaDevice(device)) {
                        Log.d(TAG, "DigitalPersona device attached: ${device.deviceName}")
                        checkAndRequestPermission(device)
                        sendEvent("device_connected", mapOf(
                            "name" to device.deviceName,
                            "vendorId" to device.vendorId,
                            "productId" to device.productId
                        ))
                    }
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val device: UsbDevice? = getDeviceExtra(intent)
                    if (device != null && isDigitalPersonaDevice(device)) {
                        Log.d(TAG, "DigitalPersona device detached")
                        stopCapture()
                        sendEvent("device_disconnected", emptyMap<String, Any>())
                    }
                }
                ACTION_USB_PERMISSION -> {
                    synchronized(this) {
                        val device: UsbDevice? = getDeviceExtra(intent)
                        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                        if (granted && device != null) {
                            Log.d(TAG, "USB Permission granted for device: ${device.deviceName}")
                            sendEvent("permission_granted", mapOf("deviceName" to device.deviceName))
                        } else {
                            Log.w(TAG, "USB Permission denied")
                            sendEvent("permission_denied", emptyMap<String, Any>())
                        }
                    }
                }
            }
        }
    }

    private fun getDeviceExtra(intent: Intent): UsbDevice? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        usbManager = context?.getSystemService(Context.USB_SERVICE) as? UsbManager

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel?.setStreamHandler(this)

        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(ACTION_USB_PERMISSION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context?.registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context?.registerReceiver(usbReceiver, filter)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        try {
            context?.unregisterReceiver(usbReceiver)
        } catch (_: Exception) {}

        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSensorConnected" -> {
                result.success(findDigitalPersonaDevice() != null)
            }
            "requestUsbPermission" -> {
                val device = findDigitalPersonaDevice()
                if (device == null) {
                    result.error("no_device", "HID DigitalPersona reader not found", null)
                } else {
                    checkAndRequestPermission(device)
                    result.success(true)
                }
            }
            "startCapture" -> {
                val device = findDigitalPersonaDevice()
                if (device == null) {
                    result.error("device_not_connected", "Lektè biometrik la pa konekte sou USB", null)
                } else {
                    startCapture()
                    result.success(true)
                }
            }
            "stopCapture" -> {
                stopCapture()
                result.success(true)
            }
            "matchTemplates" -> {
                val candidate = call.argument<String>("candidate") ?: ""
                val enrolled = call.argument<String>("enrolled") ?: ""
                val score = computeTemplateMatchScore(candidate, enrolled)
                val isMatch = score >= 0.70 // 70% threshold
                result.success(mapOf("match" to isMatch, "score" to score))
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val connected = findDigitalPersonaDevice() != null
        if (connected) {
            sendEvent("device_connected", mapOf("name" to "DigitalPersona U.are.U 4500"))
        } else {
            sendEvent("device_disconnected", emptyMap<String, Any>())
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        stopCapture()
    }

    private fun isDigitalPersonaDevice(device: UsbDevice): Boolean {
        if (device.vendorId == DP_VENDOR_ID) {
            for (pid in DP_PRODUCT_IDS) {
                if (device.productId == pid) return true
            }
        }
        return false
    }

    private fun findDigitalPersonaDevice(): UsbDevice? {
        val manager = usbManager ?: return null
        for (device in manager.deviceList.values) {
            if (isDigitalPersonaDevice(device)) return device
        }
        return null
    }

    private fun checkAndRequestPermission(device: UsbDevice) {
        val manager = usbManager ?: return
        val ctx = context ?: return
        if (!manager.hasPermission(device)) {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            val permissionIntent = PendingIntent.getBroadcast(ctx, 0, Intent(ACTION_USB_PERMISSION), flags)
            manager.requestPermission(device, permissionIntent)
        }
    }

    private fun startCapture() {
        if (isCapturing) return
        isCapturing = true
        sendEvent("waiting_finger", emptyMap<String, Any>())
    }

    private fun stopCapture() {
        isCapturing = false
    }

    private fun sendEvent(event: String, data: Map<String, Any>) {
        mainHandler.post {
            val map = HashMap<String, Any>(data)
            map["event"] = event
            eventSink?.success(map)
        }
    }

    /**
     * Konparezon de tèmplat ISO / Minutiae nan nivo nimerik
     * Retounen yon nòt ant 0.0 ak 1.0
     */
    private fun computeTemplateMatchScore(candidateB64: String, enrolledB64: String): Double {
        if (candidateB64.isEmpty() || enrolledB64.isEmpty()) return 0.0
        if (candidateB64 == enrolledB64) return 1.0

        try {
            val candBytes = Base64.decode(candidateB64, Base64.DEFAULT)
            val enrBytes = Base64.decode(enrolledB64, Base64.DEFAULT)

            if (candBytes.isEmpty() || enrBytes.isEmpty()) return 0.0

            val minLen = minOf(candBytes.size, enrBytes.size)
            var matches = 0
            for (i in 0 until minLen) {
                if (abs(candBytes[i].toInt() - enrBytes[i].toInt()) <= 4) {
                    matches++
                }
            }
            return matches.toDouble() / maxOf(candBytes.size, enrBytes.size).toDouble()
        } catch (_: Exception) {
            return 0.0
        }
    }
}
