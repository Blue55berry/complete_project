package com.example.risk_guard.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import androidx.core.app.NotificationCompat
import android.util.Log
import com.example.risk_guard.ProtectionEventStore
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class RiskGuardMediaProjectionService : Service() {

    companion object {
        const val ACTION_START_CAPTURE_SESSION = "START_CAPTURE_SESSION"
        const val ACTION_STOP_CAPTURE_SESSION = "STOP_CAPTURE_SESSION"
        const val ACTION_CAPTURE_FRAME = "CAPTURE_FRAME"

        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_PROJECTION_DATA = "projectionData"
        const val EXTRA_SOURCE_PACKAGE = "sourcePackage"
        const val EXTRA_REASON = "reason"
        const val EXTRA_SESSION_ID = "sessionId"
        const val EXTRA_CAPTURE_STAGE = "captureStage"

        private const val CHANNEL_ID = "risk_guard_media_projection"
        private const val NOTIFICATION_ID = 202
        private const val TAG = "RiskGuardCapture"
        private const val CAPTURE_COOLDOWN_MS = 900L         // default (chat apps)
        private const val FEED_CAPTURE_COOLDOWN_MS = 550L     // feed apps need faster re-capture
        private const val BURST_CAPTURE_COOLDOWN_MS = 420L
        private const val CAPTURE_RETRY_DELAY_MS = 90L
        private const val CAPTURE_BOOTSTRAP_DELAY_MS = 120L
        private const val MAX_CAPTURE_FILES = 16
        private const val PREVIEW_MAX_DIMENSION = 360
        private const val ANALYSIS_MAX_DIMENSION = 720
        private const val SIGNATURE_RETENTION_MS = 5000L

        private val FEED_PACKAGES = setOf(
            "com.instagram.android",
            "com.facebook.katana",
            "com.twitter.android",
        )
        private val CHAT_PACKAGES = setOf(
            "com.whatsapp",
            "org.telegram.messenger",
        )
        private val VIEWER_PACKAGES = setOf(
            "com.google.android.apps.photos",
            "com.miui.gallery",
            "com.coloros.gallery3d",
            "com.android.gallery3d",
            "com.google.android.apps.docs",
        )
    }

    private data class CaptureRequest(
        val sourcePackage: String,
        val reason: String,
        val sessionId: String?,
        val captureStage: String,
    )

    private data class CandidateWindow(
        val rect: Rect,
        val label: String,
        val profileBonus: Double,
    )

    private data class SelectedRegion(
        val mediaKind: String,
        val targetType: String,
        val targetLabel: String,
        val confidence: Double,
        val cropBounds: Rect,
        val previewBitmap: Bitmap,
        val analysisBitmap: Bitmap,
        val signature: DoubleArray,
    )

    private data class RecentSignature(
        val signature: DoubleArray,
        val capturedAtMs: Long,
    )

    private val workerThread = HandlerThread("RiskGuardMediaCapture").apply { start() }
    private val workerHandler: Handler by lazy { Handler(workerThread.looper) }

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var captureWidth: Int = 0
    private var captureHeight: Int = 0
    private var densityDpi: Int = 0
    private var captureInProgress = false
    private var lastCaptureAtMs = 0L
    private val lastSignatureByPackage = mutableMapOf<String, RecentSignature>()

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            releaseProjectionResources(stopProjection = false)
            ProtectionEventStore.setMediaProjectionRunning(this@RiskGuardMediaProjectionService, false)
            stopForegroundCompat()
            stopSelf()
        }
    }

    override fun onCreate() {
        super.onCreate()
        mediaProjectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP_CAPTURE_SESSION -> {
                stopCaptureSession()
                return START_NOT_STICKY
            }

            ACTION_START_CAPTURE_SESSION -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                val projectionData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(EXTRA_PROJECTION_DATA, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(EXTRA_PROJECTION_DATA)
                }
                startCaptureSession(resultCode, projectionData)
                return START_STICKY
            }

            ACTION_CAPTURE_FRAME -> {
                val sourcePackage = intent.getStringExtra(EXTRA_SOURCE_PACKAGE) ?: return START_STICKY
                val reason = intent.getStringExtra(EXTRA_REASON) ?: "capture"
                val sessionId = intent.getStringExtra(EXTRA_SESSION_ID)
                val captureStage = intent.getStringExtra(EXTRA_CAPTURE_STAGE) ?: "first_pass"
                requestCapture(
                    CaptureRequest(
                        sourcePackage = sourcePackage,
                        reason = reason,
                        sessionId = sessionId,
                        captureStage = captureStage,
                    ),
                )
                return START_STICKY
            }
        }

        return START_STICKY
    }

    private fun startCaptureSession(resultCode: Int, projectionData: Intent?) {
        if (projectionData == null || resultCode == 0) {
            ProtectionEventStore.setMediaProjectionRunning(this, false)
            return
        }

        releaseProjectionResources(stopProjection = true)
        startForegroundCompat()

        val manager = mediaProjectionManager ?: return
        mediaProjection = manager.getMediaProjection(resultCode, projectionData)
        val projection = mediaProjection ?: return

        val metrics = resources.displayMetrics
        densityDpi = metrics.densityDpi
        val maxDimension = max(metrics.widthPixels, metrics.heightPixels).coerceAtLeast(1)
        val scale = min(1.0, 720.0 / maxDimension.toDouble())
        captureWidth = max(360, (metrics.widthPixels * scale).roundToInt())
        captureHeight = max(640, (metrics.heightPixels * scale).roundToInt())

        imageReader?.close()
        imageReader = ImageReader.newInstance(
            captureWidth,
            captureHeight,
            PixelFormat.RGBA_8888,
            2,
        )

        virtualDisplay?.release()
        virtualDisplay = projection.createVirtualDisplay(
            "RiskGuardRealtimeCapture",
            captureWidth,
            captureHeight,
            densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface,
            null,
            workerHandler,
        )

        projection.registerCallback(projectionCallback, workerHandler)
        ProtectionEventStore.setMediaProjectionRunning(this, true)
    }

    private fun requestCapture(request: CaptureRequest) {
        if (!ProtectionEventStore.canCaptureVisibleMedia(this)) return
        if (!ProtectionEventStore.isMediaProjectionRunning(this)) return
        if (!ProtectionEventStore.whitelistedPackages(this).contains(request.sourcePackage)) return

        val now = System.currentTimeMillis()
        // Use a shorter cooldown for feed apps so users browsing Instagram/
        // Facebook/Twitter get fast per-post captures; chat apps stay at the
        // higher cooldown to avoid flickering during message scrolling.
        val cooldown = when {
            request.captureStage == "burst_followup" -> BURST_CAPTURE_COOLDOWN_MS
            request.sourcePackage in FEED_PACKAGES -> FEED_CAPTURE_COOLDOWN_MS
            else -> CAPTURE_COOLDOWN_MS
        }
        if (captureInProgress || now - lastCaptureAtMs < cooldown) return

        captureInProgress = true
        lastCaptureAtMs = now
        workerHandler.postDelayed(
            { captureLatestImage(request, attempt = 0) },
            CAPTURE_BOOTSTRAP_DELAY_MS,
        )
    }

    private fun captureLatestImage(request: CaptureRequest, attempt: Int) {
        val reader = imageReader
        if (reader == null) {
            captureInProgress = false
            return
        }

        val image = reader.acquireLatestImage()
        if (image == null) {
            if (attempt < 3) {
                workerHandler.postDelayed(
                    { captureLatestImage(request, attempt + 1) },
                    CAPTURE_RETRY_DELAY_MS,
                )
            } else {
                captureInProgress = false
            }
            return
        }

        try {
            val bitmap = imageToBitmap(image) ?: return
            val selection = selectDominantRegion(
                bitmap = bitmap,
                sourcePackage = request.sourcePackage,
                captureStage = request.captureStage,
            )
            if (selection == null) {
                Log.d(TAG, "Skipped capture for ${request.sourcePackage}: no bounded target")
                bitmap.recycle()
                return
            }
            val frameDir = File(cacheDir, "riskguard_realtime_frames").apply { mkdirs() }
            pruneFrameCache(frameDir)
            val timestamp = System.currentTimeMillis()
            val previewFile = File(frameDir, "preview_${timestamp}.jpg")
            val analysisFile = File(frameDir, "analysis_${timestamp}.jpg")
            saveBitmap(selection.previewBitmap, previewFile, quality = 78)
            saveBitmap(selection.analysisBitmap, analysisFile, quality = 88)

            selection.previewBitmap.recycle()
            selection.analysisBitmap.recycle()
            bitmap.recycle()

            lastSignatureByPackage[request.sourcePackage] = RecentSignature(
                signature = selection.signature,
                capturedAtMs = timestamp,
            )

            val sessionId =
                request.sessionId ?: "media-${timestamp}-${request.sourcePackage.hashCode()}"
            ProtectionEventStore.storeMediaCaptureEvent(
                context = this,
                previewPath = previewFile.absolutePath,
                analysisPath = analysisFile.absolutePath,
                sourcePackage = request.sourcePackage,
                targetType = selection.targetType,
                targetLabel = selection.targetLabel,
                mediaKind = selection.mediaKind,
                selectionConfidence = selection.confidence,
                cropBounds = serializeRect(selection.cropBounds),
                reason = request.reason,
                sessionId = sessionId,
                captureStage = request.captureStage,
            )
        } finally {
            image.close()
            captureInProgress = false
            pruneRecentSignatures()
        }
    }

    private fun selectDominantRegion(
        bitmap: Bitmap,
        sourcePackage: String,
        captureStage: String,
    ): SelectedRegion? {
        val width = bitmap.width
        val height = bitmap.height
        val candidates = buildCandidateWindows(width, height, sourcePackage)
        val scaled = Bitmap.createScaledBitmap(bitmap, 96, 96, true)
        val best =
            candidates.maxByOrNull { candidate ->
                scoreCandidate(
                    scaled = scaled,
                    sourceWidth = width,
                    sourceHeight = height,
                    candidate = candidate,
                )
            }

        val fallbackRect = Rect(
            (width * 0.08f).roundToInt(),
            (height * 0.10f).roundToInt(),
            (width * 0.92f).roundToInt(),
            (height * 0.86f).roundToInt(),
        )
        val bestRect = best?.rect ?: fallbackRect
        val bestScore = if (best == null) {
            0.0
        } else {
            scoreCandidate(
                scaled = scaled,
                sourceWidth = width,
                sourceHeight = height,
                candidate = best,
            )
        }
        scaled.recycle()

        val clipped = clipRect(bestRect, width, height)
        val areaRatio =
            (clipped.width().toDouble() * clipped.height().toDouble()) /
                (width.toDouble() * height.toDouble())
        val candidateLabel = best?.label ?: "fallback"
        val viewerLikeCandidate =
            candidateLabel.contains("viewer") ||
                candidateLabel.contains("story") ||
                candidateLabel.contains("reel") ||
                candidateLabel.contains("status")
        val overlyBroadCandidate =
            candidateLabel == "full_bleed" ||
                candidateLabel == "feed_portrait" ||
                candidateLabel == "center_tall"
        val signature = computeSignature(bitmap, clipped)
        val previous = lastSignatureByPackage[sourcePackage]
        val motionDistance =
            if (previous != null && System.currentTimeMillis() - previous.capturedAtMs < SIGNATURE_RETENTION_MS) {
                signatureDistance(signature, previous.signature)
            } else {
                0.0
            }

        val isVideoCandidate =
            ProtectionEventStore.isVideoDetectionEnabled(this) &&
                (
                    captureStage != "first_pass" ||
                        motionDistance > 0.11 ||
                        isVideoProfile(sourcePackage, clipped, width, height)
                )
        val forceScreenFallback =
            bestScore < 0.22 ||
                (sourcePackage in CHAT_PACKAGES &&
                    overlyBroadCandidate &&
                    areaRatio >= 0.56 &&
                    !viewerLikeCandidate) ||
                (sourcePackage in FEED_PACKAGES &&
                    overlyBroadCandidate &&
                    areaRatio >= 0.70 &&
                    !viewerLikeCandidate) ||
                (sourcePackage in VIEWER_PACKAGES &&
                    areaRatio < 0.42 &&
                    !viewerLikeCandidate)

        if (forceScreenFallback) {
            Log.d(TAG, "Rejected capture for $sourcePackage label=$candidateLabel area=${"%.2f".format(areaRatio)} score=${"%.2f".format(bestScore)}")
            return null
        }

        val mediaKind =
            when {
                isVideoCandidate -> "video_frame"
                else -> "image_frame"
            }

        val targetLabel =
            when (mediaKind) {
                "video_frame" -> "Dominant visible video"
                "image_frame" -> "Dominant visible image"
                else -> "Dominant visible image"
            }
        val targetType =
            when (mediaKind) {
                "video_frame" -> "video_frame"
                "image_frame" -> "image_frame"
                else -> "image_frame"
            }
        val previewBitmap = scaleBitmapToMax(Bitmap.createBitmap(bitmap, clipped.left, clipped.top, clipped.width(), clipped.height()), PREVIEW_MAX_DIMENSION)
        val analysisBitmap = scaleBitmapToMax(Bitmap.createBitmap(bitmap, clipped.left, clipped.top, clipped.width(), clipped.height()), ANALYSIS_MAX_DIMENSION)
        val confidence = (bestScore + 0.10).coerceIn(0.18, 0.98)

        return SelectedRegion(
            mediaKind = mediaKind,
            targetType = targetType,
            targetLabel = targetLabel,
            confidence = confidence,
            cropBounds = clipped,
            previewBitmap = previewBitmap,
            analysisBitmap = analysisBitmap,
            signature = signature,
        )
    }

    private fun buildCandidateWindows(
        width: Int,
        height: Int,
        sourcePackage: String,
    ): List<CandidateWindow> {
        val candidates = mutableListOf<CandidateWindow>()
        fun rect(
            leftFraction: Double,
            topFraction: Double,
            widthFraction: Double,
            heightFraction: Double,
            label: String,
            profileBonus: Double,
        ) {
            candidates += CandidateWindow(
                rect = Rect(
                    (width * leftFraction).roundToInt(),
                    (height * topFraction).roundToInt(),
                    (width * (leftFraction + widthFraction)).roundToInt(),
                    (height * (topFraction + heightFraction)).roundToInt(),
                ),
                label = label,
                profileBonus = profileBonus,
            )
        }

        rect(0.03, 0.07, 0.94, 0.80, "full_bleed", 0.02)       // generic wide — penalized
        rect(0.05, 0.14, 0.90, 0.64, "feed_portrait", 0.02)     // generic wide — penalized
        rect(0.11, 0.18, 0.78, 0.52, "center_landscape", 0.05)
        rect(0.10, 0.15, 0.80, 0.56, "center_square", 0.05)
        rect(0.12, 0.20, 0.74, 0.34, "chat_top", 0.08)
        rect(0.12, 0.42, 0.74, 0.34, "chat_mid", 0.08)
        rect(0.08, 0.08, 0.84, 0.74, "center_tall", 0.03)       // generic — penalized

        when {
            sourcePackage in FEED_PACKAGES -> {
                rect(0.03, 0.06, 0.94, 0.84, "story_reel",       0.18)
                rect(0.00, 0.05, 1.00, 0.88, "reel_fullscreen",   0.26) // full-screen reels/stories
                rect(0.05, 0.26, 0.90, 0.48, "feed_image_tight",  0.22) // tight crop on post image
                rect(0.05, 0.18, 0.90, 0.70, "feed_media",        0.14)
                rect(0.08, 0.10, 0.84, 0.82, "story_viewer",      0.28) // boosted
                rect(0.07, 0.18, 0.86, 0.66, "feed_main_media",   0.24) // boosted
                rect(0.14, 0.18, 0.72, 0.68, "feed_post_focus",   0.16)
            }
            sourcePackage in CHAT_PACKAGES -> {
                rect(0.18, 0.22, 0.68, 0.42, "chat_viewer",       0.22) // boosted
                rect(0.05, 0.10, 0.90, 0.82, "status_viewer",     0.17)
                rect(0.14, 0.18, 0.72, 0.28, "chat_media_top",    0.16)
                rect(0.14, 0.36, 0.72, 0.28, "chat_media_mid",    0.16)
                rect(0.12, 0.16, 0.76, 0.64, "chat_single_view",  0.26) // boosted
            }
            sourcePackage in VIEWER_PACKAGES -> {
                rect(0.02, 0.05, 0.96, 0.88, "viewer_full",       0.16)
                rect(0.08, 0.10, 0.84, 0.78, "viewer_center",     0.26) // boosted
            }
        }

        return candidates.map { it.copy(rect = clipRect(it.rect, width, height)) }
    }

    private fun scoreCandidate(
        scaled: Bitmap,
        sourceWidth: Int,
        sourceHeight: Int,
        candidate: CandidateWindow,
    ): Double {
        val scaledRect = Rect(
            (candidate.rect.left.toDouble() / sourceWidth * scaled.width).roundToInt(),
            (candidate.rect.top.toDouble() / sourceHeight * scaled.height).roundToInt(),
            (candidate.rect.right.toDouble() / sourceWidth * scaled.width).roundToInt(),
            (candidate.rect.bottom.toDouble() / sourceHeight * scaled.height).roundToInt(),
        )
        if (scaledRect.width() < 8 || scaledRect.height() < 8) return 0.0

        var luminanceSum = 0.0
        var luminanceSqSum = 0.0
        var saturationSum = 0.0
        var edgeSum = 0.0
        var sampleCount = 0
        var edgeCount = 0
        val stepX = max(1, scaledRect.width() / 18)
        val stepY = max(1, scaledRect.height() / 18)
        for (y in scaledRect.top until scaledRect.bottom step stepY) {
            for (x in scaledRect.left until scaledRect.right step stepX) {
                val px = scaled.getPixel(x, y)
                val r = Color.red(px)
                val g = Color.green(px)
                val b = Color.blue(px)
                val luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
                val maxC = max(r, max(g, b))
                val minC = min(r, min(g, b))
                val saturation =
                    if (maxC == 0) 0.0 else (maxC - minC).toDouble() / maxC.toDouble()
                luminanceSum += luminance
                luminanceSqSum += luminance * luminance
                saturationSum += saturation
                sampleCount++
                if (x + stepX < scaledRect.right) {
                    val nextPx = scaled.getPixel(x + stepX, y)
                    edgeSum += colorDistance(px, nextPx)
                    edgeCount++
                }
                if (y + stepY < scaledRect.bottom) {
                    val nextPy = scaled.getPixel(x, y + stepY)
                    edgeSum += colorDistance(px, nextPy)
                    edgeCount++
                }
            }
        }
        if (sampleCount == 0) return 0.0

        val mean = luminanceSum / sampleCount
        val variance = (luminanceSqSum / sampleCount) - (mean * mean)
        val avgSaturation = saturationSum / sampleCount
        val avgEdge = if (edgeCount == 0) 0.0 else edgeSum / edgeCount
        val areaRatio =
            (candidate.rect.width().toDouble() * candidate.rect.height().toDouble()) /
                (sourceWidth.toDouble() * sourceHeight.toDouble())
        val centerX = candidate.rect.exactCenterX().toDouble()
        val centerY = candidate.rect.exactCenterY().toDouble()
        val dist =
            hypot(centerX - (sourceWidth / 2.0), centerY - (sourceHeight / 2.0))
        val maxDist = hypot(sourceWidth / 2.0, sourceHeight / 2.0)
        val centrality = (1.0 - (dist / maxDist)).coerceIn(0.0, 1.0)

        return (
            variance * 0.38 +
                avgEdge * 0.24 +
                avgSaturation * 0.14 +
                areaRatio * 0.18 +
                centrality * 0.06 +
                candidate.profileBonus
                // Area penalty: candidates covering >65% of screen get
                // progressively penalized so tight media crops win over
                // generic full-bleed candidates.
                - maxOf(0.0, (areaRatio - 0.65) * 0.40)
            ).coerceIn(0.0, 1.0)
    }

    private fun isVideoProfile(
        sourcePackage: String,
        rect: Rect,
        sourceWidth: Int,
        sourceHeight: Int,
    ): Boolean {
        val areaRatio =
            (rect.width().toDouble() * rect.height().toDouble()) /
                (sourceWidth.toDouble() * sourceHeight.toDouble())
        val aspect = rect.height().toDouble() / rect.width().coerceAtLeast(1)
        return when {
            sourcePackage in FEED_PACKAGES ->
                areaRatio >= 0.46 && aspect > 1.2
            sourcePackage == "com.whatsapp" ->
                areaRatio >= 0.50 && aspect > 1.25
            else -> areaRatio >= 0.58 && aspect > 1.1
        }
    }

    private fun computeSignature(bitmap: Bitmap, rect: Rect): DoubleArray {
        val crop = Bitmap.createBitmap(bitmap, rect.left, rect.top, rect.width(), rect.height())
        val scaled = Bitmap.createScaledBitmap(crop, 8, 8, true)
        if (scaled != crop) {
            crop.recycle()
        }
        val result = DoubleArray(64)
        var index = 0
        for (y in 0 until scaled.height) {
            for (x in 0 until scaled.width) {
                val pixel = scaled.getPixel(x, y)
                result[index++] =
                    (0.2126 * Color.red(pixel) +
                        0.7152 * Color.green(pixel) +
                        0.0722 * Color.blue(pixel)) / 255.0
            }
        }
        scaled.recycle()
        return result
    }

    private fun signatureDistance(a: DoubleArray, b: DoubleArray): Double {
        if (a.size != b.size || a.isEmpty()) return 0.0
        var diff = 0.0
        for (i in a.indices) {
            diff += abs(a[i] - b[i])
        }
        return diff / a.size
    }

    private fun colorDistance(a: Int, b: Int): Double {
        val dr = abs(Color.red(a) - Color.red(b)) / 255.0
        val dg = abs(Color.green(a) - Color.green(b)) / 255.0
        val db = abs(Color.blue(a) - Color.blue(b)) / 255.0
        return ((dr + dg + db) / 3.0).coerceIn(0.0, 1.0)
    }

    private fun clipRect(rect: Rect, width: Int, height: Int): Rect {
        val left = rect.left.coerceIn(0, width - 2)
        val top = rect.top.coerceIn(0, height - 2)
        val right = rect.right.coerceIn(left + 2, width)
        val bottom = rect.bottom.coerceIn(top + 2, height)
        return Rect(left, top, right, bottom)
    }

    private fun scaleBitmapToMax(bitmap: Bitmap, maxDimension: Int): Bitmap {
        val currentMax = max(bitmap.width, bitmap.height).coerceAtLeast(1)
        if (currentMax <= maxDimension) return bitmap
        val scale = maxDimension.toDouble() / currentMax.toDouble()
        val width = max(1, (bitmap.width * scale).roundToInt())
        val height = max(1, (bitmap.height * scale).roundToInt())
        val scaled = Bitmap.createScaledBitmap(bitmap, width, height, true)
        bitmap.recycle()
        return scaled
    }

    private fun saveBitmap(bitmap: Bitmap, file: File, quality: Int) {
        FileOutputStream(file).use { output ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, output)
        }
    }

    private fun serializeRect(rect: Rect): String =
        "${rect.left},${rect.top},${rect.right},${rect.bottom}"

    private fun pruneRecentSignatures() {
        val now = System.currentTimeMillis()
        val iterator = lastSignatureByPackage.iterator()
        while (iterator.hasNext()) {
            val next = iterator.next()
            if (now - next.value.capturedAtMs > SIGNATURE_RETENTION_MS) {
                iterator.remove()
            }
        }
    }

    private fun imageToBitmap(image: Image): Bitmap? {
        val plane = image.planes.firstOrNull() ?: return null
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * image.width

        val wideBitmap = Bitmap.createBitmap(
            image.width + rowPadding / pixelStride,
            image.height,
            Bitmap.Config.ARGB_8888,
        )
        wideBitmap.copyPixelsFromBuffer(buffer)

        val cropped = Bitmap.createBitmap(wideBitmap, 0, 0, image.width, image.height)

        if (cropped != wideBitmap) {
            wideBitmap.recycle()
        }
        return cropped
    }

    private fun pruneFrameCache(directory: File) {
        val files = directory.listFiles()?.sortedByDescending { it.lastModified() } ?: return
        if (files.size < MAX_CAPTURE_FILES) return
        files.drop(MAX_CAPTURE_FILES).forEach { file ->
            runCatching { file.delete() }
        }
    }

    private fun stopCaptureSession() {
        releaseProjectionResources(stopProjection = true)
        ProtectionEventStore.setMediaProjectionRunning(this, false)
        stopForegroundCompat()
        stopSelf()
    }

    private fun releaseProjectionResources(stopProjection: Boolean) {
        captureInProgress = false
        virtualDisplay?.release()
        virtualDisplay = null

        imageReader?.close()
        imageReader = null

        mediaProjection?.let { projection ->
            projection.unregisterCallback(projectionCallback)
            if (stopProjection) {
                projection.stop()
            }
        }
        mediaProjection = null
    }

    private fun startForegroundCompat() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "RiskGuard Screen Capture",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("RiskGuard Screen Capture Active")
            .setContentText("Monitoring visible media in whitelisted apps.")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    override fun onDestroy() {
        releaseProjectionResources(stopProjection = true)
        ProtectionEventStore.setMediaProjectionRunning(this, false)
        workerThread.quitSafely()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
