import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:risk_guard/core/models/analysis_models.dart';
import 'package:risk_guard/core/services/api_service.dart';
import 'package:risk_guard/core/services/native_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

enum _OverlaySurface { hidden, bubble, card, call }
enum _SessionKind { none, url, media, call }
enum _SessionState { dismissed, captured, verifying, ready, degraded }
enum _CallChipAnchor { left, center, right }

class _CachedUrlVerdict {
  const _CachedUrlVerdict(this.verdict, this.cachedAt);
  final UrlVerificationResult verdict;
  final DateTime cachedAt;
  bool get isFresh =>
      DateTime.now().difference(cachedAt) < const Duration(minutes: 2);
}

class _Session {
  const _Session({
    required this.id,
    required this.kind,
    required this.state,
    required this.sourcePackage,
    required this.targetType,
    required this.target,
    required this.status,
    required this.summary,
    required this.recommendation,
    required this.intelSource,
    required this.threatType,
    required this.phoneNumber,
    required this.riskScore,
    required this.isThreat,
    required this.previewPath,
    required this.mediaKind,
    required this.selectionConfidence,
    required this.captureStage,
  });

  const _Session.idle()
      : id = '',
        kind = _SessionKind.none,
        state = _SessionState.dismissed,
        sourcePackage = '',
        targetType = 'URL',
        target = 'Awaiting live capture',
        status = 'MONITORING ACTIVE',
        summary = 'RiskGuard is ready to monitor whitelisted apps.',
        recommendation = 'RiskGuard will surface live verdicts here.',
        intelSource = 'LOCAL SHIELD',
        threatType = 'Shield Ready',
        phoneNumber = 'Hidden Number',
        riskScore = 0,
        isThreat = false,
        previewPath = null,
        mediaKind = 'idle',
        selectionConfidence = 0,
        captureStage = 'idle';

  final String id;
  final _SessionKind kind;
  final _SessionState state;
  final String sourcePackage;
  final String targetType;
  final String target;
  final String status;
  final String summary;
  final String recommendation;
  final String intelSource;
  final String threatType;
  final String phoneNumber;
  final double riskScore;
  final bool isThreat;
  final String? previewPath;
  final String mediaKind;
  final double selectionConfidence;
  final String captureStage;

  _Session copyWith({
    String? id,
    _SessionKind? kind,
    _SessionState? state,
    String? sourcePackage,
    String? targetType,
    String? target,
    String? status,
    String? summary,
    String? recommendation,
    String? intelSource,
    String? threatType,
    String? phoneNumber,
    double? riskScore,
    bool? isThreat,
    String? previewPath,
    String? mediaKind,
    double? selectionConfidence,
    String? captureStage,
  }) => _Session(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    state: state ?? this.state,
    sourcePackage: sourcePackage ?? this.sourcePackage,
    targetType: targetType ?? this.targetType,
    target: target ?? this.target,
    status: status ?? this.status,
    summary: summary ?? this.summary,
    recommendation: recommendation ?? this.recommendation,
    intelSource: intelSource ?? this.intelSource,
    threatType: threatType ?? this.threatType,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    riskScore: riskScore ?? this.riskScore,
    isThreat: isThreat ?? this.isThreat,
    previewPath: previewPath ?? this.previewPath,
    mediaKind: mediaKind ?? this.mediaKind,
    selectionConfidence: selectionConfidence ?? this.selectionConfidence,
    captureStage: captureStage ?? this.captureStage,
  );
}

class RiskGuardOverlay extends StatefulWidget {
  const RiskGuardOverlay({super.key});
  @override
  State<RiskGuardOverlay> createState() => _RiskGuardOverlayState();
}

class _RiskGuardOverlayState extends State<RiskGuardOverlay> {
  static const MethodChannel _channel = MethodChannel('com.example.risk_guard/overlay');
  static const double _bubbleSize = 84;
  static const double _cardWidth = 368;
  static const double _cardHeight = 328;
  static const double _callChipHeight = 58;
  static const double _callChipWidth = 214;
  static const double _callPanelWidth = 320;
  static const double _callPanelHeight = 228;
  // Anti-flicker: minimum ms between surface transitions
  static const int _surfaceTransitionCooldownMs = 300;
  // Anti-flicker: minimum ms before repeating a resize for the same surface
  static const int _resizeDedupMs = 300;
  // Drag distance threshold (pixels²) before a pan is considered a drag
  static const double _dragThresholdSq = 4.0; // More sensitive drag detection
  final Map<String, _CachedUrlVerdict> _urlVerdicts = <String, _CachedUrlVerdict>{};
  final Set<String> _processedEventIds = <String>{};
  final Set<String> _scheduledBurstSessions = <String>{};
  int _lastQueueUpdatedAtMs = 0;
  SharedPreferences? _prefs;
  Timer? _pollTimer;
  Timer? _dismissTimer;
  Timer? _visibilityHideTimer;
  Timer? _waveTimer;
  _OverlaySurface _surface = _OverlaySurface.hidden;
  _Session _session = const _Session.idle();
  String? _foregroundPackage;
  bool _foregroundWhitelisted = false;
  bool _protectionActive = true;
  // ignore: unused_field
  bool _voiceDetectionEnabled = true;
  bool _imageDetectionEnabled = true;
  // ignore: unused_field
  bool _textDetectionEnabled = true;
  bool _videoDetectionEnabled = true;
  bool _callMonitoringEnabled = true;
  String? _collapsedSessionId;
  // Synced position cache — updated optimistically on every drag event.
  // This means drag starts INSTANTLY with no async wait for getOverlayPosition().
  OverlayPosition? _bubblePosition;
  OverlayPosition? _dragPosition; // current drag in-progress position
  OverlayPosition? _callPanelPosition;
  // Call chip remembered position (persists across expand/collapse cycles)
  OverlayPosition? _callChipLastPosition;
  Size _viewportSize = const Size(392, 820);
  DateTime _surfacePinnedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _bubbleTapSuppressedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _callTapSuppressedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _interactiveCaptureUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _callExpanded = false;
  bool _cardExpanded = false;
  _CallChipAnchor _callChipAnchor = _CallChipAnchor.center;
  double _callChipY = 26;
  double _callChipX = -1; // -1 = unset, use anchor-based default
  int _wavePhase = 0;
  bool _bubbleDragged = false;
  bool _callChipDragged = false;
  // ignore: unused_field
  bool _callPanelDragged = false;
  // Drag throttle — 16ms = exactly 60fps, smoothest possible
  int _lastMoveMs = 0;
  static const int _moveCooldownMs = 16; // 60fps drag
  // Anti-flicker state
  int _lastSurfaceChangeMs = 0;
  int _lastResizeMs = 0;
  _OverlaySurface _lastResizeSurface = _OverlaySurface.hidden;
  bool _surfaceTransitioning = false;
  // Poll
  int _lastPollSuccessMs = 0;
  int _lastSetWidth = 0;
  int _lastSetHeight = 0;
  // Visibility debounce: tracks how many consecutive 'hidden' events fired
  int _visibilityHideCount = 0;
  // ── 24-hour position memory ───────────────────────────────────────────────
  // Positions are saved to SharedPreferences on every drag-end.
  // They are restored when the overlay boots, as long as they were saved
  // within the last 24 hours (counted from the time real-time was enabled).
  static const String _prefBubbleX      = 'overlay_bubble_x';
  static const String _prefBubbleY      = 'overlay_bubble_y';
  static const String _prefChipX       = 'overlay_chip_x';
  static const String _prefChipY       = 'overlay_chip_y';
  static const String _prefPanelX      = 'overlay_panel_x';
  static const String _prefPanelY      = 'overlay_panel_y';
  static const String _prefPosSavedAt  = 'overlay_pos_saved_at_ms';  
  static const int    _posMemoryMs     = 24 * 60 * 60 * 1000;        // 24 hours in ms

  bool get _isAnalyzing => _session.state == _SessionState.captured || _session.state == _SessionState.verifying;
  bool get _bubbleAllowed => _session.kind == _SessionKind.call || _foregroundWhitelisted;
  bool get _cardEligible =>
      (_session.kind == _SessionKind.url || _session.kind == _SessionKind.media) &&
      _foregroundWhitelisted &&
      _session.sourcePackage == _foregroundPackage &&
      _session.id.isNotEmpty;
  bool get _cardAllowed => _cardEligible && _cardExpanded && _session.id != _collapsedSessionId;
  bool get _canExpandFromBubble =>
      _session.kind == _SessionKind.call || _cardEligible || (_session.kind == _SessionKind.none && _foregroundWhitelisted);
  bool get _isSurfacePinned => DateTime.now().isBefore(_surfacePinnedUntil);
  bool get _waitingForInteractiveCapture =>
      DateTime.now().isBefore(_interactiveCaptureUntil);

  @override
  void initState() {
    super.initState();
    _boot();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onMessageReceived' && call.arguments is Map) {
        _applyPayload(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
  }

  Future<void> _boot() async {
    _prefs = await SharedPreferences.getInstance();
    _loadSavedPositions(); // Restore 24-hour remembered positions
    await _setSurface(_OverlaySurface.hidden);
    _schedulePoll();
  }

  /// Load chip + panel positions from SharedPreferences.
  /// Only applied if they were saved within the last 24 hours.
  void _loadSavedPositions() {
    final prefs = _prefs;
    if (prefs == null) return;
    final savedAt = prefs.getInt(_prefPosSavedAt) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (savedAt <= 0 || (now - savedAt) > _posMemoryMs) return; // Expired

    // Bubble position
    final bubbleX = prefs.getDouble(_prefBubbleX);
    final bubbleY = prefs.getDouble(_prefBubbleY);
    if (bubbleX != null && bubbleY != null) {
      _bubblePosition = OverlayPosition(bubbleX, bubbleY);
    }

    // Chip position
    final chipX = prefs.getDouble(_prefChipX);
    final chipY = prefs.getDouble(_prefChipY);
    if (chipX != null && chipY != null) {
      _callChipX = chipX;
      _callChipY = chipY;
      _callChipLastPosition = OverlayPosition(chipX, chipY);
    }

    // Panel position
    final panelX = prefs.getDouble(_prefPanelX);
    final panelY = prefs.getDouble(_prefPanelY);
    if (panelX != null && panelY != null) {
      _callPanelPosition = OverlayPosition(panelX, panelY);
    }
  }

  /// Persist chip + panel positions to SharedPreferences.
  /// Called after every drag-end so positions survive app restarts for 24 hrs.
  void _savePositions() {
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await Future.wait([
        if (_bubblePosition != null) prefs.setDouble(_prefBubbleX, _bubblePosition!.x),
        if (_bubblePosition != null) prefs.setDouble(_prefBubbleY, _bubblePosition!.y),
        if (_callChipX >= 0) prefs.setDouble(_prefChipX, _callChipX),
        if (_callChipX >= 0) prefs.setDouble(_prefChipY, _callChipY),
        if (_callPanelPosition != null) prefs.setDouble(_prefPanelX, _callPanelPosition!.x),
        if (_callPanelPosition != null) prefs.setDouble(_prefPanelY, _callPanelPosition!.y),
        prefs.setInt(_prefPosSavedAt, now),
      ]);
    }());
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    final delay = _surface == _OverlaySurface.hidden && !_isAnalyzing && _session.kind != _SessionKind.call
        ? const Duration(milliseconds: 1500)
        : const Duration(milliseconds: 350);
    _pollTimer = Timer(delay, () async {
      await _pollQueue();
      if (mounted) _schedulePoll();
    });
  }

  Future<void> _pollQueue() async {
    final prefs = _prefs;
    if (prefs == null) return;
    // Skip reload if we already reloaded very recently (prevents double-reload
    // during rapid event bursts that would cause scroll-triggered flickering)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastPollSuccessMs < 200) return;
    await prefs.reload();
    _lastPollSuccessMs = DateTime.now().millisecondsSinceEpoch;
    final updatedAt = _readInt(prefs.get('protection_event_queue_updated_at'));
    if (updatedAt > 0 && updatedAt == _lastQueueUpdatedAtMs) return;
    final raw = prefs.getString('protection_event_queue');
    if (raw == null || raw.isEmpty) {
      if (updatedAt > 0) {
        _lastQueueUpdatedAtMs = updatedAt;
      }
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      if (updatedAt > 0) {
        _lastQueueUpdatedAtMs = updatedAt;
      }
      return;
    }
    final events = decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      ..sort((a, b) => _readInt(a['createdAtMs']).compareTo(_readInt(b['createdAtMs'])));
    for (final event in events) {
      final id = event['id']?.toString();
      if (id == null || _processedEventIds.contains(id)) continue;
      if (_readInt(event['expiresAtMs']) > 0 &&
          DateTime.now().millisecondsSinceEpoch > _readInt(event['expiresAtMs'])) {
        _remember(id);
        continue;
      }
      switch (event['kind']) {
        case 'url_capture':
          await _handleUrlEvent(event);
          break;
        case 'media_result':
          await _handleMediaEvent(event);
          break;
        case 'call_state':
          await _handleCallEvent(event);
          break;
        case 'overlay_status':
          _handleOverlayStatus(event);
          break;
      }
      _remember(id);
    }
    if (updatedAt > 0) {
      _lastQueueUpdatedAtMs = updatedAt;
    }
  }

  int _readInt(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  void _remember(String id) {
    _processedEventIds.add(id);
    if (_processedEventIds.length > 120) _processedEventIds.remove(_processedEventIds.first);
  }

  void _pinSurface([Duration duration = const Duration(milliseconds: 850)]) {
    _surfacePinnedUntil = DateTime.now().add(duration);
  }

  void _suppressBubbleTap([Duration duration = const Duration(milliseconds: 260)]) {
    _bubbleTapSuppressedUntil = DateTime.now().add(duration);
  }

  void _suppressCallTap([Duration duration = const Duration(milliseconds: 260)]) {
    _callTapSuppressedUntil = DateTime.now().add(duration);
  }

  void _cleanupPreview(String? path) {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!file.existsSync()) return;
    unawaited(file.delete());
  }

  String _appName(String? packageName) {
    const known = <String, String>{
      'com.android.chrome': 'Chrome',
      'com.whatsapp': 'WhatsApp',
      'org.telegram.messenger': 'Telegram',
      'com.instagram.android': 'Instagram',
      'com.facebook.katana': 'Facebook',
      'phone_service': 'Phone Service',
    };
    if (packageName == null || packageName.isEmpty) return 'Protected App';
    return known[packageName] ?? packageName.split('.').last.replaceAll('_', ' ');
  }

  Future<void> _handleUrlEvent(Map<String, dynamic> event) async {
    final id = event['id']?.toString();
    final target = event['normalizedTarget']?.toString();
    final pkg = event['sourcePackage']?.toString() ?? '';
    if (id == null || target == null || target.isEmpty) return;
    _dismissTimer?.cancel();
    _collapsedSessionId = null;
    _setSession(_Session(
      id: id,
      kind: _SessionKind.url,
      state: _SessionState.captured,
      sourcePackage: pkg,
      targetType: 'URL',
      target: target,
      status: 'CAPTURED LINK',
      summary: 'Target captured from the active monitored app. Starting verification.',
      recommendation: 'Preparing normalization and offline precheck.',
      intelSource: 'LOCAL PRECHECK',
      threatType: 'URL',
      phoneNumber: _session.phoneNumber,
      riskScore: 0.08,
      isThreat: false,
      previewPath: null,
      mediaKind: 'url',
      selectionConfidence: 1,
      captureStage: 'final',
    ));
    await _syncSurface();
    final cached = _urlVerdicts[target];
    if (cached != null && cached.isFresh) {
      if (_session.id == id) _applyVerdict(cached.verdict, pkg, true);
      return;
    }
    _setSession(_session.copyWith(
      state: _SessionState.verifying,
      status: 'CLOUD VERIFYING',
      summary: 'Comparing the target against live threat intelligence and local checks.',
      recommendation: 'Waiting for a final verdict.',
      intelSource: 'THREAT INTEL',
      riskScore: 0.16,
    ));
    await _syncSurface();
    try {
      final result = await ApiService().verifyUrl(target);
      if (!mounted || _session.id != id) return;
      if (!result.isSuccess || result.data == null) {
        _setSession(_session.copyWith(
          state: _SessionState.degraded,
          status: 'DEGRADED OFFLINE',
          summary: 'Live capture succeeded, but the backend verdict was unavailable.',
          recommendation: 'Treat this target with caution until connectivity is restored.',
          intelSource: 'OFFLINE FALLBACK',
          threatType: 'Pending',
          riskScore: 0.2,
        ));
        await _syncSurface();
        _scheduleDismiss(id);
        return;
      }
      _urlVerdicts[target] = _CachedUrlVerdict(result.data!, DateTime.now());
      _applyVerdict(result.data!, pkg, false);
    } catch (_) {
      if (!mounted || _session.id != id) return;
      _setSession(_session.copyWith(
        state: _SessionState.degraded,
        status: 'SCAN ERROR',
        summary: 'Realtime verification failed before a final verdict.',
        recommendation: 'Keep the target unopened until verification recovers.',
        intelSource: 'ERROR',
        threatType: 'Retry Needed',
        riskScore: 0.18,
      ));
      await _syncSurface();
      _scheduleDismiss(id);
    }
  }

  void _applyVerdict(UrlVerificationResult verdict, String pkg, bool fromCache) {
    final danger = verdict.status.toUpperCase().contains('DANGER') || verdict.status.toUpperCase().contains('MALICIOUS');
    final next = _session.copyWith(
      state: _SessionState.ready,
      status: 'VERDICT READY',
      sourcePackage: pkg,
      target: verdict.url.isNotEmpty ? verdict.url : _session.target,
      summary: danger ? 'Threat indicators were found for this destination.' : 'No known malicious indicators were found for this destination.',
      recommendation: verdict.recommendation,
      intelSource: verdict.intelligenceSource.isNotEmpty ? verdict.intelligenceSource.toUpperCase() : (fromCache ? 'LOCAL CACHE' : 'THREAT INTEL'),
      threatType: verdict.threatType.isNotEmpty ? verdict.threatType : 'URL',
      riskScore: (verdict.riskScore / 100).clamp(0.0, 1.0).toDouble(),
      isThreat: danger,
    );
    _setSession(next);
    unawaited(_syncSurface());
    _scheduleDismiss(next.id);
  }

  Future<void> _handleMediaEvent(Map<String, dynamic> event) async {
    if (!_imageDetectionEnabled && !_videoDetectionEnabled) return;
    if (_session.kind == _SessionKind.call) return;
    final payload = event['payload'];
    if (payload is Map) {
      final mediaPayload = Map<String, dynamic>.from(payload);
      if (mediaPayload['localFramePath'] != null) {
        await _handleCapturedFramePayload(
          mediaPayload,
          fallbackSessionId: event['sessionId']?.toString() ?? event['id']?.toString(),
        );
        return;
      }
      _applyPayload(mediaPayload);
    }
  }

  Future<void> _handleCapturedFramePayload(
    Map<String, dynamic> payload, {
    String? fallbackSessionId,
  }) async {
    final String analysisPath =
        payload['analysisPath']?.toString() ??
        payload['localFramePath']?.toString() ??
        '';
    final String previewPath =
        payload['previewPath']?.toString() ?? analysisPath;
    final String sessionId =
        payload['sessionId']?.toString() ??
        payload['requestId']?.toString() ??
        fallbackSessionId ??
        'media-${DateTime.now().millisecondsSinceEpoch}';
    final String sourcePackage =
        payload['sourcePackage']?.toString() ??
        payload['source']?.toString() ??
        _foregroundPackage ??
        _session.sourcePackage;
    final String mediaKind =
        payload['mediaKind']?.toString() ?? 'screen_fallback';
    final String captureStage =
        payload['captureStage']?.toString() ?? 'first_pass';
    final double selectionConfidence =
        ((payload['selectionConfidence'] as num?)?.toDouble() ?? 0.2)
            .clamp(0.0, 1.0);
    final String targetLabel =
        payload['targetLabel']?.toString() ?? _labelForMediaKind(mediaKind);
    final String targetType =
        payload['targetType']?.toString() ?? _typeForMediaKind(mediaKind);

    if (mediaKind == 'screen_fallback') return;
    
    if (mediaKind == 'video_frame' && !_videoDetectionEnabled) return;
    if (mediaKind == 'image_frame' && !_imageDetectionEnabled) {
      return;
    }

    if (_session.kind == _SessionKind.url &&
        _session.sourcePackage == sourcePackage &&
        _session.id.isNotEmpty) {
      return;
    }

    if (_session.kind == _SessionKind.media &&
        _isAnalyzing &&
        _session.sourcePackage == sourcePackage) {
      return;
    }

    if (sourcePackage.isNotEmpty &&
        _foregroundPackage != null &&
        sourcePackage != _foregroundPackage) {
      return;
    }

    final File frameFile = File(analysisPath);
    if (analysisPath.isEmpty) {
      return;
    }
    _dismissTimer?.cancel();
    _collapsedSessionId = null;
    _pinSurface(
      captureStage == 'burst_followup'
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 1200),
    );
    _setSession(
      _Session(
        id: sessionId,
        kind: _SessionKind.media,
        state: _SessionState.captured,
        sourcePackage: sourcePackage,
        targetType: targetType.toUpperCase(),
        target: targetLabel,
        status:
            captureStage == 'burst_followup'
                ? 'VIDEO BURST FRAME'
                : 'CAPTURED MEDIA',
        summary:
            captureStage == 'burst_followup'
                ? 'Captured another live video frame to strengthen the current verdict.'
                : 'Captured the dominant visible media from the monitored app. Starting deepfake verification.',
        recommendation:
            captureStage == 'burst_followup'
                ? 'Keep the same video visible while RiskGuard completes the burst verification.'
                : 'Keep the current media visible while RiskGuard completes the first-pass verdict.',
        intelSource:
            captureStage == 'burst_followup'
                ? 'VIDEO BURST'
                : 'SCREEN CAPTURE',
        threatType: _threatTypeForMediaKind(mediaKind),
        phoneNumber: _session.phoneNumber,
        riskScore: 0.12,
        isThreat: false,
        previewPath: previewPath,
        mediaKind: mediaKind,
        selectionConfidence: selectionConfidence,
        captureStage: captureStage,
      ),
    );
    await _syncSurface();

    if (!await frameFile.exists()) {
      _setSession(
        _session.copyWith(
          state: _SessionState.degraded,
          status: 'CAPTURE ERROR',
          summary: 'The captured frame was no longer available for analysis.',
          recommendation:
              'Keep the source visible and wait for the next capture cycle.',
          intelSource: 'SCREEN CAPTURE',
          riskScore: 0.15,
          captureStage: captureStage,
        ),
      );
      await _syncSurface();
      _scheduleDismiss(sessionId);
      return;
    }

    try {
      final bytes = await frameFile.readAsBytes();
      if (!mounted || _session.id != sessionId) return;

      _setSession(
        _session.copyWith(
          state: _SessionState.verifying,
          status:
              captureStage == 'burst_followup'
                  ? 'ANALYZING VIDEO BURST'
                  : 'ANALYZING FIRST PASS',
          summary:
              captureStage == 'burst_followup'
                  ? 'Running a follow-up verification on additional live video frames.'
                  : 'Running deepfake analysis on the dominant visible media.',
          recommendation:
              captureStage == 'burst_followup'
                  ? 'Hold the same video in view for a stronger final verdict.'
                  : 'Waiting for the first media verdict.',
          intelSource:
              captureStage == 'burst_followup' ? 'VIDEO BURST' : 'LIVE MEDIA',
          riskScore: 0.18,
          captureStage: captureStage,
        ),
      );
      await _syncSurface();

      final result = await ApiService().analyzeRealtimeMedia(
        bytes,
        requestId:
            '${sessionId}_${captureStage}_${DateTime.now().millisecondsSinceEpoch}',
        sessionId: sessionId,
        mediaKind: mediaKind,
        captureStage: captureStage,
        selectionConfidence: selectionConfidence,
        sourcePackage:
            sourcePackage.isNotEmpty
                ? sourcePackage
                : (_foregroundPackage ?? 'unknown'),
        capturedAt: DateTime.now().toUtc().toIso8601String(),
        filename: frameFile.uri.pathSegments.isNotEmpty
            ? frameFile.uri.pathSegments.last
            : 'screen_frame.jpg',
      );
      if (!mounted || _session.id != sessionId) return;

      if (!result.isSuccess || result.data == null) {
        _setSession(
          _session.copyWith(
            state: _SessionState.degraded,
            status: 'MEDIA BACKEND UNAVAILABLE',
            summary:
                'Live capture succeeded, but the backend did not return a media verdict.',
            recommendation:
                'RiskGuard will continue capturing new frames while connectivity recovers.',
            intelSource: 'OFFLINE / DEGRADED',
            threatType: _threatTypeForMediaKind(mediaKind),
            riskScore: 0.2,
            captureStage: captureStage,
          ),
        );
        await _syncSurface();
        _scheduleDismiss(sessionId);
        return;
      }

      final analysis = result.data!;
      // Preview path comes from the locally captured file (set when frame was captured).
      final probability = analysis.aiGeneratedProbability > 1
          ? analysis.aiGeneratedProbability / 100
          : analysis.aiGeneratedProbability;
      final isThreat = analysis.isAiGenerated || probability >= 0.65;

      if (captureStage == 'burst_followup' && _session.id == sessionId) {
        final mergedScore =
            ((_session.riskScore + probability) / 2).clamp(0.0, 1.0).toDouble();
        final mergedThreat = _session.isThreat || isThreat;
        _setSession(
          _session.copyWith(
            state: _SessionState.ready,
            status: 'FINAL VIDEO VERDICT',
            summary: analysis.explanation.isNotEmpty
                ? analysis.explanation
                : (mergedThreat
                    ? 'Additional live frames strengthened the deepfake concern for this video.'
                    : 'Additional live frames did not reveal strong deepfake indicators.'),
            recommendation: mergedThreat
                ? 'Treat this video as suspicious until you verify the original source.'
                : 'No strong deepfake indicators were found in the sampled live frames.',
            intelSource: 'VIDEO BURST',
            threatType: 'Video Deepfake',
            riskScore: mergedScore,
            isThreat: mergedThreat,
            mediaKind: 'video_frame',
            captureStage: 'final',
          ),
        );
        await _syncSurface();
        _scheduleDismiss(sessionId);
        return;
      }

      _setSession(
        _session.copyWith(
          state: _SessionState.ready,
          status:
              mediaKind == 'video_frame'
                  ? 'FIRST VIDEO PASS'
                  : 'MEDIA VERDICT READY',
          summary: analysis.explanation.isNotEmpty
              ? analysis.explanation
              : (isThreat
                    ? 'Potential deepfake indicators were found in the visible media.'
                    : 'No strong deepfake indicators were found in the visible media.'),
          recommendation: isThreat
              ? 'Treat this media as untrusted until you verify the source.'
              : 'No immediate deepfake risk was detected from this captured frame.',
          intelSource:
              mediaKind == 'video_frame'
                  ? 'FIRST PASS'
                  : analysis.analysisMethod.toUpperCase(),
          threatType: _threatTypeForMediaKind(mediaKind),
          riskScore: probability.clamp(0.0, 1.0),
          isThreat: isThreat,
          mediaKind: mediaKind,
          captureStage:
              mediaKind == 'video_frame' ? 'first_pass_complete' : 'final',
        ),
      );
      await _syncSurface();
      if (mediaKind == 'video_frame' && _videoDetectionEnabled) {
        _scheduleVideoBurst(sessionId, sourcePackage);
      } else {
        _scheduleDismiss(sessionId);
      }
    } catch (_) {
      if (!mounted || _session.id != sessionId) return;
      _setSession(
        _session.copyWith(
          state: _SessionState.degraded,
          status: 'FRAME ANALYSIS ERROR',
          summary: 'Captured media could not be analyzed successfully.',
          recommendation:
              'RiskGuard will wait for the next valid frame capture from this app.',
          intelSource: 'ERROR',
          riskScore: 0.18,
          captureStage: captureStage,
        ),
      );
      await _syncSurface();
      _scheduleDismiss(sessionId);
    }
  }

  Future<void> _handleCallEvent(Map<String, dynamic> event) async {
    if (!_callMonitoringEnabled) {
      if (_session.kind == _SessionKind.call) {
        _callExpanded = false;
        await _clearSession();
      }
      return;
    }
    final state = (event['callState']?.toString() ?? event['normalizedTarget']?.toString() ?? '').toUpperCase();
    if (state.isEmpty) return;
    if (state == 'IDLE') {
      _callExpanded = false;
      await _clearSession();
      return;
    }
    final number = event['phoneNumber']?.toString();
    _dismissTimer?.cancel();
    _collapsedSessionId = null;
    if (_session.kind != _SessionKind.call) {
      _callExpanded = false;
    }
    _setSession(_Session(
      id: event['id']?.toString() ?? 'call-${DateTime.now().millisecondsSinceEpoch}',
      kind: _SessionKind.call,
      state: _SessionState.verifying,
      sourcePackage: 'phone_service',
      targetType: 'VOICE',
      target: number?.isNotEmpty == true ? number! : _session.target,
      status: state == 'RINGING' ? 'INCOMING' : 'LIVE VOICE',
      summary: state == 'RINGING' ? 'RiskGuard is preparing a live caller profile.' : 'RiskGuard is monitoring the live voice stream in the background.',
      recommendation: 'Use the native call screen for answer, hold, mute, keypad, and other call controls.',
      intelSource: 'VOICE STREAM',
      threatType: 'VOICE',
      phoneNumber: number?.isNotEmpty == true ? number! : _session.phoneNumber,
      riskScore: 0,
      isThreat: false,
      previewPath: null,
      mediaKind: 'voice_stream',
      selectionConfidence: 1,
      captureStage: 'live',
    ));
    await _syncSurface();
  }

  void _handleOverlayStatus(Map<String, dynamic> event) {
    final payload = event['payload'];
    if (event['targetType'] == 'visibility' && payload is Map) {
      final visibility = Map<String, dynamic>.from(payload);
      final packageName = visibility['packageName']?.toString();
      final visible = visibility['visible'] == true;

      if (visible) {
        // ── App came to foreground ─────────────────────────────────────────
        // Cancel any pending hide and immediately show bubble.
        _visibilityHideTimer?.cancel();
        _visibilityHideCount = 0;
        _foregroundPackage = packageName;
        _foregroundWhitelisted = true;
        // If a different whitelisted app is now foreground, reset the session.
        if (_session.kind != _SessionKind.call &&
            _session.kind != _SessionKind.none &&
            _session.sourcePackage.isNotEmpty &&
            packageName != null &&
            packageName.isNotEmpty &&
            _session.sourcePackage != packageName) {
          _collapsedSessionId = null;
          _setSession(const _Session.idle());
        }
        unawaited(_syncSurface());
      } else {
        // ── App left foreground ───────────────────────────────────────────
        // Use a 2-stage debounce:
        //   Stage 1: Wait 800ms — kills brief system-UI interruptions (keyboards,
        //            pull-down notifications, volume HUD) that fire 'hidden' then
        //            immediately 'visible' again during normal app usage.
        //   Stage 2: If still hidden after 800ms, wait another 1500ms before
        //            actually clearing the session — gives the user time to
        //            switch back (e.g. copy a URL, check another app briefly).
        // NEVER hide during active analysis regardless of how long we wait.
        _visibilityHideCount++;
        final capturedCount = _visibilityHideCount;
        _visibilityHideTimer?.cancel();
        _visibilityHideTimer = Timer(const Duration(milliseconds: 800), () async {
          if (!mounted) return;
          // If a new 'visible' or newer 'hidden' event fired, abort.
          if (_visibilityHideCount != capturedCount) return;
          // Still actively analyzing — keep overlay alive.
          if (_isAnalyzing) return;
          // Call sessions survive foreground changes (call is ongoing independently).
          if (_session.kind == _SessionKind.call) {
            _foregroundWhitelisted = false;
            _foregroundPackage = packageName;
            return; // Keep call chip/panel visible — call is still active
          }
          // Second stage: wait for user to possibly switch back
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          if (!mounted) return;
          if (_visibilityHideCount != capturedCount) return; // Back already
          if (_isAnalyzing) return;
          if (_session.kind == _SessionKind.call) return;
          // Confirmed gone: clear state and hide
          _foregroundPackage = packageName;
          _foregroundWhitelisted = false;
          _interactiveCaptureUntil = DateTime.fromMillisecondsSinceEpoch(0);
          if (_session.kind != _SessionKind.none) {
            await _clearSession();
          } else {
            await _syncSurface();
          }
        });
      }
      return;
    }
    if (payload is Map) {
      final map = Map<String, dynamic>.from(payload);
      if ((map['type']?.toString() ?? '').toLowerCase() == 'policy_update') {
        _applyPolicyUpdate(map);
      } else {
        _applyPayload(map);
      }
    }
  }

  void _applyPayload(Map<String, dynamic> payload) {
    if ((payload['type']?.toString() ?? '').toLowerCase() == 'policy_update') {
      _applyPolicyUpdate(payload);
      return;
    }
    final rawKind = (payload['sessionKind']?.toString() ?? payload['kind']?.toString() ?? '').toLowerCase();
    final targetType = (payload['targetType']?.toString() ?? '').toLowerCase();
    final sourcePackage =
        payload['sourcePackage']?.toString() ??
        payload['source']?.toString() ??
        _session.sourcePackage;
    final isCall =
        payload['isCallActive'] == true ||
        rawKind == 'call' ||
        sourcePackage == 'phone_service' ||
        payload.containsKey('callState');
    if (isCall && !_callMonitoringEnabled) {
      return;
    }
    if (isCall && ((payload['status']?.toString().toUpperCase() == 'CALL ENDED') || payload['isCallActive'] == false)) {
      unawaited(_clearSession());
      return;
    }
    final kind = isCall
        ? _SessionKind.call
        : (rawKind == 'media' ||
                  targetType == 'image' ||
                  targetType == 'video' ||
                  targetType == 'text' ||
                  targetType == 'voice')
            ? _SessionKind.media
            : _SessionKind.url;
    final status = (payload['status']?.toString() ?? _session.status).toUpperCase();
    final rawScore = payload['riskScore'] ?? payload['score'];
    final score = rawScore is num
        ? ((rawScore.toDouble() > 1) ? rawScore.toDouble() / 100 : rawScore.toDouble()).clamp(0.0, 1.0)
        : _session.riskScore;
    final mediaKind = payload['mediaKind']?.toString() ?? _session.mediaKind;
    if (!isCall &&
        kind == _SessionKind.media &&
        ((mediaKind == 'video_frame' && !_videoDetectionEnabled) ||
            (mediaKind == 'image_frame' && !_imageDetectionEnabled) ||
            (mediaKind == 'screen_fallback' &&
                !_imageDetectionEnabled &&
                !_videoDetectionEnabled))) {
      return;
    }
    if (!isCall &&
        sourcePackage.isNotEmpty &&
        _foregroundPackage != null &&
        _foregroundPackage != sourcePackage &&
        sourcePackage != 'com.example.risk_guard') {
      return;
    }
    final next = _Session(
      id: payload['sessionId']?.toString() ?? payload['requestId']?.toString() ?? '${kind.name}-${DateTime.now().millisecondsSinceEpoch}',
      kind: kind,
      state: status.contains('VERIFY') || status.contains('ANALYZ') ? _SessionState.verifying : (status.contains('ERROR') || status.contains('DEGRADE') ? _SessionState.degraded : _SessionState.ready),
      sourcePackage: sourcePackage,
      targetType: (payload['targetType']?.toString() ?? _session.targetType).toUpperCase(),
      target: kind == _SessionKind.media
          ? (payload['targetLabel']?.toString() ?? _labelForMediaKind(mediaKind))
          : (payload['targetLabel']?.toString() ?? payload['url']?.toString() ?? payload['target']?.toString() ?? _session.target),
      status: status,
      summary: payload['threatText']?.toString() ?? payload['summary']?.toString() ?? _session.summary,
      recommendation: payload['recommendation']?.toString() ?? _session.recommendation,
      intelSource: (payload['analysisSource']?.toString() ?? payload['intelSource']?.toString() ?? _session.intelSource).toUpperCase(),
      threatType: payload['threatType']?.toString() ?? _session.threatType,
      phoneNumber: payload['phoneNumber']?.toString() ?? _session.phoneNumber,
      riskScore: score,
      isThreat: payload['isThreat'] == true || status.contains('DANGER') || status.contains('MALICIOUS'),
      previewPath: payload['previewPath']?.toString() ?? payload['localFramePath']?.toString() ?? _session.previewPath,
      mediaKind: mediaKind,
      selectionConfidence:
          ((payload['selectionConfidence'] as num?)?.toDouble() ??
                  _session.selectionConfidence)
              .clamp(0.0, 1.0),
      captureStage: payload['captureStage']?.toString() ?? _session.captureStage,
    );
    _interactiveCaptureUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _setSession(next);
    unawaited(_syncSurface());
    if (next.kind != _SessionKind.call && !_isAnalyzing) _scheduleDismiss(next.id);
  }

  void _applyPolicyUpdate(Map<String, dynamic> payload) {
    _protectionActive = payload['isProtectionActive'] != false;
    _voiceDetectionEnabled = payload['voiceDetectionEnabled'] != false;
    _imageDetectionEnabled = payload['imageDetectionEnabled'] != false;
    _textDetectionEnabled = payload['textDetectionEnabled'] != false;
    _videoDetectionEnabled = payload['videoDetectionEnabled'] != false;
    _callMonitoringEnabled = payload['callMonitoringEnabled'] != false;

    if (!_protectionActive) {
      unawaited(_clearSession());
      return;
    }
    if (!_callMonitoringEnabled && _session.kind == _SessionKind.call) {
      _callExpanded = false;
      unawaited(_clearSession());
      return;
    }
    if (!_imageDetectionEnabled && !_videoDetectionEnabled && _session.kind == _SessionKind.media) {
      unawaited(_clearSession());
      return;
    }
    unawaited(_syncSurface());
  }

  String _labelForMediaKind(String mediaKind) {
    switch (mediaKind) {
      case 'video_frame':
        return 'Dominant visible video';
      case 'image_frame':
        return 'Dominant visible image';
      default:
        return 'Screen fallback';
    }
  }

  String _typeForMediaKind(String mediaKind) {
    switch (mediaKind) {
      case 'video_frame':
        return 'VIDEO FRAME';
      case 'image_frame':
        return 'IMAGE FRAME';
      default:
        return 'SCREEN FALLBACK';
    }
  }

  String _threatTypeForMediaKind(String mediaKind) {
    switch (mediaKind) {
      case 'video_frame':
        return 'Video Deepfake';
      case 'image_frame':
        return 'Image Deepfake';
      default:
        return 'Screen Media';
    }
  }

  void _scheduleVideoBurst(String sessionId, String sourcePackage) {
    if (_scheduledBurstSessions.contains(sessionId)) return;
    _scheduledBurstSessions.add(sessionId);
    for (final delay in const [
      Duration(milliseconds: 520),
      Duration(milliseconds: 1040),
      Duration(milliseconds: 1560),
    ]) {
      unawaited(
        Future<void>.delayed(delay, () async {
          if (!mounted) return;
          if (_session.id != sessionId || _session.kind != _SessionKind.media) {
            return;
          }
          if (!_videoDetectionEnabled || sourcePackage.isEmpty) {
            return;
          }
          await NativeBridge.requestRealtimeMediaCapture(
            sourcePackage: sourcePackage,
            reason: 'burst_followup',
            sessionId: sessionId,
            captureStage: 'burst_followup',
          );
        }),
      );
    }
  }

  void _scheduleDismiss(String sessionId) {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(seconds: 4), () async {
      if (!mounted || _session.id != sessionId || _isAnalyzing || _session.kind == _SessionKind.call) return;
      await _clearSession();
    });
  }

  Future<void> _clearSession() async {
    _dismissTimer?.cancel();
    _collapsedSessionId = null;
    _interactiveCaptureUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _callExpanded = false;
    _cardExpanded = false;
    _dragPosition = null;
    _bubbleDragged = false;
    _callChipDragged = false;
    _callPanelDragged = false;
    _scheduledBurstSessions.clear();
    _setSession(const _Session.idle());
    await _syncSurface();
  }

  void _setSession(_Session next) {
    if (_collapsedSessionId != null && _collapsedSessionId != next.id) {
      _collapsedSessionId = null;
    }
    // Automatically collapse if the session identity changes significantly
    if (_session.id.isNotEmpty && next.id != _session.id) {
      _cardExpanded = false;
    }
    final previousPreview = _session.previewPath;
    final nextPreview = next.previewPath;
    if (mounted) {
      setState(() => _session = next);
    } else {
      _session = next;
    }
    if (next.kind == _SessionKind.call) {
      _ensureWaveTimer();
    } else {
      _stopWaveTimer();
    }
    if (previousPreview != null &&
        previousPreview.isNotEmpty &&
        previousPreview != nextPreview) {
      _cleanupPreview(previousPreview);
    }
  }

  void _ensureWaveTimer() {
    _waveTimer ??= Timer.periodic(const Duration(milliseconds: 220), (_) {
      if (!mounted) return;
      if (_session.kind != _SessionKind.call) return;
      setState(() => _wavePhase = (_wavePhase + 1) % 12);
    });
  }

  void _stopWaveTimer() {
    _waveTimer?.cancel();
    _waveTimer = null;
    _wavePhase = 0;
  }

  Future<void> _syncSurface() async {
    final desired = (_session.kind == _SessionKind.call)
        ? _OverlaySurface.call
        : (_cardAllowed ? _OverlaySurface.card : (_bubbleAllowed ? _OverlaySurface.bubble : _OverlaySurface.hidden));

    if (_isSurfacePinned &&
        _surface == _OverlaySurface.card &&
        desired != _OverlaySurface.call) {
      return;
    }
    // Anti-flicker: if actively analyzing, do not hide the overlay
    if (_isAnalyzing && desired == _OverlaySurface.hidden) {
      return;
    }
    // Anti-flicker: if a surface transition happened very recently, skip this
    // one to prevent rapid bubble→card→bubble→card flips during scrolling
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (desired != _surface && nowMs - _lastSurfaceChangeMs < _surfaceTransitionCooldownMs) {
      return;
    }
    return _setSurface(desired);
  }

  Future<void> _rememberBubblePosition() async {
    try {
      _bubblePosition = await FlutterOverlayWindow.getOverlayPosition();
    } catch (_) {}
  }

  OverlayPosition _defaultBubblePosition() {
    final double maxX = math.max(12.0, _viewportSize.width - _bubbleSize - 12).toDouble();
    final double maxY = math.max(120.0, _viewportSize.height - _bubbleSize - 24).toDouble();
    final double x = maxX;
    final y = (_viewportSize.height * 0.34).clamp(120.0, maxY).toDouble();
    return OverlayPosition(x, y);
  }


  Future<void> _restoreBubblePosition() async {
    try {
      await FlutterOverlayWindow.moveOverlay(_bubblePosition ?? _defaultBubblePosition());
    } catch (_) {}
  }

  OverlayPosition _clampBubblePosition(OverlayPosition position) {
    // Keep bubble fully visible: at least 8px safe from every edge.
    const double margin = 8.0;
    final double maxX = (_viewportSize.width - _bubbleSize - margin).clamp(margin, double.infinity);
    final double maxY = (_viewportSize.height - _bubbleSize - margin).clamp(margin, double.infinity);
    return OverlayPosition(
      position.x.clamp(margin, maxX).toDouble(),
      position.y.clamp(margin, maxY).toDouble(),
    );
  }

  // INSTANT drag start — seed from cache, fire async fetch in background
  // so the very first move event has a valid position without waiting.
  void _beginBubbleDragSync() {
    _bubbleDragged = false;
    // Use last known position immediately — zero latency
    _dragPosition = _bubblePosition ?? _defaultBubblePosition();
    // Background refresh for next drag (does not block current drag)
    FlutterOverlayWindow.getOverlayPosition().then((pos) {
      if (_dragPosition != null) return; // drag already in progress, keep it
      _bubblePosition = _clampBubblePosition(pos);
    }).catchError((_) {});
  }

  void _updateBubbleDragSync(DragUpdateDetails details) {
    if (_surfaceTransitioning) return;
    if (details.delta.distanceSquared > _dragThresholdSq) {
      _bubbleDragged = true;
      _suppressBubbleTap();
    }
    final current = _dragPosition ?? _bubblePosition ?? _defaultBubblePosition();
    final next = _clampBubblePosition(
      OverlayPosition(
        current.x + details.delta.dx,
        current.y + details.delta.dy,
      ),
    );
    _dragPosition = next;
    _bubblePosition = next; // Update cache immediately for next event
    _throttledMove(next);
  }

  void _endBubbleDrag() {
    final position = _dragPosition ?? _bubblePosition;
    if (position != null) {
      // Snap X to the nearest edge (left/right) — keep exact Y the user left it
      final double rightEdge = (_viewportSize.width - _bubbleSize - 8.0).clamp(8.0, double.infinity);
      const double leftEdge = 8.0;
      final double snappedX = position.x < (_viewportSize.width / 2) ? leftEdge : rightEdge;
      final snapped = _clampBubblePosition(OverlayPosition(snappedX, position.y));
      _bubblePosition = snapped;
      unawaited(FlutterOverlayWindow.moveOverlay(snapped));
      _savePositions(); // Persist for 24-hr memory
    }
    _dragPosition = null;
  }

  Future<void> _moveCardToCenter() async {
    final double width = math.max(
      280.0,
      _viewportSize.width < 420 ? _viewportSize.width - 24 : _cardWidth,
    ).toDouble();
    // Default expanded view: horizontally centered, vertically above center (~28% down)
    // Same philosophy as call panel to keep bottom of screen clear.
    final double x = ((_viewportSize.width - width) / 2).clamp(12.0, _viewportSize.width - width - 12).toDouble();
    final double y = (_viewportSize.height * 0.28).clamp(32.0, _viewportSize.height * 0.45).toDouble();
    try {
      await FlutterOverlayWindow.moveOverlay(OverlayPosition(x, y));
    } catch (_) {}
  }

  OverlayPosition _callChipPosition() {
    // Safe-but-free: chip stays within visible screen with 8px margin.
    const double margin = 8.0;
    final double maxX = (_viewportSize.width - _callChipWidth - margin).clamp(margin, double.infinity);
    final double maxY = (_viewportSize.height - _callChipHeight - margin).clamp(margin, double.infinity);
    double x;
    if (_callChipX >= 0) {
      x = _callChipX.clamp(margin, maxX);
    } else {
      // First-show: default anchored positions
      if (_callChipAnchor == _CallChipAnchor.left) {
        x = margin;
      } else if (_callChipAnchor == _CallChipAnchor.center) {
        x = ((_viewportSize.width - _callChipWidth) / 2).clamp(margin, maxX);
      } else {
        x = maxX;
      }
    }
    final double y = _callChipY.clamp(margin, maxY);
    return OverlayPosition(x, y);
  }

  OverlayPosition _defaultCallPanelPosition() {
    final double callWidth =
        math.min(_viewportSize.width - 24, _callPanelWidth).toDouble();
    // Default: horizontally centered, vertically at ~28% from top.
    // This keeps the bottom 55%+ (where native call controls live:
    // mute, hold, speaker, end-call, keypad) fully accessible to the user.
    final double x = ((_viewportSize.width - callWidth) / 2).clamp(12.0, _viewportSize.width - callWidth - 12).toDouble();
    final double y = (_viewportSize.height * 0.28).clamp(56.0, _viewportSize.height * 0.48).toDouble();
    return OverlayPosition(x, y);
  }

  OverlayPosition _clampCallPanelPosition(OverlayPosition position) {
    // Keep panel fully visible with 8px margin
    const double margin = 8.0;
    final double panelW = math.min(_viewportSize.width - 24, _callPanelWidth).toDouble();
    final double panelH = math.min(_viewportSize.height - 120, _callPanelHeight).toDouble();
    final double maxX = (_viewportSize.width - panelW - margin).clamp(margin, double.infinity);
    final double maxY = (_viewportSize.height - panelH - margin).clamp(margin, double.infinity);
    return OverlayPosition(
      position.x.clamp(margin, maxX).toDouble(),
      position.y.clamp(margin, maxY).toDouble(),
    );
  }

  Future<void> _moveCallChipToAnchor() async {
    try {
      await FlutterOverlayWindow.moveOverlay(_callChipPosition());
    } catch (_) {}
  }

  Future<void> _moveCallToAnchor() async {
    if (!_callExpanded) {
      await _moveCallChipToAnchor();
      return;
    }
    try {
      await FlutterOverlayWindow.moveOverlay(
        _clampCallPanelPosition(
          _callPanelPosition ?? _defaultCallPanelPosition(),
        ),
      );
    } catch (_) {}
  }

  Future<void> _expandCallCompanion() async {
    _callExpanded = true;
    // 1. Resize the overlay window to the call panel size first
    final double callWidth  = math.min(_viewportSize.width - 24, _callPanelWidth).toDouble();
    final double callHeight = math.min(_viewportSize.height - 120, _callPanelHeight).toDouble();
    _lastSetWidth  = callWidth.toInt();
    _lastSetHeight = callHeight.toInt();
    try {
      await FlutterOverlayWindow.resizeOverlay(callWidth.toInt(), callHeight.toInt(), false);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 60));
    // 2. Rebuild UI (paints the expanded panel)
    if (mounted) setState(() {});
    // 3. Move to default center position (respects native call controls below)
    final pos = _clampCallPanelPosition(_callPanelPosition ?? _defaultCallPanelPosition());
    _callPanelPosition = pos;
    try {
      await FlutterOverlayWindow.moveOverlay(pos);
    } catch (_) {}
  }

  Future<void> _collapseCallCompanion() async {
    _callExpanded = false;
    // 1. Resize back to chip size
    _lastSetWidth  = _callChipWidth.toInt();
    _lastSetHeight = _callChipHeight.toInt();
    try {
      await FlutterOverlayWindow.resizeOverlay(_callChipWidth.toInt(), _callChipHeight.toInt(), false);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 60));
    // 2. Rebuild UI (paints the compact chip)
    if (mounted) setState(() {});
    // 3. Move back to chip position
    try {
      await FlutterOverlayWindow.moveOverlay(_callChipPosition());
    } catch (_) {}
  }

  // INSTANT call chip drag — no async wait, seeded from last known position
  void _beginCallChipDragSync() {
    _callChipDragged = false;
    _dragPosition = _callChipLastPosition ?? _callChipPosition();
  }

  void _updateCallChipDragSync(DragUpdateDetails details) {
    // Allow drag even when expanded (so expanded panel can be moved)
    if (_surfaceTransitioning) return; // Only block during actual resize transitions
    if (details.delta.distanceSquared > _dragThresholdSq) {
      _callChipDragged = true;
      _suppressCallTap();
    }
    final current = _dragPosition ?? _callChipLastPosition ?? _callChipPosition();
    // Clamp within screen with 8px safety margin — no disappearing
    const double margin = 8.0;
    final double maxX = (_viewportSize.width - _callChipWidth - margin).clamp(margin, double.infinity);
    final double maxY = (_viewportSize.height - _callChipHeight - margin).clamp(margin, double.infinity);
    final next = OverlayPosition(
      (current.x + details.delta.dx).clamp(margin, maxX).toDouble(),
      (current.y + details.delta.dy).clamp(margin, maxY).toDouble(),
    );
    _dragPosition = next;
    _callChipLastPosition = next; // Cache for instant next drag start
    _throttledMove(next);
  }

  void _endCallChipDrag() {
    if (_callExpanded) return;
    final position = _dragPosition ?? _callChipLastPosition ?? _callChipPosition();
    // Store clamped released position — stays within visible screen
    const double margin = 8.0;
    final double maxX = (_viewportSize.width - _callChipWidth - margin).clamp(margin, double.infinity);
    final double maxY = (_viewportSize.height - _callChipHeight - margin).clamp(margin, double.infinity);
    _callChipX = position.x.clamp(margin, maxX).toDouble();
    _callChipY = position.y.clamp(margin, maxY).toDouble();
    // Update anchor bookkeeping (used only for first-show default position)
    final third = _viewportSize.width / 3;
    _callChipAnchor = _callChipX < third
        ? _CallChipAnchor.left
        : (_callChipX > third * 1.8 ? _CallChipAnchor.right : _CallChipAnchor.center);
    final exact = OverlayPosition(_callChipX, _callChipY);
    _callChipLastPosition = exact;
    _dragPosition = null;
    unawaited(FlutterOverlayWindow.moveOverlay(exact));
    _savePositions();
  }

  // INSTANT call panel drag — seeded from cache, no async wait
  void _beginCallPanelDragSync() {
    if (!_callExpanded) return;
    _callPanelDragged = false;
    _dragPosition = _callPanelPosition ?? _defaultCallPanelPosition();
  }

  void _updateCallPanelDragSync(DragUpdateDetails details) {
    if (!_callExpanded) return;
    // Do NOT check _surfaceTransitioning here — panel drag should always work
    if (details.delta.distanceSquared > _dragThresholdSq) {
      _callPanelDragged = true;
      _suppressCallTap(const Duration(milliseconds: 180));
    }
    final current = _dragPosition ?? _callPanelPosition ?? _defaultCallPanelPosition();
    final next = _clampCallPanelPosition(
      OverlayPosition(
        current.x + details.delta.dx,
        current.y + details.delta.dy,
      ),
    );
    _dragPosition = next;
    _callPanelPosition = next; // Cache immediately
    _throttledMove(next);
  }

  void _endCallPanelDrag() {
    if (!_callExpanded) return;
    final position = _dragPosition ?? _callPanelPosition;
    if (position != null) {
      // No clamping — store exact released position, fully unconstrained
      _callPanelPosition = position;
      unawaited(FlutterOverlayWindow.moveOverlay(position));
      // Persist for 24-hour memory
      _savePositions();
    }
    _dragPosition = null;
  }

  /// Fire-and-forget overlay move with 60fps throttle guard.
  /// Pure temporal throttle — no async backpressure, no blocking.
  void _throttledMove(OverlayPosition position) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - _lastMoveMs) < _moveCooldownMs) return;
    _lastMoveMs = now;
    // unawaited: move fires instantly without blocking the drag callback
    unawaited(FlutterOverlayWindow.moveOverlay(position));
  }

  Future<void> _expandFromBubble() async {
    await _rememberBubblePosition();
    _collapsedSessionId = null;
    if (_session.kind == _SessionKind.call) {
      _pinSurface(const Duration(seconds: 2));
      await _setSurface(_OverlaySurface.call);
      return;
    }
    if (_cardEligible) {
      _pinSurface(const Duration(seconds: 2));
      _cardExpanded = true;
      await _setSurface(_OverlaySurface.card);
      return;
    }
    if (_foregroundWhitelisted &&
        _foregroundPackage != null &&
        _foregroundPackage!.isNotEmpty) {
      _interactiveCaptureUntil = DateTime.now().add(
        const Duration(seconds: 2),
      );
      if (mounted) {
        setState(() {});
      }
      unawaited(
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          if (!_waitingForInteractiveCapture) return;
          setState(() {});
        }),
      );
      _pinSurface(const Duration(milliseconds: 1200));
      final requested = await NativeBridge.requestRealtimeMediaCapture(
        sourcePackage: _foregroundPackage,
        reason: 'bubble_expand',
      );
      if (!requested) {
        _interactiveCaptureUntil = DateTime.fromMillisecondsSinceEpoch(0);
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  Future<void> _setSurface(_OverlaySurface next) async {
    final sameSurface = _surface == next;
    if (mounted) {
      setState(() => _surface = next);
    } else {
      _surface = next;
    }

    if (sameSurface) {
      if (next == _OverlaySurface.card) {
        await _moveCardToCenter();
      } else if (next == _OverlaySurface.call) {
        final double callWidth =
            (_callExpanded
                    ? math.min(_viewportSize.width - 24, _callPanelWidth)
                    : _callChipWidth)
                .toDouble();
        final double callHeight =
            (_callExpanded
                    ? math.min(_viewportSize.height - 120, _callPanelHeight)
                    : _callChipHeight)
                .toDouble();
        if (_lastSetWidth != callWidth.toInt() || _lastSetHeight != callHeight.toInt()) {
          _lastSetWidth = callWidth.toInt();
          _lastSetHeight = callHeight.toInt();
          await FlutterOverlayWindow.resizeOverlay(
            callWidth.toInt(),
            callHeight.toInt(),
            false,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await _moveCallToAnchor();
      }
      return;
    }

    // Record the transition timestamp — used by _syncSurface cooldown guard
    _lastSurfaceChangeMs = DateTime.now().millisecondsSinceEpoch;
    // Block drag operations while the overlay is resizing/repositioning
    _surfaceTransitioning = true;
    try {
      switch (next) {
        case _OverlaySurface.hidden:
          {
            await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
            await FlutterOverlayWindow.resizeOverlay(1, 1, false);
            break;
          }
        case _OverlaySurface.bubble:
          {
            // Dedup guard: if bubble was resized very recently, skip the
            // physical resize (prevents double-resize flicker during fast
            // scroll-triggered surface toggles)
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            final skipResize =
                _lastResizeSurface == _OverlaySurface.bubble &&
                    (nowMs - _lastResizeMs) < _resizeDedupMs;
            await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
            if (!skipResize && (_lastSetWidth != _bubbleSize.toInt() || _lastSetHeight != _bubbleSize.toInt())) {
              _lastSetWidth = _bubbleSize.toInt();
              _lastSetHeight = _bubbleSize.toInt();
              _lastResizeMs = nowMs;
              _lastResizeSurface = _OverlaySurface.bubble;
              await FlutterOverlayWindow.resizeOverlay(
                  _bubbleSize.toInt(), _bubbleSize.toInt(), true);
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await _restoreBubblePosition();
            break;
          }
        case _OverlaySurface.card:
          {
            final double cardWidth = math.max(
              280.0,
              _viewportSize.width < 420
                  ? _viewportSize.width - 24
                  : _cardWidth,
            ).toDouble();
            if (_lastSetWidth != cardWidth.toInt() || _lastSetHeight != _cardHeight.toInt()) {
              _lastSetWidth = cardWidth.toInt();
              _lastSetHeight = _cardHeight.toInt();
              await FlutterOverlayWindow.resizeOverlay(
                cardWidth.toInt(),
                _cardHeight.toInt(),
                false,
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await _moveCardToCenter();
            break;
          }
        case _OverlaySurface.call:
          {
            final double callWidth =
                (_callExpanded
                        ? math.min(_viewportSize.width - 24, _callPanelWidth)
                        : _callChipWidth)
                    .toDouble();
            final double callHeight =
                (_callExpanded
                        ? math.min(
                            _viewportSize.height - 120, _callPanelHeight)
                        : _callChipHeight)
                    .toDouble();
            if (_lastSetWidth != callWidth.toInt() || _lastSetHeight != callHeight.toInt()) {
              _lastSetWidth = callWidth.toInt();
              _lastSetHeight = callHeight.toInt();
              await FlutterOverlayWindow.resizeOverlay(
                callWidth.toInt(),
                callHeight.toInt(),
                false,
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await _moveCallToAnchor();
            break;
          }
      }
    } finally {
      _surfaceTransitioning = false;
    }
    _schedulePoll();
  }


  Future<void> _minimize() async {
    if (_session.kind == _SessionKind.url || _session.kind == _SessionKind.media) {
      _collapsedSessionId = _session.id;
    }
    await _rememberBubblePosition();
    await _setSurface(_bubbleAllowed ? _OverlaySurface.bubble : _OverlaySurface.hidden);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _dismissTimer?.cancel();
    _visibilityHideTimer?.cancel();
    _waveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    _viewportSize = Size(
      view.display.size.width / view.display.devicePixelRatio,
      view.display.size.height / view.display.devicePixelRatio,
    );
    if (_surface == _OverlaySurface.hidden) {
      return const Material(color: Colors.transparent, child: SizedBox.shrink());
    }
    return Material(
      color: Colors.transparent,
      child: _surface == _OverlaySurface.call ? _buildCall() : (_surface == _OverlaySurface.bubble ? _buildBubble() : _buildCard()),
    );
  }

  Widget _buildBubble() {
    final waitingForCapture =
        _waitingForInteractiveCapture && _session.kind == _SessionKind.none;
    final accent = waitingForCapture
        ? Colors.orangeAccent
        : (_session.isThreat ? Colors.redAccent : Colors.cyanAccent);
    final canExpand = _canExpandFromBubble;
    final previewPath = _session.previewPath;
    final hasPreview =
        _session.kind == _SessionKind.media &&
        previewPath != null &&
        previewPath.isNotEmpty &&
        // Accept both file-based and base64 previews
        (previewPath.startsWith('b64:') || File(previewPath).existsSync());
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTapUp: (_) {
        if (DateTime.now().isBefore(_bubbleTapSuppressedUntil)) {
          _bubbleDragged = false;
          return;
        }
        if (canExpand && !_bubbleDragged) {
          unawaited(_expandFromBubble());
        }
        _bubbleDragged = false;
      },
      // Use synchronous drag start — zero latency, finger-attached movement
      onPanStart: (_) => _beginBubbleDragSync(),
      onPanUpdate: (details) => _updateBubbleDragSync(details),
      onPanEnd: (_) {
        _endBubbleDrag();
        _bubbleDragged = false;
      },
      onPanCancel: () {
        _endBubbleDrag();
        _bubbleDragged = false;
      },
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF071120).withValues(alpha: 0.96),
          shape: BoxShape.circle,
          border: Border.all(color: accent.withValues(alpha: 0.75), width: 2),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.22), blurRadius: 18)],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (hasPreview)
              ClipOval(
                child: SizedBox.expand(
                  child: Image.file(
                    File(previewPath),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              )
            else
              Icon(_session.isThreat ? Icons.warning_rounded : Icons.shield_rounded, color: accent, size: 28),
            if (hasPreview)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.32),
                ),
              ),
            if (hasPreview)
              Icon(
                _session.isThreat ? Icons.warning_rounded : Icons.photo_camera_back_rounded,
                color: Colors.white,
                size: 20,
              ),
            if (!_isAnalyzing && _session.riskScore > 0.01)
              Positioned(
                top: 10,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${(_session.riskScore * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (waitingForCapture)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.45)),
                  ),
                  child: const Text(
                    'SCAN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            Positioned(bottom: 16, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: _isAnalyzing ? Colors.orangeAccent : accent, shape: BoxShape.circle))),
          ],
        ),
      ),
    );
  }

  Widget _buildCard() {
    final accent = _session.isThreat ? Colors.redAccent : Colors.cyanAccent;
    return SafeArea(
      child: Center(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(colors: [const Color(0xFF08111D).withValues(alpha: 0.97), const Color(0xFF0F172A).withValues(alpha: 0.97)]),
            border: Border.all(color: accent.withValues(alpha: 0.34), width: 1.5),
            boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 28)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 22, backgroundColor: accent.withValues(alpha: 0.14), child: Icon(_session.isThreat ? Icons.gpp_bad_rounded : Icons.gpp_good_rounded, color: accent)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('RISKGUARD PROACTIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.8)),
                Text(_appName(_session.sourcePackage), style: TextStyle(color: Colors.white.withValues(alpha: 0.58), fontSize: 12)),
              ])),
              IconButton(onPressed: _minimize, icon: const Icon(Icons.remove_rounded, color: Colors.white70)),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(
                  _isAnalyzing
                      ? 'VERIFYING'
                      : (_session.isThreat ? 'DANGER' : 'SAFE'),
                  accent,
                ),
                _pill(_session.targetType, Colors.white70),
                _pill(_session.intelSource, Colors.orangeAccent),
                if (_session.kind == _SessionKind.media)
                  _pill(
                    '${(_session.selectionConfidence * 100).round()}% PICK',
                    Colors.white60,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_session.kind == _SessionKind.media) ...[
              // Show shimmer while analyzing (no preview yet) or render preview
              if (_isAnalyzing && (_session.previewPath == null || _session.previewPath!.isEmpty))
                _previewShimmer()
              else if (_session.previewPath != null && _session.previewPath!.isNotEmpty)
                _buildMediaPreview(_session.previewPath!, accent),
              const SizedBox(height: 12),
            ],
            _info('Captured target', _session.target),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _isAnalyzing ? null : (_session.riskScore > 0 ? _session.riskScore : 0.04), backgroundColor: Colors.white12, color: accent, minHeight: 8, borderRadius: BorderRadius.circular(999)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text(_session.status, style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13))),
              Text('${(_session.riskScore * 100).round()}% score', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            _info(_session.threatType, _session.summary, footer: _session.recommendation),
          ]),
        ),
      ),
    );
  }

  Widget _buildCall() {
    final accent = _session.riskScore >= 0.65 ? Colors.redAccent : Colors.cyanAccent;
    final scoreLabel = '${(_session.riskScore * 100).round()}%';
    final isIncoming = _session.status == 'INCOMING';
    final headline = () {
      if (isIncoming) return 'Incoming caller profile';
      if (_session.riskScore >= 0.7) return 'Elevated synthetic-voice risk';
      if (_session.riskScore >= 0.35) return 'Voice pattern under review';
      return 'Live voice stream stable';
    }();
    final body = () {
      if (isIncoming) {
        return 'Preparing the first caller profile before the conversation settles into a stable voice stream.';
      }
      if (_session.riskScore >= 0.7) {
        return 'Multiple synthetic-voice indicators are active. Keep the caller talking and verify identity through another trusted channel.';
      }
      if (_session.riskScore >= 0.35) {
        return 'RiskGuard is seeing mixed voice signals. Hold the same call view for a stronger verdict over the next few live chunks.';
      }
      return 'RiskGuard is quietly sampling the live call in the background while leaving the native phone controls available.';
    }();
    if (!_callExpanded) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onTapUp: (_) {
          if (DateTime.now().isBefore(_callTapSuppressedUntil)) {
            _callChipDragged = false;
            return;
          }
          if (!_callChipDragged) {
            unawaited(_expandCallCompanion());
          }
          _callChipDragged = false;
        },
        // Synchronous drag — finger-attached, zero-latency
        onPanStart: (_) => _beginCallChipDragSync(),
        onPanUpdate: (details) => _updateCallChipDragSync(details),
        onPanEnd: (_) {
          _endCallChipDrag();
          _callChipDragged = false;
        },
        onPanCancel: () {
          _endCallChipDrag();
          _callChipDragged = false;
        },
        child: Container(
          height: _callChipHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xF20A1320), Color(0xF2142232)],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.28), width: 1.2),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 18),
              BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 14),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.16),
                ),
                child: Icon(Icons.call_rounded, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isIncoming ? 'Incoming call watch' : 'Live call companion',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$scoreLabel risk | ${_session.phoneNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildCallWaveform(accent, compact: true),
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_up_rounded,
                color: Colors.white70,
              ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      // Synchronous drag for expanded call panel — butter-smooth
      onPanStart: (_) => _beginCallPanelDragSync(),
      onPanUpdate: (details) => _updateCallPanelDragSync(details),
      onPanEnd: (_) => _endCallPanelDrag(),
      onPanCancel: _endCallPanelDrag,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF20A1320), Color(0xF2101A28)],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.28), width: 1.4),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.32), blurRadius: 22),
            BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 16),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _pill('CALL COMPANION', accent),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isIncoming ? 'INCOMING' : 'LIVE STREAM',
                    style: TextStyle(
                      color: accent,
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.drag_handle_rounded,
                  color: Colors.white.withValues(alpha: 0.34),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _collapseCallCompanion,
                  icon: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.12),
                    border: Border.all(color: accent.withValues(alpha: 0.18)),
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    size: 24,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _session.phoneNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 50,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withValues(alpha: 0.14)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        scoreLabel,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        'risk',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 9,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildCallWaveform(accent),
            const SizedBox(height: 10),
            Text(
              body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.graphic_eq_rounded, color: accent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        isIncoming ? 'Profiling caller' : 'Monitoring live voice',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  _session.intelSource,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallWaveform(Color accent, {bool compact = false}) {
    final barCount = compact ? 8 : 12;
    final baseHeight = compact ? 7.0 : 10.0;
    final peakHeight = compact ? 15.0 : 28.0;
    final riskBoost = (_session.riskScore * (compact ? 3.5 : 6.0));
    final activityBias = _session.status == 'INCOMING' ? 0.55 : 0.85;
    final liveBars = List<Widget>.generate(barCount, (index) {
      final phase = (_wavePhase / 12) * math.pi * 2;
      final waveA = (math.sin(phase + (index * 0.55)) + 1) / 2;
      final waveB = (math.cos((phase * 0.7) - (index * 0.42)) + 1) / 2;
      final blend = ((waveA * 0.62) + (waveB * 0.38)) * activityBias;
      final height = baseHeight + (peakHeight * blend) + riskBoost;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: compact ? 3 : 4,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              accent.withValues(alpha: index.isEven ? 0.48 : 0.28),
              accent.withValues(alpha: index.isEven ? 0.98 : 0.74),
            ],
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: compact
              ? null
              : [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.18),
                    blurRadius: 10,
                  ),
                ],
        ),
      );
    });

    return Container(
      width: compact ? 44 : double.infinity,
      height: compact ? 26 : 50,
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: compact ? 0 : 8),
      decoration: compact
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.04),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: compact
            ? MainAxisAlignment.end
            : MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: liveBars,
      ),
    );
  }

  /// Animated shimmer shown while media analysis is in progress.
  Widget _previewShimmer() => Shimmer.fromColors(
    baseColor: const Color(0xFF1A2332),
    highlightColor: const Color(0xFF263447),
    child: Container(
      height: 108,
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(18),
      ),
    ),
  );

  /// Renders a media preview from either a b64 string (b64:<data>) or a file path.
  Widget _buildMediaPreview(String previewPath, Color accent) {
    // Determine image source: base64 from backend or local temp file
    Widget imageWidget;
    if (previewPath.startsWith('b64:')) {
      // Backend-supplied base64 thumbnail — never breaks, no file dependency
      try {
        final bytes = base64Decode(previewPath.substring(4));
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
        );
      } catch (_) {
        imageWidget = _previewShimmer();
      }
    } else {
      // Local temp file fallback
      final file = File(previewPath);
      imageWidget = file.existsSync()
          ? Image.file(file, fit: BoxFit.contain, filterQuality: FilterQuality.low)
          : _previewShimmer();
    }

    return Container(
      height: 108,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        color: const Color(0xFF0B1624),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF0B1624)),
            imageWidget,
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _session.mediaKind == 'video_frame'
                      ? 'VIDEO PREVIEW'
                      : (_session.mediaKind == 'image_frame'
                          ? 'IMAGE PREVIEW'
                          : 'SCREEN PREVIEW'),
                  style: const TextStyle(
                    color: Colors.white, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10, right: 10, bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.16)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_labelForMediaKind(_session.mediaKind)} — ${_session.target}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${(_session.selectionConfidence * 100).round()}% match',
                      style: TextStyle(
                        color: accent, fontSize: 10,
                        fontWeight: FontWeight.w700, letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withValues(alpha: 0.24))),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
  );

  Widget _info(String title, String body, {String? footer, Color? accent, bool expand = false}) {
    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: (accent ?? Colors.white).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: [
        Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Text(body, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35)),
        if (footer != null) ...[
          const SizedBox(height: 8),
          Text(footer, style: TextStyle(color: Colors.white.withValues(alpha: 0.68), fontSize: 12, height: 1.35)),
        ],
      ]),
    );
    return expand ? Expanded(child: child) : child;
  }
}
