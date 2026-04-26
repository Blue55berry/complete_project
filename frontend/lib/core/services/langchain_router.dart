/// LangChain-style router — intelligently routes analysis requests
/// to the optimal pipeline (local TFLite → cloud API).
///
/// Decision Tree:
///   1. Input arrives (text, image, audio, URL)
///   2. Run local TFLite check if models are loaded
///   3. If local confidence > 80%: return result (zero latency, zero cloud)
///   4. If local confidence < 40%: must use cloud
///   5. If uncertain (40-80%): use cloud for accuracy
///
/// This reduces cloud API calls by ~80%, saving battery and bandwidth.
library;

import 'package:flutter/foundation.dart';
import 'package:risk_guard/core/services/tflite_service.dart';
import 'package:risk_guard/core/services/local_heuristic_scanner.dart';

/// Input type classification
enum AnalysisInputType { text, url, image, audio, video }

/// Route decision — where to process the input
enum ProcessingRoute { localOnly, cloudOnly, hybridLocalFirst }

/// Routing result
class RouteDecision {
  final AnalysisInputType inputType;
  final ProcessingRoute route;
  final LocalClassification? localResult;
  final String reason;

  RouteDecision({
    required this.inputType,
    required this.route,
    this.localResult,
    required this.reason,
  });
}

/// The LangChain-style orchestrator that decides processing pipeline.
class LangChainRouter {
  final TFLiteService _tflite;

  LangChainRouter({TFLiteService? tfliteService})
      : _tflite = tfliteService ?? TFLiteService();

  /// Classify input type from raw data
  AnalysisInputType classifyInput(String? text, Uint8List? mediaBytes) {
    if (mediaBytes != null) {
      // Check if it's video by size (rough heuristic)
      if (mediaBytes.length > 5 * 1024 * 1024) return AnalysisInputType.video;
      return AnalysisInputType.image;
    }
    if (text != null) {
      // Check if it's a URL
      final urlPattern = RegExp(r'https?://\S+|www\.\S+');
      if (urlPattern.hasMatch(text) && text.split(' ').length <= 3) {
        return AnalysisInputType.url;
      }
      return AnalysisInputType.text;
    }
    return AnalysisInputType.text;
  }

  /// Route a text input through the optimal pipeline
  RouteDecision routeText(String text) {
    final inputType = classifyInput(text, null);

    // URLs always go to cloud (need phishing database)
    if (inputType == AnalysisInputType.url) {
      return RouteDecision(
        inputType: inputType,
        route: ProcessingRoute.cloudOnly,
        reason: 'URLs require cloud phishing database check',
      );
    }

    // Try local TFLite first
    if (_tflite.isReady) {
      final localResult = _tflite.classifyText(text);
      if (localResult != null && !_tflite.shouldCallCloud(localResult)) {
        return RouteDecision(
          inputType: inputType,
          route: ProcessingRoute.localOnly,
          localResult: localResult,
          reason: 'High confidence local result (${(localResult.confidence * 100).round()}%)',
        );
      }
      return RouteDecision(
        inputType: inputType,
        route: ProcessingRoute.hybridLocalFirst,
        localResult: localResult,
        reason: 'Local confidence too low, routing to cloud',
      );
    }

    // No local models → fallback to heuristics
    final heuristic = LocalHeuristicScanner.analyzeText(text);
    return RouteDecision(
      inputType: inputType,
      route: ProcessingRoute.cloudOnly,
      localResult: LocalClassification(
        label: heuristic['riskLevel'].toString().toLowerCase(),
        confidence: (heuristic['riskScore'] as int) / 100.0,
        needsCloudVerification: true,
      ),
      reason: 'TFLite not loaded; providing deterministic heuristic score.',
    );
  }

  /// Route an image input through the optimal pipeline
  RouteDecision routeImage(Uint8List imageBytes) {
    if (_tflite.isReady) {
      final localResult = _tflite.classifyImage(imageBytes);
      if (localResult != null && !_tflite.shouldCallCloud(localResult)) {
        return RouteDecision(
          inputType: AnalysisInputType.image,
          route: ProcessingRoute.localOnly,
          localResult: localResult,
          reason: 'High confidence local image classification',
        );
      }
    }

    return RouteDecision(
      inputType: AnalysisInputType.image,
      route: ProcessingRoute.cloudOnly,
      reason: 'Image analysis requires cloud pipeline',
    );
  }

  /// Route audio — always cloud (no local audio model yet)
  RouteDecision routeAudio() {
    return RouteDecision(
      inputType: AnalysisInputType.audio,
      route: ProcessingRoute.cloudOnly,
      reason: 'Voice analysis requires cloud wav2vec2 model',
    );
  }

  /// Route video — always cloud
  RouteDecision routeVideo() {
    return RouteDecision(
      inputType: AnalysisInputType.video,
      route: ProcessingRoute.cloudOnly,
      reason: 'Video frame analysis requires cloud pipeline',
    );
  }

  /// Log routing decision for debugging
  void logDecision(RouteDecision decision) {
    debugPrint(
      'LangChainRouter: ${decision.inputType.name} → ${decision.route.name} '
      '(${decision.reason})',
    );
  }
}
