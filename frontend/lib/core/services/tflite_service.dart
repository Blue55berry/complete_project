/// TFLite service — stub for on-device ML inference.
/// When TFLite models are added to assets/models/, this service provides
/// fast local classification before deciding whether to call the cloud API.
///
/// Models needed:
///   - assets/models/mobilebert.tflite   (~25MB) — text classification
///   - assets/models/mobilenet_v2.tflite (~3.4MB) — image classification
///
/// Usage (future):
///   final tflite = TFLiteService();
///   await tflite.loadModels();
///   final result = tflite.classifyText("suspicious text");
///   if (result.confidence > 0.8) showResultDirectly(result);
///   else callCloudAPI(text);
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Classification result from the local TFLite model
class LocalClassification {
  final String label;     // e.g. 'safe', 'phishing', 'ai_generated'
  final double confidence; // 0.0 - 1.0
  final bool needsCloudVerification; // true if confidence is in uncertain range

  LocalClassification({
    required this.label,
    required this.confidence,
    required this.needsCloudVerification,
  });
}

/// Service that manages TFLite model loading and inference.
/// Currently a stub — replace with tflite_flutter when models are added.
class TFLiteService {
  bool _modelsLoaded = false;
  bool get isReady => _modelsLoaded;

  // Confidence thresholds for the hybrid gatekeeper
  static const double highConfidenceThreshold = 0.80;
  static const double lowConfidenceThreshold = 0.40;

  /// Load TFLite models from assets.
  /// Call once at app startup.
  Future<void> loadModels() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final textModelFile = File('${dir.path}/mobilebert.tflite');
      final imageModelFile = File('${dir.path}/mobilenet_v2.tflite');

      if (textModelFile.existsSync() && imageModelFile.existsSync()) {
        // TODO: Replace with actual tflite_flutter model loading:
        // _textModel = await Interpreter.fromFile(textModelFile);
        // _imageModel = await Interpreter.fromFile(imageModelFile);
        debugPrint('TFLiteService: Models loaded from storage');
        _modelsLoaded = true;
      } else {
        debugPrint('TFLiteService: Models missing in storage — using cloud fallback');
        _modelsLoaded = false;
      }
    } catch (e) {
      debugPrint('TFLiteService: Failed to load models: $e');
      _modelsLoaded = false;
    }
  }

  /// Classify text locally using MobileBERT.
  /// Returns null if models aren't loaded (forces cloud fallback).
  LocalClassification? classifyText(String text) {
    if (!_modelsLoaded) return null;

    // TODO: When tflite_flutter is integrated:
    // 1. Tokenize text using WordPiece tokenizer
    // 2. Run inference: _textModel.run(inputTokens, output);
    // 3. Parse output probabilities

    return null; // Stub — always falls back to cloud
  }

  /// Classify image locally using MobileNetV2.
  /// Returns null if models aren't loaded (forces cloud fallback).
  LocalClassification? classifyImage(Uint8List imageBytes) {
    if (!_modelsLoaded) return null;

    // TODO: When tflite_flutter is integrated:
    // 1. Decode image to 224x224 RGB
    // 2. Normalize pixel values
    // 3. Run inference: _imageModel.run(imageData, output);
    // 4. Parse output probabilities

    return null; // Stub — always falls back to cloud
  }

  /// The hybrid gatekeeper decision logic.
  /// Returns true if cloud API call is needed.
  bool shouldCallCloud(LocalClassification? localResult) {
    if (localResult == null) return true; // No local result → must use cloud
    if (localResult.confidence >= highConfidenceThreshold) return false; // High confidence → trust local
    if (localResult.confidence <= lowConfidenceThreshold) return true;  // Low confidence → need cloud
    return true; // Uncertain range → use cloud for safety
  }

  void dispose() {
    // TODO: Dispose interpreters when tflite_flutter is added
    // _textModel?.close();
    // _imageModel?.close();
  }
}
