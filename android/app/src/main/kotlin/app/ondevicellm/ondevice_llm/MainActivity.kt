package app.ondevicellm.ondevice_llm

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.StatFs
import android.view.Display
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var offlineDictation: OfflineDictation? = null
    private var shareInbox: ShareInbox? = null
    private var scheduledPrompts: ScheduledPrompts? = null
    private var hostDiscovery: HostDiscovery? = null
    private var voiceAudio: VoiceAudio? = null
    // Tags the models this window loads; they are freed when it is destroyed.
    private val nativeOwner = NativeBridge.newOwner()

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        shareInbox?.offer(intent, notify = true)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == OfflineDictation.PERMISSION_REQUEST) {
            offlineDictation?.onPermissionResult(
                grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED)
        }
        if (requestCode == VoiceAudio.PERMISSION_REQUEST) {
            voiceAudio?.onPermissionResult(
                grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED)
        }
        if (requestCode == ScheduledPrompts.PERMISSION_REQUEST) {
            scheduledPrompts?.onPermissionResult(
                grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED)
        }
    }

    override fun onStop() {
        offlineDictation?.cancel()
        // Not seen any more: the conversation's microphone and voice stop
        // (audit C7); the screen listens again when it comes back.
        voiceAudio?.pause()
        super.onStop()
    }

    override fun onDestroy() {
        offlineDictation?.close()
        offlineDictation = null
        hostDiscovery?.close()
        hostDiscovery = null
        voiceAudio?.close()
        voiceAudio = null
        super.onDestroy()
        // The engine and its isolates are gone; the process and its native
        // memory may stay, so the model this window loaded is freed now.
        NativeBridge.release(nativeOwner)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        // Some OEM power modes reset the preference while the app is backgrounded.
        requestHighestRefreshRate()
    }

    /// Samsung (and other) phones keep a Flutter app at 60 Hz unless it asks
    /// for a display mode. Pick the fastest mode at the current resolution
    /// (120 Hz on the S25+); the framework then renders at that cadence.
    private fun requestHighestRefreshRate() {
        val display: Display = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
            else @Suppress("DEPRECATION") windowManager.defaultDisplay) ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        if (best.modeId == current.modeId && best.refreshRate <= current.refreshRate) return
        val attributes = window.attributes
        attributes.preferredDisplayModeId = best.modeId
        window.attributes = attributes
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        offlineDictation?.close()
        offlineDictation = OfflineDictation(this, flutterEngine.dartExecutor.binaryMessenger)
        shareInbox = ShareInbox(this, flutterEngine.dartExecutor.binaryMessenger).also {
            // The share that launched the app waits until Dart asks for it.
            it.offer(intent, notify = false)
        }
        scheduledPrompts = ScheduledPrompts(this, flutterEngine.dartExecutor.binaryMessenger)
        BackgroundDownloads(this, flutterEngine.dartExecutor.binaryMessenger)
        OnDeviceOcr(this, flutterEngine.dartExecutor.binaryMessenger)
        AudioDecode(flutterEngine.dartExecutor.binaryMessenger)
        PhoneActions(this, flutterEngine.dartExecutor.binaryMessenger)
        voiceAudio?.close()
        voiceAudio = VoiceAudio(this, flutterEngine.dartExecutor.binaryMessenger)
        hostDiscovery?.close()
        hostDiscovery = HostDiscovery(this, flutterEngine.dartExecutor.binaryMessenger)
        // Read-only device facts used to size models and defaults. Nothing leaves the device.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ondevice_llm/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "memoryInfo" -> {
                        val info = ActivityManager.MemoryInfo()
                        (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
                        result.success(
                            mapOf(
                                "totalBytes" to info.totalMem,
                                "availableBytes" to info.availMem,
                                "lowMemory" to info.lowMemory,
                            )
                        )
                    }
                    "storageInfo" -> {
                        val storage = StatFs((getExternalFilesDir(null) ?: filesDir).absolutePath)
                        result.success(mapOf(
                            "totalBytes" to storage.totalBytes,
                            "availableBytes" to storage.availableBytes,
                        ))
                    }
                    "refreshRate" -> {
                        val d = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
                            else @Suppress("DEPRECATION") windowManager.defaultDisplay
                        result.success(d?.refreshRate ?: 0f)
                    }
                    // Battery level/charging and the OS thermal status (0 none
                    // … 6 shutdown, -1 unknown) for the device-server page.
                    "powerInfo" -> {
                        val battery = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                        val thermal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                            (getSystemService(Context.POWER_SERVICE) as PowerManager).currentThermalStatus
                            else -1
                        result.success(mapOf(
                            "level" to battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
                            "charging" to battery.isCharging,
                            "thermalStatus" to thermal,
                        ))
                    }
                    // Which window the native runtimes belong to, and which
                    // bridge library Dart opened (NativeBridge frees them).
                    "nativeOwner" -> result.success(nativeOwner)
                    "nativeLibrary" -> {
                        (call.arguments as? String)?.let(NativeBridge::opened)
                        result.success(null)
                    }
                    // While this device serves a model the screen stays on, so
                    // the OS does not suspend the app mid-request.
                    "keepScreenOn" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
