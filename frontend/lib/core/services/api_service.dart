/// Centralized API client for RiskGuard backend communication.
/// Handles JSON POST, multipart file upload, GET, and error handling.
/// Privacy-first: no request payload logging.
library;
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'native_bridge.dart';
import '../models/analysis_models.dart';

// ══════════════════════════════════════════════════════════════════════════════
// API RESULT WRAPPER
// ══════════════════════════════════════════════════════════════════════════════

class ApiResult<T> {
  final T? data;
  final String? error;
  final int? statusCode;

  bool get isSuccess => data != null && error == null;
  bool get isError => error != null;

  ApiResult.success(this.data) : error = null, statusCode = 200;
  ApiResult.failure(this.error, {this.statusCode}) : data = null;
}

// ══════════════════════════════════════════════════════════════════════════════
// API SERVICE (SINGLETON)
// ══════════════════════════════════════════════════════════════════════════════

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  final http.Client _client = http.Client();

  String get _baseUrl => ApiConfig.baseUrl;

  // ── Helpers ────────────────────────────────────────────────────────────────

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> get _jsonHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Parse error message from response body
  String _parseError(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return body['detail'] ??
          body['message'] ??
          'Server error ${response.statusCode}';
    } catch (_) {
      return 'Server error ${response.statusCode}';
    }
  }

  // ── Health ─────────────────────────────────────────────────────────────────

  /// Check if the backend is reachable
  Future<bool> isBackendHealthy() async {
    try {
      final response = await _client
          .get(_uri(ApiConfig.health))
          .timeout(ApiConfig.healthTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Get backend status info
  Future<ApiResult<Map<String, dynamic>>> getStatus() async {
    try {
      final response = await _client
          .get(_uri(ApiConfig.status))
          .timeout(ApiConfig.defaultTimeout);
      if (response.statusCode == 200) {
        return ApiResult.success(jsonDecode(response.body));
      }
      return ApiResult.failure(
        _parseError(response),
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult.failure('Connection failed: ${e.toString()}');
    }
  }

  // ── Text Analysis ──────────────────────────────────────────────────────────

  Future<ApiResult<TextAnalysisResult>> analyzeText(
    String text, {
    bool useCloudAI = true,
  }) async {
    try {
      final response = await _client
          .post(
            _uri(ApiConfig.textAnalysis),
            headers: _jsonHeaders,
            body: jsonEncode({'text': text, 'useCloudAI': useCloudAI}),
          )
          .timeout(ApiConfig.defaultTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResult.success(TextAnalysisResult.fromJson(json));
      }
      return ApiResult.failure(
        _parseError(response),
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult.failure('Text analysis failed: ${e.toString()}');
    }
  }

  // ── Voice Analysis ─────────────────────────────────────────────────────────

  /// Upload full audio file for analysis
  Future<ApiResult<VoiceAnalysisResult>> analyzeVoice(
    Uint8List audioBytes, {
    String filename = 'recording.wav',
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _uri(ApiConfig.voiceAnalysis),
      );
      request.files.add(
        http.MultipartFile.fromBytes('audio', audioBytes, filename: filename),
      );

      final streamedResponse = await _client.send(request).timeout(
        ApiConfig.uploadTimeout,
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResult.success(VoiceAnalysisResult.fromJson(json));
      }
      return ApiResult.failure(
        _parseError(response),
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult.failure('Voice analysis failed: ${e.toString()}');
    }
  }

  /// Send real-time audio chunk for quick analysis
  Future<ApiResult<RealtimeVoiceResult>> analyzeVoiceRealtime(
    Uint8List chunkBytes, {
    int chunkIndex = 0,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _uri(ApiConfig.voiceRealtime),
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'audio',
          chunkBytes,
          filename: 'chunk_$chunkIndex.wav',
        ),
      );

      final streamedResponse = await _client.send(request).timeout(
        ApiConfig.defaultTimeout,
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResult.success(RealtimeVoiceResult.fromJson(json));
      }
      return ApiResult.failure(
        _parseError(response),
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult.failure(
        'Realtime voice analysis failed: ${e.toString()}',
      );
    }
  }

  // ── Image Analysis ─────────────────────────────────────────────────────────

  Future<ApiResult<ImageAnalysisResult>> analyzeImage(
    Uint8List imageBytes, {
    String filename = 'image.png',
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _uri(ApiConfig.imageAnalysis),
      );
      request.files.add(
        http.MultipartFile.fromBytes('image', imageBytes, filename: filename),
      );

      final streamedResponse = await _client.send(request).timeout(
        ApiConfig.uploadTimeout,
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResult.success(ImageAnalysisResult.fromJson(json));
      }
      return ApiResult.failure(
        _parseError(response),
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult.failure('Image analysis failed: ${e.toString()}');
    }
  }

  Future<ApiResult<RealtimeMediaAnalysisResult>> analyzeRealtimeMedia(
    Uint8List imageBytes, {
    required String requestId,
    required String sessionId,
    required String mediaKind,
    required String captureStage,
    required double selectionConfidence,
    required String sourcePackage,
    String capturedAt = '',
    String filename = 'screen_frame.jpg',
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _uri(ApiConfig.realtimeMediaAnalysis),
      );
      request.fields.addAll({
        'requestId': requestId,
        'sessionId': sessionId,
        'mediaKind': mediaKind,
        'captureStage': captureStage,
        'selectionConfidence': selectionConfidence.toString(),
        'sourcePackage': sourcePackage,
        'capturedAt': capturedAt.isNotEmpty
            ? capturedAt
            : DateTime.now().toUtc().toIso8601String(),
      });
      request.files.add(
        http.MultipartFile.fromBytes('image', imageBytes, filename: filename),
      );

      final streamedResponse = await _client
          .send(request)
          .timeout(ApiConfig.realtimeMediaTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResult.success(RealtimeMediaAnalysisResult.fromJson(json));
      }
      return ApiResult.failure(
        _parseError(response),
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult.failure('Realtime media analysis failed: ${e.toString()}');
    }
  }

  // ── Video Analysis ─────────────────────────────────────────────────────────

  Future<ApiResult<VideoAnalysisResult>> analyzeVideo(
    Uint8List videoBytes, {
    String filename = 'video.mp4',
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _uri(ApiConfig.videoAnalysis),
      );
      request.files.add(
        http.MultipartFile.fromBytes('video', videoBytes, filename: filename),
      );

      final streamedResponse = await _client.send(request).timeout(
        ApiConfig.uploadTimeout,
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResult.success(VideoAnalysisResult.fromJson(json));
      }
      return ApiResult.failure(
        _parseError(response),
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult.failure('Video analysis failed: ${e.toString()}');
    }
  }

  /// Analyze specific video frames for faster results
  Future<ApiResult<VideoAnalysisResult>> analyzeVideoFrames(
    List<Uint8List> frames, {
    String filename = 'video_frames.zip',
  }) async {
    try {
      // Notify overlay that we are starting frame analysis
      await NativeBridge.sendMessageToOverlay({
        'sessionKind': 'media',
        'sourcePackage': 'com.example.risk_guard',
        'targetType': 'video',
        'targetLabel': filename,
        'status': 'Analyzing video frames...',
        'analysisSource': 'manual_scan',
        'isThreat': false,
        'threatText': 'Processing ${frames.length} frames',
      });

      final request = http.MultipartRequest(
        'POST',
        _uri(ApiConfig.videoAnalysis), // Reusing same endpoint or a new one if available
      );
      
      // In a real optimized system, we'd zip these or send as multiple files
      // For now, we'll send the most representative frame or the first few
      for (int i = 0; i < frames.length; i++) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'frames', 
            frames[i], 
            filename: 'frame_$i.jpg'
          ),
        );
      }

      final streamedResponse = await _client.send(request).timeout(
        ApiConfig.uploadTimeout,
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final result = VideoAnalysisResult.fromJson(json);
        
        // Update overlay with result
        await NativeBridge.sendMessageToOverlay({
          'sessionKind': 'media',
          'sourcePackage': 'com.example.risk_guard',
          'targetType': 'video',
          'targetLabel': filename,
          'status': 'Analysis Complete',
          'analysisSource': 'manual_scan',
          'isThreat': result.isDeepfake,
          'threatText': result.isDeepfake ? 'Deepfake Detected!' : 'Authentic Video',
          'riskScore': result.deepfakeProbability,
          'threatType': 'Video Deepfake',
          'recommendation': result.isDeepfake
              ? 'Review the media carefully before trusting or sharing it.'
              : 'No strong deepfake indicators were found in the sampled frames.',
        });

        return ApiResult.success(result);
      }
      return ApiResult.failure(
        _parseError(response),
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult.failure('Frame analysis failed: ${e.toString()}');
    }
  }

  // ── Risk Scoring ───────────────────────────────────────────────────────────

  Future<ApiResult<RiskScoringResult>> calculateRisk({
    int? callScore,
    int? voiceScore,
    int? contentScore,
    int? historyScore,
    List<String>? riskFactors,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (callScore != null) body['callScore'] = callScore;
      if (voiceScore != null) body['voiceScore'] = voiceScore;
      if (contentScore != null) body['contentScore'] = contentScore;
      if (historyScore != null) body['historyScore'] = historyScore;
      if (riskFactors != null) body['riskFactors'] = riskFactors;

      final response = await http
          .post(
            _uri(ApiConfig.riskCalculate),
            headers: _jsonHeaders,
            body: jsonEncode(body),
          )
          .timeout(ApiConfig.defaultTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResult.success(RiskScoringResult.fromJson(json));
      }
      return ApiResult.failure(
        _parseError(response),
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult.failure('Risk calculation failed: ${e.toString()}');
    }
  }

  // ── Blockchain Evidence ───────────────────────────────────────────────────

  /// File evidence to the blockchain backend (IPFS + SHA256 + SQLite)
  Future<ApiResult<BlockchainReportResult>> fileBlockchainReport({
    required Uint8List imageBytes,
    String filename = 'evidence.png',
    String profileUrl = '',
    String threatType = 'Deepfake',
    String aiResult = 'AI-Generated',
    double confidence = 0.0,
    String description = '',
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _uri(ApiConfig.blockchainReport),
      );
      request.files.add(
        http.MultipartFile.fromBytes('file', imageBytes, filename: filename),
      );
      request.fields['profile_url'] = profileUrl;
      request.fields['threat_type'] = threatType;
      request.fields['ai_result'] = aiResult;
      request.fields['confidence'] = confidence.toString();
      request.fields['description'] = description;

      final streamedResponse = await request.send().timeout(
        ApiConfig.uploadTimeout,
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResult.success(BlockchainReportResult.fromJson(json));
      }
      return ApiResult.failure(
        _parseError(response),
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult.failure('Blockchain report failed: ${e.toString()}');
    }
  }

  /// Get list of blockchain reports (evidence)
  Future<ApiResult<List<BlockchainReportResult>>> getBlockchainReports() async {
    try {
      final response = await http
          .get(_uri(ApiConfig.blockchainReports))
          .timeout(ApiConfig.defaultTimeout);
      
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        // Backend returns {"evidence": [...], "counts": {...}}
        // Extract the "evidence" list from the wrapper object
        final List<dynamic> jsonList = (body is Map && body['evidence'] is List)
            ? body['evidence'] as List<dynamic>
            : (body is List ? body : <dynamic>[]);
        return ApiResult.success(
          jsonList.map((e) => BlockchainReportResult.fromJson(e as Map<String, dynamic>)).toList(),
        );
      }
      return ApiResult.failure(
        _parseError(response),
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult.failure('Failed to fetch reports: ${e.toString()}');
    }
  }

  // ── Advanced Intelligence ─────────────────────────────────────────────────

  /// Fetch latest global threat feed
  Future<ApiResult<List<GlobalThreat>>> getGlobalThreats() async {
    try {
      final response = await http
          .get(_uri('${ApiConfig.globalIntel}?scope=deepfake'))
          .timeout(ApiConfig.defaultTimeout);
      if (response.statusCode == 200) {
        final List jsonList = jsonDecode(response.body);
        return ApiResult.success(
          jsonList.map((e) => GlobalThreat.fromJson(e)).toList(),
        );
      }
      return ApiResult.failure(_parseError(response));
    } catch (e) {
      return ApiResult.failure('Failed to fetch global threats: $e');
    }
  }

  /// Fetch risk map density data
  Future<ApiResult<List<RiskHotspot>>> getRiskMap() async {
    try {
      final response = await http
          .get(_uri('${ApiConfig.riskMap}?scope=deepfake'))
          .timeout(ApiConfig.defaultTimeout);
      if (response.statusCode == 200) {
        final List jsonList = jsonDecode(response.body);
        return ApiResult.success(
          jsonList.map((e) => RiskHotspot.fromJson(e)).toList(),
        );
      }
      return ApiResult.failure(_parseError(response));
    } catch (e) {
      return ApiResult.failure('Failed to fetch risk map: $e');
    }
  }

  /// Verify a URL/Domain against intelligence database
  Future<ApiResult<UrlVerificationResult>> verifyUrl(String url) async {
    try {
      final encodedUrl = Uri.encodeComponent(url);
      final response = await http
          .get(_uri('${ApiConfig.verifyUrl}?url=$encodedUrl'))
          .timeout(ApiConfig.defaultTimeout);
      if (response.statusCode == 200) {
        return ApiResult.success(
          UrlVerificationResult.fromJson(jsonDecode(response.body)),
        );
      }
      return ApiResult.failure(_parseError(response));
    } catch (e) {
      return ApiResult.failure('URL verification failed: $e');
    }
  }
}
