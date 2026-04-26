package com.example.risk_guard.services

import android.accessibilityservice.AccessibilityService
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.content.ContextCompat
import com.example.risk_guard.ProtectionEventStore
import java.util.regex.Pattern

class RiskGuardAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "RiskGuardAccService"
        private const val WINDOW_DEBOUNCE_DELAY = 500L
        private const val PACKAGE_SCAN_DEBOUNCE_MS = 350L
        // Per-package capture debounce strategy:
        //  • Feed apps (Instagram, Facebook, Twitter): 800ms — fast enough
        //    for users swiping through posts without over-capturing
        //  • Chat apps (WhatsApp, Telegram): 2000ms — high debounce prevents
        //    scroll events from triggering excessive captures (anti-flicker)
        //  • All other whitelisted apps: 1600ms (balanced default)
        private const val MEDIA_CAPTURE_DEBOUNCE_FEED_MS = 800L
        private const val MEDIA_CAPTURE_DEBOUNCE_CHAT_MS = 2000L
        private const val MEDIA_CAPTURE_DEBOUNCE_DEFAULT_MS = 1600L
        private const val MAX_SCAN_DEPTH = 10
        private const val MAX_NODES_PER_SCAN = 48
        private const val MAX_TEXT_LENGTH = 600
        private const val CACHE_RETENTION_MS = 300000L

        private val BROWSER_PACKAGES = setOf(
            "com.android.chrome",
            "com.brave.browser",
            "com.microsoft.emmx",
            "com.opera.browser",
            "org.mozilla.firefox",
            "com.sec.android.app.sbrowser",
            "com.android.browser",
        )

        private val EXPLICIT_URL_PATTERN = Pattern.compile(
            "(?i)\\bhttps?://[\\w\\-._~:/?#\\[\\]@!\\$&'()*+,;=%]+",
        )

        private val BARE_DOMAIN_PATTERN = Pattern.compile(
            "(?i)\\b(?:www\\.)?(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,24}(?:/[\\w\\-._~:/?#\\[\\]@!\\$&'()*+,;=%]*)?",
        )

        var instance: RiskGuardAccessibilityService? = null
    }

    private data class ScanContext(
        var remainingNodes: Int = MAX_NODES_PER_SCAN,
        var foundMatch: Boolean = false,
    )

    private var lastPackageName: String? = null
    private var lastEventTime: Long = 0
    private val processedUrls = mutableSetOf<String>()
    private val lastPackageScanTimes = mutableMapOf<String, Long>()
    private val lastMediaCaptureTimes = mutableMapOf<String, Long>()
    private var lastUrlCleanup = System.currentTimeMillis()

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "Service Connected")
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        try {
            if (!ProtectionEventStore.isProtectionActive(applicationContext)) return

            val packageName = event.packageName?.toString() ?: return
            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                handleWindowChanged(packageName)
            }

            if (shouldIgnorePackage(packageName)) return

            val whitelistedPackages =
                ProtectionEventStore.whitelistedPackages(applicationContext)
            if (
                whitelistedPackages.isEmpty() ||
                !whitelistedPackages.contains(packageName)
            ) {
                return
            }

            when (event.eventType) {
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
                AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED,
                AccessibilityEvent.TYPE_VIEW_FOCUSED
                -> {
                    scanEventForUrls(event, packageName)
                    maybeRequestMediaCapture(packageName, event.eventType)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Accessibility scan failed", e)
        }
    }

    private fun handleWindowChanged(packageName: String) {
        val currentTime = System.currentTimeMillis()
        if (packageName == lastPackageName && currentTime - lastEventTime <= WINDOW_DEBOUNCE_DELAY) {
            return
        }

        lastPackageName = packageName
        lastEventTime = currentTime
        updateOverlayVisibility(packageName)
        maybeRequestMediaCapture(
            packageName = packageName,
            eventType = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            bypassDebounce = true,
        )
        Log.d(TAG, "Active package: $packageName")
    }

    private fun shouldIgnorePackage(packageName: String): Boolean {
        return packageName == "com.example.risk_guard" ||
            packageName == "android" ||
            packageName.contains("launcher") ||
            packageName.contains("systemui") ||
            packageName.contains("inputmethod")
    }

    private fun updateOverlayVisibility(packageName: String) {
        val whitelistedPackages =
            ProtectionEventStore.whitelistedPackages(applicationContext)
        val isVisible =
            !shouldIgnorePackage(packageName) &&
                whitelistedPackages.isNotEmpty() &&
                whitelistedPackages.contains(packageName)

        ProtectionEventStore.storeOverlayVisibility(
            context = applicationContext,
            isVisible = isVisible,
            packageName = packageName,
        )
    }

    private fun scanEventForUrls(event: AccessibilityEvent, packageName: String) {
        cleanupProcessedUrls()

        val now = System.currentTimeMillis()
        val lastScan = lastPackageScanTimes[packageName] ?: 0L
        if (
            event.eventType != AccessibilityEvent.TYPE_VIEW_FOCUSED &&
            now - lastScan < PACKAGE_SCAN_DEBOUNCE_MS
        ) {
            return
        }
        lastPackageScanTimes[packageName] = now

        val context = ScanContext()

        event.text?.forEach { candidate ->
            if (inspectTextCandidate(candidate?.toString(), packageName, false)) {
                context.foundMatch = true
                return@forEach
            }
        }
        if (context.foundMatch) return

        if (inspectTextCandidate(event.contentDescription?.toString(), packageName, false)) {
            return
        }

        event.source?.let { source ->
            findUrlsInNode(source, 0, packageName, context)
        }
        if (context.foundMatch) return

        if (!shouldScanRoot(event, packageName)) return
        rootInActiveWindow?.let { root ->
            if (root !== event.source) {
                findUrlsInNode(root, 0, packageName, context)
            }
        }
    }

    private fun shouldScanRoot(event: AccessibilityEvent, packageName: String): Boolean {
        return event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
            isBrowserPackage(packageName)
    }

    private fun cleanupProcessedUrls() {
        val now = System.currentTimeMillis()
        if (now - lastUrlCleanup > CACHE_RETENTION_MS) {
            processedUrls.clear()
            lastPackageScanTimes.clear()
            lastMediaCaptureTimes.clear()
            lastUrlCleanup = now
        }
    }

    private fun maybeRequestMediaCapture(
        packageName: String,
        eventType: Int,
        bypassDebounce: Boolean = false,
    ) {
        if (!ProtectionEventStore.canCaptureVisibleMedia(applicationContext)) return
        if (shouldIgnorePackage(packageName)) return
        val whitelistedPackages = ProtectionEventStore.whitelistedPackages(applicationContext)
        if (whitelistedPackages.isEmpty() || !whitelistedPackages.contains(packageName)) return

        val shouldCapture = when (eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            -> true
            else -> false
        }
        if (!shouldCapture) return

        val now = System.currentTimeMillis()
        val lastCapture = lastMediaCaptureTimes[packageName] ?: 0L
        // Use per-package debounce: feed apps get faster captures,
        // chat apps get slower debounce to kill scroll-triggered flickering.
        val debounce = mediaCaptureDebounceFor(packageName)
        if (!bypassDebounce && now - lastCapture < debounce) {
            return
        }
        if (!ProtectionEventStore.isMediaProjectionRunning(applicationContext)) {
            return
        }
        lastMediaCaptureTimes[packageName] = now

        val intent = android.content.Intent(this, RiskGuardMediaProjectionService::class.java).apply {
            action = RiskGuardMediaProjectionService.ACTION_CAPTURE_FRAME
            putExtra(RiskGuardMediaProjectionService.EXTRA_SOURCE_PACKAGE, packageName)
            putExtra(
                RiskGuardMediaProjectionService.EXTRA_REASON,
                if (eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                    "window_change"
                } else {
                    "content_change"
                },
            )
        }

        try {
            startService(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Media capture request failed for $packageName", e)
        }
    }

    private fun findUrlsInNode(
        node: AccessibilityNodeInfo,
        depth: Int,
        packageName: String,
        context: ScanContext,
    ) {
        if (depth > MAX_SCAN_DEPTH || context.remainingNodes <= 0 || context.foundMatch) {
            return
        }

        context.remainingNodes -= 1
        val isAddressBarContext = looksLikeAddressBar(node)

        if (inspectTextCandidate(node.text?.toString(), packageName, isAddressBarContext)) {
            context.foundMatch = true
            return
        }

        if (inspectTextCandidate(node.contentDescription?.toString(), packageName, isAddressBarContext)) {
            context.foundMatch = true
            return
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            inspectTextCandidate(node.hintText?.toString(), packageName, isAddressBarContext)
        ) {
            context.foundMatch = true
            return
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            inspectTextCandidate(node.paneTitle?.toString(), packageName, isAddressBarContext)
        ) {
            context.foundMatch = true
            return
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            inspectTextCandidate(node.stateDescription?.toString(), packageName, isAddressBarContext)
        ) {
            context.foundMatch = true
            return
        }

        for (i in 0 until node.childCount) {
            if (context.remainingNodes <= 0 || context.foundMatch) return

            val child = node.getChild(i)
            if (child != null) {
                try {
                    findUrlsInNode(child, depth + 1, packageName, context)
                } finally {
                    child.recycle()
                }
            }
        }
    }

    private fun inspectTextCandidate(
        rawText: String?,
        packageName: String,
        isAddressBarContext: Boolean,
    ): Boolean {
        val text = rawText
            ?.replace('\n', ' ')
            ?.trim()
            ?.take(MAX_TEXT_LENGTH)

        if (text.isNullOrEmpty() || !text.contains('.')) {
            return false
        }

        val explicitMatcher = EXPLICIT_URL_PATTERN.matcher(text)
        while (explicitMatcher.find()) {
            val normalizedUrl = normalizeUrl(explicitMatcher.group(), isAddressBarContext) ?: continue
            if (processedUrls.add(normalizedUrl)) {
                Log.d(TAG, "Found explicit URL: $normalizedUrl from $packageName")
                handleDetectedUrl(normalizedUrl, packageName)
                return true
            }
        }

        if (!allowBareDomainScan(text, packageName, isAddressBarContext)) {
            return false
        }

        val matcher = BARE_DOMAIN_PATTERN.matcher(text)
        while (matcher.find()) {
            val candidate = matcher.group() ?: continue
            val normalizedUrl = normalizeUrl(candidate, isAddressBarContext) ?: continue
            if (processedUrls.add(normalizedUrl)) {
                Log.d(TAG, "Found domain URL: $normalizedUrl from $packageName")
                handleDetectedUrl(normalizedUrl, packageName)
                return true
            }
        }

        return false
    }

    private fun allowBareDomainScan(
        text: String,
        packageName: String,
        isAddressBarContext: Boolean,
    ): Boolean {
        if (isAddressBarContext) return true

        val hasPathOrQuery =
            text.contains('/') || text.contains('?') || text.contains('#') || text.contains('=')
        if (hasPathOrQuery) return true

        return text.startsWith("www.", ignoreCase = true) && isBrowserPackage(packageName)
    }

    private fun normalizeUrl(rawUrl: String?, isAddressBarContext: Boolean): String? {
        if (rawUrl.isNullOrBlank()) return null

        val trimmed = rawUrl
            .trim()
            .trimEnd('.', ',', ';', ':', ')', ']', '}', '>')

        if (trimmed.isBlank() || !trimmed.contains('.') || trimmed.contains(" ")) {
            return null
        }

        val lower = trimmed.lowercase()
        if (lower.contains("..")) return null
        if (trimmed.startsWith("@")) return null

        val hasScheme =
            lower.startsWith("http://") || lower.startsWith("https://")
        if (hasScheme) {
            return trimmed
        }

        val hasPathOrQuery =
            trimmed.contains('/') ||
            trimmed.contains('?') ||
            trimmed.contains('#') ||
            trimmed.contains('=')

        val topLevelDomain = trimmed
            .substringAfterLast('.')
            .substringBefore('/')
            .substringBefore('?')
            .substringBefore('#')

        if (topLevelDomain.length !in 2..10 && !isAddressBarContext) {
            return null
        }

        if (!isAddressBarContext && !hasPathOrQuery && !lower.startsWith("www.")) {
            return null
        }

        return "https://$trimmed"
    }

    private fun looksLikeAddressBar(node: AccessibilityNodeInfo): Boolean {
        val resourceId = node.viewIdResourceName?.lowercase() ?: ""
        val text = node.text?.toString()?.lowercase() ?: ""
        val description = node.contentDescription?.toString()?.lowercase() ?: ""
        val className = node.className?.toString()?.lowercase() ?: ""
        val hint = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            node.hintText?.toString()?.lowercase() ?: ""
        } else {
            ""
        }

        val combined = listOf(resourceId, text, description, className, hint).joinToString(" ")
        return combined.contains("url") ||
            combined.contains("address") ||
            combined.contains("location_bar") ||
            combined.contains("search_or_type") ||
            combined.contains("search or type")
    }

    private fun isBrowserPackage(packageName: String): Boolean {
        return packageName in BROWSER_PACKAGES
    }

    /**
     * Returns the appropriate media-capture debounce interval for a given
     * package so that:
     * - Feed apps (Instagram, Facebook, Twitter) capture quickly between posts
     * - Chat apps (WhatsApp, Telegram) capture slowly to avoid flicker on scroll
     * - Everything else uses a balanced default
     */
    private fun mediaCaptureDebounceFor(packageName: String): Long = when (packageName) {
        // Fast refresh for social feed apps — users swipe posts quickly
        "com.instagram.android",
        "com.facebook.katana",
        "com.twitter.android" -> MEDIA_CAPTURE_DEBOUNCE_FEED_MS
        // High debounce for chat apps — prevents rapid scroll events from
        // producing a flood of captures and overlay flicker
        "com.whatsapp",
        "org.telegram.messenger" -> MEDIA_CAPTURE_DEBOUNCE_CHAT_MS
        // All other whitelisted apps (browsers, galleries, unknown apps)
        else -> MEDIA_CAPTURE_DEBOUNCE_DEFAULT_MS
    }

    private fun handleDetectedUrl(url: String, packageName: String) {
        ProtectionEventStore.storeUrlEvent(applicationContext, url, packageName)
        ProtectionEventStore.broadcastUrl(applicationContext, url, packageName)

        val serviceIntent = android.content.Intent(this, RiskGuardForegroundService::class.java)
        ContextCompat.startForegroundService(this, serviceIntent)
    }

    override fun onInterrupt() {
        Log.d(TAG, "Service Interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }
}
