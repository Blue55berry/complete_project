/// API configuration — centralized endpoints & dynamic base URL.
/// The base URL can be changed at runtime (e.g., to a cloudflared tunnel URL)
/// and is persisted in Hive so it survives app restarts.
library;
import 'package:hive_flutter/hive_flutter.dart';

class ApiConfig {
  ApiConfig._();

  // ── Dynamic Base URL ────────────────────────────────────────────────────────
  static const String _boxName = 'user_settings';
  static const String _urlKey = 'backend_url';
  static const String defaultUrl = 'http://127.0.0.1:8000';

  static String _cachedUrl = defaultUrl;
  static final RegExp _ipv4WithPort = RegExp(
    r'^\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?$',
  );

  /// Initialize from Hive (call once at app startup)
  static Future<void> init() async {
    try {
      final box = await Hive.openBox(_boxName);
      _cachedUrl = normalizeBaseUrl(
        box.get(_urlKey, defaultValue: defaultUrl) ?? defaultUrl,
      );
    } catch (_) {
      _cachedUrl = defaultUrl;
    }
  }

  /// Current base URL (reads from cache for speed)
  static String get baseUrl => _cachedUrl;

  /// Update the backend URL and persist to Hive.
  /// This propagates to ALL ApiService calls immediately.
  static Future<void> setBaseUrl(String url) async {
    final normalized = normalizeBaseUrl(url);
    _cachedUrl = normalized;
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_urlKey, normalized);
    } catch (_) {}
  }

  static String normalizeBaseUrl(String url) {
    String normalized = url.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.isEmpty) {
      return defaultUrl;
    }

    final lower = normalized.toLowerCase();
    final hasScheme =
        lower.startsWith('http://') || lower.startsWith('https://');
    if (hasScheme) {
      return normalized;
    }

    final isLocalHost =
        lower.startsWith('localhost') ||
        lower.startsWith('127.0.0.1') ||
        lower.startsWith('10.0.2.2') ||
        _ipv4WithPort.hasMatch(lower);

    return '${isLocalHost ? 'http' : 'https'}://$normalized';
  }

  /// Reset to localhost default
  static Future<void> resetToDefault() async {
    await setBaseUrl(defaultUrl);
  }

  // ── Endpoints ──────────────────────────────────────────────────────────────
  static const String textAnalysis = '/api/v1/analyze/text';
  static const String voiceAnalysis = '/api/v1/analyze/voice';
  static const String voiceRealtime = '/api/v1/analyze/voice/realtime';
  static const String imageAnalysis = '/api/v1/analyze/image';
  static const String realtimeMediaAnalysis = '/api/v1/analyze/media/realtime';
  static const String imageBatch = '/api/v1/analyze/image/batch';
  static const String videoAnalysis = '/api/v1/analyze/video';
  static const String riskCalculate = '/api/v1/score/calculate';
  static const String riskWeights = '/api/v1/score/weights';
  static const String health = '/health';
  static const String status = '/api/v1/status';

  // ── Blockchain Evidence ────────────────────────────────────────────────────
  static const String blockchainReport = '/api/v1/blockchain/report';
  static const String blockchainReports = '/api/v1/blockchain/reports';
  static const String blockchainAnchor = '/api/v1/blockchain/anchor';
  static const String blockchainStatus = '/api/v1/blockchain/status';

  // ── Advanced Intelligence ─────────────────────────────────────────────────
  static const String globalIntel = '/api/v1/intel/global-feed';
  static const String riskMap = '/api/v1/intel/risk-map';
  static const String verifyUrl = '/api/v1/intel/verify-url';

  // ── Timeouts ───────────────────────────────────────────────────────────────
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 120);
  static const Duration healthTimeout = Duration(seconds: 5);
  static const Duration realtimeMediaTimeout = Duration(seconds: 8);
}
