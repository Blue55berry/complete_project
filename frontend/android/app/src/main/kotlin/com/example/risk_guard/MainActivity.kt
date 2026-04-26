package com.example.risk_guard

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import android.accessibilityservice.AccessibilityServiceInfo
import android.media.projection.MediaProjectionManager
import android.view.accessibility.AccessibilityManager
import androidx.annotation.NonNull
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.example.risk_guard/native"
    private var methodChannel: MethodChannel? = null
    private var pendingMediaProjectionResult: MethodChannel.Result? = null
    private val mediaProjectionLauncher: ActivityResultLauncher<Intent> =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val pendingResult = pendingMediaProjectionResult
            pendingMediaProjectionResult = null
            if (pendingResult == null) {
                return@registerForActivityResult
            }

            if (result.resultCode == RESULT_OK && result.data != null) {
                try {
                    val serviceIntent = Intent(
                        this,
                        com.example.risk_guard.services.RiskGuardMediaProjectionService::class.java,
                    ).apply {
                        action =
                            com.example.risk_guard.services.RiskGuardMediaProjectionService.ACTION_START_CAPTURE_SESSION
                        putExtra(
                            com.example.risk_guard.services.RiskGuardMediaProjectionService.EXTRA_RESULT_CODE,
                            result.resultCode,
                        )
                        putExtra(
                            com.example.risk_guard.services.RiskGuardMediaProjectionService.EXTRA_PROJECTION_DATA,
                            result.data,
                        )
                    }
                    ContextCompat.startForegroundService(this, serviceIntent)
                    pendingResult.success(true)
                } catch (e: Exception) {
                    pendingResult.error("MEDIA_PROJECTION_ERROR", e.message, null)
                }
            } else {
                pendingResult.success(false)
            }
        }

    private val callDetectionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ProtectionEventStore.ACTION_CALL_DETECTED) {
                val state = intent.getStringExtra("state")
                val phoneNumber = intent.getStringExtra("phoneNumber")
                methodChannel?.invokeMethod("onCallDetected", mapOf(
                    "state" to state,
                    "phoneNumber" to phoneNumber
                ))
            }
        }
    }

    private val urlDetectionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ProtectionEventStore.ACTION_URL_DETECTED) {
                val url = intent.getStringExtra("url")
                val packageName = intent.getStringExtra("packageName")
                if (url != null) {
                    methodChannel?.invokeMethod("onUrlDetected", mapOf(
                        "url" to url,
                        "packageName" to packageName
                    ))
                }
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // Register broadcast receivers here so they persist across the Activity lifecycle
        val urlFilter = IntentFilter(ProtectionEventStore.ACTION_URL_DETECTED)
        val callFilter = IntentFilter(ProtectionEventStore.ACTION_CALL_DETECTED)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(urlDetectionReceiver, urlFilter, Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(callDetectionReceiver, callFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(urlDetectionReceiver, urlFilter)
            registerReceiver(callDetectionReceiver, callFilter)
        }

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppIcon" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val icon = getAppIcon(packageName)
                        if (icon != null) {
                            result.success(icon)
                        } else {
                            result.error("UNAVAILABLE", "Icon not available", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is null", null)
                    }
                }
                "isOverlayPermissionGranted" -> {
                    result.success(isOverlayPermissionGranted())
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                "isAccessibilityPermissionGranted" -> {
                    result.success(isAccessibilityPermissionGranted())
                }
                "requestAccessibilityPermission" -> {
                    requestAccessibilityPermission()
                    result.success(null)
                }
                "getInstalledApps" -> {
                    result.success(getInstalledApps())
                }
                "sendMessageToOverlay" -> {
                    @Suppress("UNCHECKED_CAST")
                    val data = call.arguments as? Map<String, Any?>
                    if (data != null) {
                        try {
                            ProtectionEventStore.storeOverlayPayload(this@MainActivity, data)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OVERLAY_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Data is null", null)
                    }
                }
                "syncSecuritySettings" -> {
                    val isProtectionActive = call.argument<Boolean>("isProtectionActive") ?: false
                    val whitelistedPackages = call.argument<List<String>>("whitelistedPackages") ?: emptyList()
                    val voiceDetectionEnabled =
                        call.argument<Boolean>("voiceDetectionEnabled") ?: true
                    val imageDetectionEnabled =
                        call.argument<Boolean>("imageDetectionEnabled") ?: true
                    val textDetectionEnabled =
                        call.argument<Boolean>("textDetectionEnabled") ?: true
                    val videoDetectionEnabled =
                        call.argument<Boolean>("videoDetectionEnabled") ?: true
                    val blockchainEnabled =
                        call.argument<Boolean>("blockchainEnabled") ?: true
                    val callMonitoringEnabled =
                        call.argument<Boolean>("callMonitoringEnabled") ?: true
                    ProtectionEventStore.syncSecuritySettings(
                        context = this@MainActivity,
                        isProtectionActive = isProtectionActive,
                        whitelistedPackages = whitelistedPackages,
                        voiceDetectionEnabled = voiceDetectionEnabled,
                        imageDetectionEnabled = imageDetectionEnabled,
                        textDetectionEnabled = textDetectionEnabled,
                        videoDetectionEnabled = videoDetectionEnabled,
                        blockchainEnabled = blockchainEnabled,
                        callMonitoringEnabled = callMonitoringEnabled,
                    )
                    result.success(true)
                }
                "clearNativeProtectionState" -> {
                    try {
                        ProtectionEventStore.clearAll(this@MainActivity)
                        val serviceIntent = Intent(
                            this@MainActivity,
                            com.example.risk_guard.services.RiskGuardForegroundService::class.java,
                        ).apply {
                            action = "STOP_SERVICE"
                        }
                        startService(serviceIntent)
                        startService(
                            Intent(
                                this@MainActivity,
                                com.example.risk_guard.services.RiskGuardMediaProjectionService::class.java,
                            ).apply {
                                action =
                                    com.example.risk_guard.services.RiskGuardMediaProjectionService.ACTION_STOP_CAPTURE_SESSION
                            },
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLEAR_STATE_ERROR", e.message, null)
                    }
                }
                "startForegroundService" -> {
                    try {
                        val serviceIntent = Intent(this@MainActivity, 
                            com.example.risk_guard.services.RiskGuardForegroundService::class.java)
                        ContextCompat.startForegroundService(this@MainActivity, serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "isForegroundServiceRunning" -> {
                    result.success(ProtectionEventStore.isForegroundServiceRunning(this@MainActivity))
                }
                "stopForegroundService" -> {
                    try {
                        val serviceIntent = Intent(this@MainActivity,
                            com.example.risk_guard.services.RiskGuardForegroundService::class.java)
                        serviceIntent.action = "STOP_SERVICE"
                        startService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "requestMediaProjectionPermission" -> {
                    if (pendingMediaProjectionResult != null) {
                        result.error(
                            "MEDIA_PROJECTION_BUSY",
                            "Another screen-capture request is already pending.",
                            null,
                        )
                    } else {
                        requestMediaProjectionPermission(result)
                    }
                }
                "isMediaProjectionActive" -> {
                    result.success(ProtectionEventStore.isMediaProjectionRunning(this@MainActivity))
                }
                "requestRealtimeMediaCapture" -> {
                    val sourcePackage = call.argument<String>("sourcePackage")
                    val reason = call.argument<String>("reason") ?: "manual"
                    val sessionId = call.argument<String>("sessionId")
                    val captureStage = call.argument<String>("captureStage") ?: "first_pass"
                    if (sourcePackage.isNullOrBlank() ||
                        !ProtectionEventStore.isMediaProjectionRunning(this@MainActivity)
                    ) {
                        result.success(false)
                    } else {
                        try {
                            val serviceIntent = Intent(
                                this@MainActivity,
                                com.example.risk_guard.services.RiskGuardMediaProjectionService::class.java,
                            ).apply {
                                action =
                                    com.example.risk_guard.services.RiskGuardMediaProjectionService.ACTION_CAPTURE_FRAME
                                putExtra(
                                    com.example.risk_guard.services.RiskGuardMediaProjectionService.EXTRA_SOURCE_PACKAGE,
                                    sourcePackage,
                                )
                                putExtra(
                                    com.example.risk_guard.services.RiskGuardMediaProjectionService.EXTRA_REASON,
                                    reason,
                                )
                                putExtra(
                                    com.example.risk_guard.services.RiskGuardMediaProjectionService.EXTRA_SESSION_ID,
                                    sessionId,
                                )
                                putExtra(
                                    com.example.risk_guard.services.RiskGuardMediaProjectionService.EXTRA_CAPTURE_STAGE,
                                    captureStage,
                                )
                            }
                            startService(serviceIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("MEDIA_CAPTURE_ERROR", e.message, null)
                        }
                    }
                }
                "stopMediaProjectionService" -> {
                    try {
                        val serviceIntent = Intent(
                            this@MainActivity,
                            com.example.risk_guard.services.RiskGuardMediaProjectionService::class.java,
                        ).apply {
                            action =
                                com.example.risk_guard.services.RiskGuardMediaProjectionService.ACTION_STOP_CAPTURE_SESSION
                        }
                        startService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MEDIA_PROJECTION_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        val apps = mutableListOf<Map<String, Any>>()
        val pm = packageManager
        val packages = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        for (appInfo in packages) {
            if (pm.getLaunchIntentForPackage(appInfo.packageName) != null) {
                val appMap = mutableMapOf<String, Any>()
                appMap["name"] = appInfo.loadLabel(pm).toString()
                appMap["packageName"] = appInfo.packageName
                // We fetch icons separately via getAppIcon to avoid large data transfer in one go
                apps.add(appMap)
            }
        }
        return apps
    }

    private fun getAppIcon(packageName: String): ByteArray? {
        try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = drawableToBitmap(drawable)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            return stream.toByteArray()
        } catch (e: PackageManager.NameNotFoundException) {
            return null
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable) {
            return drawable.bitmap
        }
        val bitmap = Bitmap.createBitmap(drawable.intrinsicWidth, drawable.intrinsicHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    private fun isOverlayPermissionGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
            startActivity(intent)
        }
    }

    private fun isAccessibilityPermissionGranted(): Boolean {
        // Method 1: Check via Settings.Secure (standard Android)
        val service = "$packageName/${com.example.risk_guard.services.RiskGuardAccessibilityService::class.java.canonicalName}"
        val enabled = Settings.Secure.getInt(contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 0)
        if (enabled == 1) {
            val settingValue = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            if (settingValue != null) {
                val splitter = TextUtils.SimpleStringSplitter(':')
                splitter.setString(settingValue)
                while (splitter.hasNext()) {
                    if (splitter.next().equals(service, ignoreCase = true)) {
                        return true
                    }
                }
            }
        }

        // Method 2: Fallback for OEMs (Realme, Oppo, etc.) using AccessibilityManager
        try {
            val am = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
            val enabledServices = am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            for (info in enabledServices) {
                if (info.resolveInfo.serviceInfo.packageName == packageName) {
                    return true
                }
            }
        } catch (_: Exception) {}

        return false
    }

    private fun requestAccessibilityPermission() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
        startActivity(intent)
    }

    private fun requestMediaProjectionPermission(result: MethodChannel.Result) {
        val manager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
        if (manager == null) {
            result.error(
                "MEDIA_PROJECTION_UNAVAILABLE",
                "MediaProjectionManager is unavailable.",
                null,
            )
            return
        }

        pendingMediaProjectionResult = result
        try {
            mediaProjectionLauncher.launch(manager.createScreenCaptureIntent())
        } catch (e: Exception) {
            pendingMediaProjectionResult = null
            result.error("MEDIA_PROJECTION_ERROR", e.message, null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(urlDetectionReceiver)
            unregisterReceiver(callDetectionReceiver)
        } catch (_: Exception) {}
    }
}
