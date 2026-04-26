package com.example.risk_guard

import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

object ProtectionEventStore {
    private const val NATIVE_PREFS = "RiskGuardPrefs"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"

    private const val KEY_PROTECTION_ACTIVE = "protection_active"
    private const val KEY_WHITELISTED_PACKAGES = "whitelisted_packages"
    private const val KEY_FOREGROUND_SERVICE_RUNNING = "foreground_service_running"
    private const val KEY_MEDIA_PROJECTION_RUNNING = "media_projection_running"
    private const val KEY_VOICE_DETECTION_ENABLED = "voice_detection_enabled"
    private const val KEY_IMAGE_DETECTION_ENABLED = "image_detection_enabled"
    private const val KEY_TEXT_DETECTION_ENABLED = "text_detection_enabled"
    private const val KEY_VIDEO_DETECTION_ENABLED = "video_detection_enabled"
    private const val KEY_BLOCKCHAIN_ENABLED = "blockchain_enabled"
    private const val KEY_CALL_MONITORING_ENABLED = "call_monitoring_enabled"

    private const val KEY_URL = "flutter.latest_proactive_url"
    private const val KEY_URL_PACKAGE = "flutter.latest_proactive_pkg"
    private const val KEY_URL_TIME = "flutter.latest_proactive_time"

    private const val KEY_CALL_STATE = "flutter.latest_call_state"
    private const val KEY_CALL_NUMBER = "flutter.latest_call_number"
    private const val KEY_CALL_TIME = "flutter.latest_call_time"

    private const val KEY_TRIGGER_OVERLAY = "flutter.trigger_overlay"
    private const val KEY_OVERLAY_PAYLOAD = "flutter.latest_overlay_payload"
    private const val KEY_OVERLAY_PAYLOAD_TIME = "flutter.latest_overlay_payload_time"
    private const val KEY_EVENT_QUEUE = "flutter.protection_event_queue"
    private const val KEY_EVENT_QUEUE_UPDATED_AT = "flutter.protection_event_queue_updated_at"
    private const val MAX_PENDING_EVENTS = 24
    private const val URL_DEDUPE_WINDOW_MS = 6000L
    private const val URL_EVENT_TTL_MS = 8000L
    private const val CALL_EVENT_TTL_MS = 30000L
    private const val OVERLAY_EVENT_TTL_MS = 5000L
    private const val MEDIA_EVENT_TTL_MS = 12000L
    private const val MEDIA_DEDUPE_WINDOW_MS = 1500L

    const val ACTION_URL_DETECTED = "com.example.risk_guard.URL_DETECTED"
    const val ACTION_CALL_DETECTED = "com.example.risk_guard.CALL_DETECTED"

    fun syncSecuritySettings(
        context: Context,
        isProtectionActive: Boolean,
        whitelistedPackages: List<String>,
        voiceDetectionEnabled: Boolean,
        imageDetectionEnabled: Boolean,
        textDetectionEnabled: Boolean,
        videoDetectionEnabled: Boolean,
        blockchainEnabled: Boolean,
        callMonitoringEnabled: Boolean,
    ) {
        context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PROTECTION_ACTIVE, isProtectionActive)
            .putStringSet(KEY_WHITELISTED_PACKAGES, whitelistedPackages.toSet())
            .putBoolean(KEY_VOICE_DETECTION_ENABLED, voiceDetectionEnabled)
            .putBoolean(KEY_IMAGE_DETECTION_ENABLED, imageDetectionEnabled)
            .putBoolean(KEY_TEXT_DETECTION_ENABLED, textDetectionEnabled)
            .putBoolean(KEY_VIDEO_DETECTION_ENABLED, videoDetectionEnabled)
            .putBoolean(KEY_BLOCKCHAIN_ENABLED, blockchainEnabled)
            .putBoolean(KEY_CALL_MONITORING_ENABLED, callMonitoringEnabled)
            .apply()
    }

    fun isProtectionActive(context: Context): Boolean {
        return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_PROTECTION_ACTIVE, false)
    }

    fun whitelistedPackages(context: Context): Set<String> {
        return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .getStringSet(KEY_WHITELISTED_PACKAGES, emptySet())
            ?: emptySet()
    }

    fun isVoiceDetectionEnabled(context: Context): Boolean {
        return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_VOICE_DETECTION_ENABLED, true)
    }

    fun isImageDetectionEnabled(context: Context): Boolean {
        return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_IMAGE_DETECTION_ENABLED, true)
    }

    fun isTextDetectionEnabled(context: Context): Boolean {
        return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_TEXT_DETECTION_ENABLED, true)
    }

    fun isVideoDetectionEnabled(context: Context): Boolean {
        return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_VIDEO_DETECTION_ENABLED, true)
    }

    fun isBlockchainEnabled(context: Context): Boolean {
        return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_BLOCKCHAIN_ENABLED, true)
    }

    fun isCallMonitoringEnabled(context: Context): Boolean {
        return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_CALL_MONITORING_ENABLED, true)
    }

    fun canCaptureVisibleMedia(context: Context): Boolean {
        return isProtectionActive(context) &&
            (isImageDetectionEnabled(context) || isVideoDetectionEnabled(context))
    }

    fun setForegroundServiceRunning(context: Context, isRunning: Boolean) {
        context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_FOREGROUND_SERVICE_RUNNING, isRunning)
            .apply()
    }

    fun isForegroundServiceRunning(context: Context): Boolean {
        return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_FOREGROUND_SERVICE_RUNNING, false)
    }

    fun setMediaProjectionRunning(context: Context, isRunning: Boolean) {
        context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_MEDIA_PROJECTION_RUNNING, isRunning)
            .apply()
    }

    fun isMediaProjectionRunning(context: Context): Boolean {
        return context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_MEDIA_PROJECTION_RUNNING, false)
    }

    fun storeUrlEvent(context: Context, url: String, packageName: String) {
        val now = System.currentTimeMillis()
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_URL, url)
            .putString(KEY_URL_PACKAGE, packageName)
            .putLong(KEY_URL_TIME, now)
            .putString(KEY_TRIGGER_OVERLAY, "true")
            .apply()

        enqueueEvent(
            context = context,
            event = JSONObject().apply {
                put("id", "url-$now-${url.hashCode()}")
                put("kind", "url_capture")
                put("targetType", "url")
                put("normalizedTarget", url)
                put("sourcePackage", packageName)
                put("createdAtMs", now)
                put("expiresAtMs", now + URL_EVENT_TTL_MS)
                put("priority", 50)
                put("sessionId", "url-$now")
                put("status", "pending")
            },
        )
    }

    fun storeCallEvent(context: Context, state: String, phoneNumber: String?) {
        if (!isCallMonitoringEnabled(context) || !isProtectionActive(context)) {
            return
        }
        val now = System.currentTimeMillis()
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_CALL_STATE, state)
            .putString(KEY_CALL_NUMBER, phoneNumber)
            .putLong(KEY_CALL_TIME, now)
            .putString(KEY_TRIGGER_OVERLAY, "true")
            .apply()

        enqueueEvent(
            context = context,
            event = JSONObject().apply {
                put("id", "call-$now-$state")
                put("kind", "call_state")
                put("targetType", "phone_call")
                put("normalizedTarget", state)
                put("sourcePackage", "phone_service")
                put("createdAtMs", now)
                put("expiresAtMs", now + CALL_EVENT_TTL_MS)
                put("priority", 100)
                put("sessionId", "call-$now")
                put("status", "pending")
                put("callState", state)
                if (phoneNumber != null) {
                    put("phoneNumber", phoneNumber)
                } else {
                    put("phoneNumber", JSONObject.NULL)
                }
            },
        )
    }

    fun storeOverlayPayload(context: Context, payload: Map<String, Any?>) {
        val now = System.currentTimeMillis()
        val jsonObject = JSONObject()
        payload.forEach { (key, value) ->
            jsonObject.put(key, value ?: JSONObject.NULL)
        }
        val jsonPayload = jsonObject.toString()
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_OVERLAY_PAYLOAD, jsonPayload)
            .putLong(KEY_OVERLAY_PAYLOAD_TIME, now)
            .putString(KEY_TRIGGER_OVERLAY, "true")
            .apply()

        enqueueEvent(
            context = context,
            event = JSONObject().apply {
                put("id", "overlay-$now-${payload.hashCode()}")
                put("kind", "overlay_status")
                put("targetType", payload["targetType"] ?: "overlay")
                put("normalizedTarget", payload["url"] ?: payload["status"] ?: "overlay")
                put("sourcePackage", payload["source"] ?: payload["sourcePackage"] ?: JSONObject.NULL)
                put("createdAtMs", now)
                put("expiresAtMs", now + OVERLAY_EVENT_TTL_MS)
                put("priority", if (payload["isCallActive"] == true) 90 else 20)
                put("sessionId", "overlay-$now")
                put("status", payload["status"] ?: "pending")
                put("payload", jsonObject)
            },
        )
    }

    fun storeMediaCaptureEvent(
        context: Context,
        previewPath: String,
        analysisPath: String,
        sourcePackage: String,
        targetType: String = "screen_frame",
        targetLabel: String = "Live screen frame",
        mediaKind: String = "screen_fallback",
        selectionConfidence: Double = 0.0,
        cropBounds: String? = null,
        reason: String = "capture",
        sessionId: String = "media",
        captureStage: String = "first_pass",
    ) {
        val now = System.currentTimeMillis()
        val payload = JSONObject().apply {
            put("sessionKind", "media")
            put("sourcePackage", sourcePackage)
            put("targetType", targetType)
            put("targetLabel", targetLabel)
            put("status", if (captureStage == "first_pass") "CAPTURED FRAME" else "BURST FRAME READY")
            put("analysisSource", "screen_capture")
            put(
                "summary",
                if (captureStage == "first_pass") {
                    "Captured the dominant visible media for live deepfake verification."
                } else {
                    "Captured an additional burst frame to strengthen the live media verdict."
                },
            )
            put("recommendation", "Keep the current media visible while RiskGuard verifies it.")
            put("previewPath", previewPath)
            put("analysisPath", analysisPath)
            put("localFramePath", analysisPath)
            put("captureReason", reason)
            put("mediaKind", mediaKind)
            put("selectionConfidence", selectionConfidence)
            put("captureStage", captureStage)
            if (cropBounds != null) {
                put("cropBounds", cropBounds)
            } else {
                put("cropBounds", JSONObject.NULL)
            }
        }

        enqueueEvent(
            context = context,
            event = JSONObject().apply {
                put("id", "media-$now-${sourcePackage.hashCode()}-$captureStage")
                put("kind", "media_result")
                put("targetType", targetType)
                put("normalizedTarget", "$sourcePackage:$targetType:$sessionId:$captureStage")
                put("sourcePackage", sourcePackage)
                put("createdAtMs", now)
                put("expiresAtMs", now + MEDIA_EVENT_TTL_MS)
                put("priority", 40)
                put("sessionId", sessionId)
                put("status", captureStage)
                put("payload", payload)
            },
        )
    }

    fun storeOverlayVisibility(
        context: Context,
        isVisible: Boolean,
        packageName: String?,
        reason: String = "window_context",
    ) {
        val now = System.currentTimeMillis()
        enqueueEvent(
            context = context,
            event = JSONObject().apply {
                put("id", "visibility-$now-${packageName ?: "none"}")
                put("kind", "overlay_status")
                put("targetType", "visibility")
                put("normalizedTarget", if (isVisible) "visible" else "hidden")
                put("sourcePackage", packageName ?: JSONObject.NULL)
                put("createdAtMs", now)
                put("expiresAtMs", now + OVERLAY_EVENT_TTL_MS)
                put("priority", 10)
                put("sessionId", "visibility-$now")
                put("status", if (isVisible) "visible" else "hidden")
                put(
                    "payload",
                    JSONObject().apply {
                        put("type", "visibility")
                        put("visible", isVisible)
                        put("packageName", packageName ?: JSONObject.NULL)
                        put("reason", reason)
                    },
                )
            },
        )
    }

    fun broadcastUrl(context: Context, url: String, packageName: String) {
        val intent = Intent(ACTION_URL_DETECTED).apply {
            putExtra("url", url)
            putExtra("packageName", packageName)
        }
        context.sendBroadcast(intent)
    }

    fun broadcastCall(context: Context, state: String, phoneNumber: String?) {
        val intent = Intent(ACTION_CALL_DETECTED).apply {
            putExtra("state", state)
            putExtra("phoneNumber", phoneNumber)
        }
        context.sendBroadcast(intent)
    }

    fun clearAll(context: Context) {
        context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()

        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_URL)
            .remove(KEY_URL_PACKAGE)
            .remove(KEY_URL_TIME)
            .remove(KEY_CALL_STATE)
            .remove(KEY_CALL_NUMBER)
            .remove(KEY_CALL_TIME)
            .remove(KEY_TRIGGER_OVERLAY)
            .remove(KEY_OVERLAY_PAYLOAD)
            .remove(KEY_OVERLAY_PAYLOAD_TIME)
            .remove(KEY_EVENT_QUEUE)
            .remove(KEY_EVENT_QUEUE_UPDATED_AT)
            .apply()
    }

    private fun enqueueEvent(context: Context, event: JSONObject) {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val queue = readQueue(prefs)
        val now = System.currentTimeMillis()

        pruneQueue(queue, now)
        if (shouldSkipDuplicate(queue, event, now)) {
            persistQueue(prefs, queue)
            return
        }

        queue.add(event)
        while (queue.size > MAX_PENDING_EVENTS) {
            queue.removeAt(0)
        }
        persistQueue(prefs, queue)
    }

    private fun shouldSkipDuplicate(
        queue: MutableList<JSONObject>,
        event: JSONObject,
        now: Long,
    ): Boolean {
        val kind = event.optString("kind")
        val target = event.optString("normalizedTarget")
        val source = event.optString("sourcePackage")
        val createdAt = event.optLong("createdAtMs", now)

        return when (kind) {
            "url_capture" -> queue.any { existing ->
                existing.optString("kind") == kind &&
                    existing.optString("normalizedTarget") == target &&
                    existing.optString("sourcePackage") == source &&
                    createdAt - existing.optLong("createdAtMs", 0L) < URL_DEDUPE_WINDOW_MS
            }
            "overlay_status" -> queue.any { existing ->
                existing.optString("kind") == kind &&
                    existing.optString("normalizedTarget") == target &&
                    existing.optString("sourcePackage") == source &&
                    createdAt - existing.optLong("createdAtMs", 0L) < 1000L
            }
            "media_result" -> queue.any { existing ->
                existing.optString("kind") == kind &&
                    existing.optString("normalizedTarget") == target &&
                    existing.optString("sourcePackage") == source &&
                    createdAt - existing.optLong("createdAtMs", 0L) < MEDIA_DEDUPE_WINDOW_MS
            }
            else -> false
        }
    }

    private fun pruneQueue(queue: MutableList<JSONObject>, now: Long) {
        queue.removeAll { event ->
            val expiresAt = event.optLong("expiresAtMs", 0L)
            expiresAt > 0L && now > expiresAt
        }
    }

    private fun readQueue(
        prefs: android.content.SharedPreferences,
    ): MutableList<JSONObject> {
        val raw = prefs.getString(KEY_EVENT_QUEUE, null) ?: return mutableListOf()
        return try {
            val array = JSONArray(raw)
            MutableList(array.length()) { index -> array.getJSONObject(index) }
        } catch (_: Exception) {
            mutableListOf()
        }
    }

    private fun persistQueue(
        prefs: android.content.SharedPreferences,
        queue: List<JSONObject>,
    ) {
        val array = JSONArray()
        queue.forEach { array.put(it) }
        prefs.edit()
            .putString(KEY_EVENT_QUEUE, array.toString())
            .putLong(KEY_EVENT_QUEUE_UPDATED_AT, System.currentTimeMillis())
            .apply()
    }
}
