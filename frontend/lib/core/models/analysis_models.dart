/// Dart data models matching the FastAPI backend Pydantic schemas exactly.
/// These are used to deserialize JSON responses from the backend.
library;

// ══════════════════════════════════════════════════════════════════════════════
// TEXT ANALYSIS
// ══════════════════════════════════════════════════════════════════════════════

class TextAnalysisResult {
  final int riskScore;
  final List<String> threats;
  final List<String> patterns;
  final List<String> urls;
  final String explanation;
  final bool isSafe;
  final double aiGeneratedProbability;
  final double aiConfidence;
  final bool isAiGenerated;
  final String aiExplanation;
  final String analysisMethod;
  final Map<String, dynamic>? aiSubScores;

  TextAnalysisResult({
    required this.riskScore,
    required this.threats,
    required this.patterns,
    required this.urls,
    required this.explanation,
    required this.isSafe,
    required this.aiGeneratedProbability,
    required this.aiConfidence,
    required this.isAiGenerated,
    required this.aiExplanation,
    required this.analysisMethod,
    this.aiSubScores,
  });

  factory TextAnalysisResult.fromJson(Map<String, dynamic> json) {
    return TextAnalysisResult(
      riskScore: (json['riskScore'] ?? 0) as int,
      threats: List<String>.from(json['threats'] ?? []),
      patterns: List<String>.from(json['patterns'] ?? []),
      urls: List<String>.from(json['urls'] ?? []),
      explanation: json['explanation'] ?? '',
      isSafe: json['isSafe'] ?? true,
      aiGeneratedProbability: (json['aiGeneratedProbability'] ?? 0.0)
          .toDouble(),
      aiConfidence: (json['aiConfidence'] ?? 0.0).toDouble(),
      isAiGenerated: json['isAiGenerated'] ?? false,
      aiExplanation: json['aiExplanation'] ?? '',
      analysisMethod: json['analysisMethod'] ?? 'unknown',
      aiSubScores: json['aiSubScores'] as Map<String, dynamic>?,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// VOICE ANALYSIS
// ══════════════════════════════════════════════════════════════════════════════

class VoiceAnalysisResult {
  final double syntheticProbability;
  final double confidence;
  final List<String> detectedPatterns;
  final String explanation;
  final bool isLikelyAI;
  final String analysisMethod;
  final double processingTimeMs;
  final Map<String, dynamic>? subScores;

  VoiceAnalysisResult({
    required this.syntheticProbability,
    required this.confidence,
    required this.detectedPatterns,
    required this.explanation,
    required this.isLikelyAI,
    required this.analysisMethod,
    required this.processingTimeMs,
    this.subScores,
  });

  factory VoiceAnalysisResult.fromJson(Map<String, dynamic> json) {
    return VoiceAnalysisResult(
      syntheticProbability: (json['syntheticProbability'] ?? 0.0).toDouble(),
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      detectedPatterns: List<String>.from(json['detectedPatterns'] ?? []),
      explanation: json['explanation'] ?? '',
      isLikelyAI: json['isLikelyAI'] ?? false,
      analysisMethod: json['analysisMethod'] ?? 'unknown',
      processingTimeMs: (json['processingTimeMs'] ?? 0.0).toDouble(),
      subScores: json['subScores'] as Map<String, dynamic>?,
    );
  }
}

class RealtimeVoiceResult {
  final double syntheticProbability;
  final double confidence;
  final bool isLikelyAI;
  final String status;
  final double processingTimeMs;
  final double? vadSpeechRatio;
  final int? chunkIndex;

  RealtimeVoiceResult({
    required this.syntheticProbability,
    required this.confidence,
    required this.isLikelyAI,
    required this.status,
    required this.processingTimeMs,
    this.vadSpeechRatio,
    this.chunkIndex,
  });

  factory RealtimeVoiceResult.fromJson(Map<String, dynamic> json) {
    return RealtimeVoiceResult(
      syntheticProbability: (json['syntheticProbability'] ?? 0.0).toDouble(),
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      isLikelyAI: json['isLikelyAI'] ?? false,
      status: json['status'] ?? 'unknown',
      processingTimeMs: (json['processingTimeMs'] ?? 0.0).toDouble(),
      vadSpeechRatio: (json['vadSpeechRatio'] as num?)?.toDouble(),
      chunkIndex: json['chunkIndex'] as int?,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// IMAGE ANALYSIS
// ══════════════════════════════════════════════════════════════════════════════

class ImageAnalysisResult {
  final double aiGeneratedProbability;
  final double confidence;
  final List<String> detectedPatterns;
  final String explanation;
  final bool isAiGenerated;
  final String analysisMethod;
  final String modelUsed;
  final double processingTimeMs;
  final Map<String, dynamic>? subScores;

  ImageAnalysisResult({
    required this.aiGeneratedProbability,
    required this.confidence,
    required this.detectedPatterns,
    required this.explanation,
    required this.isAiGenerated,
    required this.analysisMethod,
    required this.modelUsed,
    required this.processingTimeMs,
    this.subScores,
  });

  factory ImageAnalysisResult.fromJson(Map<String, dynamic> json) {
    return ImageAnalysisResult(
      aiGeneratedProbability: (json['aiGeneratedProbability'] ?? 0.0)
          .toDouble(),
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      detectedPatterns: List<String>.from(json['detectedPatterns'] ?? []),
      explanation: json['explanation'] ?? '',
      isAiGenerated: json['isAiGenerated'] ?? false,
      analysisMethod: json['analysisMethod'] ?? 'unknown',
      modelUsed: json['modelUsed'] ?? 'unknown',
      processingTimeMs: (json['processingTimeMs'] ?? 0.0).toDouble(),
      subScores: json['subScores'] as Map<String, dynamic>?,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// VIDEO ANALYSIS
// ══════════════════════════════════════════════════════════════════════════════

class VideoAnalysisResult {
  final double deepfakeProbability;
  final double confidence;
  final int analyzedFrames;
  final List<Map<String, dynamic>> frameResults;
  final List<String> detectedPatterns;
  final String explanation;
  final bool isDeepfake;
  final String analysisMethod;
  final Map<String, dynamic>? subScores;

  VideoAnalysisResult({
    required this.deepfakeProbability,
    required this.confidence,
    required this.analyzedFrames,
    required this.frameResults,
    required this.detectedPatterns,
    required this.explanation,
    required this.isDeepfake,
    required this.analysisMethod,
    this.subScores,
  });

  factory VideoAnalysisResult.fromJson(Map<String, dynamic> json) {
    return VideoAnalysisResult(
      deepfakeProbability: (json['deepfakeProbability'] ?? 0.0).toDouble(),
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      analyzedFrames: (json['analyzedFrames'] ?? 0) as int,
      frameResults:
          (json['frameResults'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [],
      detectedPatterns: List<String>.from(json['detectedPatterns'] ?? []),
      explanation: json['explanation'] ?? '',
      isDeepfake: json['isDeepfake'] ?? false,
      analysisMethod: json['analysisMethod'] ?? 'unknown',
      subScores: json['subScores'] as Map<String, dynamic>?,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RISK SCORING
// ══════════════════════════════════════════════════════════════════════════════

class RiskFactor {
  final String name;
  final int contribution;
  final String category;

  RiskFactor({
    required this.name,
    required this.contribution,
    required this.category,
  });

  factory RiskFactor.fromJson(Map<String, dynamic> json) {
    return RiskFactor(
      name: json['name'] ?? '',
      contribution: json['contribution'] ?? 0,
      category: json['category'] ?? '',
    );
  }
}

class RiskScoringResult {
  final int finalScore;
  final String riskLevel;
  final double confidence;
  final Map<String, int> componentScores;
  final List<RiskFactor> riskFactors;
  final String explanation;

  RiskScoringResult({
    required this.finalScore,
    required this.riskLevel,
    required this.confidence,
    required this.componentScores,
    required this.riskFactors,
    required this.explanation,
  });

  factory RiskScoringResult.fromJson(Map<String, dynamic> json) {
    return RiskScoringResult(
      finalScore: json['finalScore'] ?? 0,
      riskLevel: json['riskLevel'] ?? 'LOW',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      componentScores: Map<String, int>.from(
        (json['componentScores'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            {},
      ),
      riskFactors:
          (json['riskFactors'] as List?)
              ?.map((e) => RiskFactor.fromJson(e))
              .toList() ??
          [],
      explanation: json['explanation'] ?? '',
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SCAN HISTORY ENTRY (Local storage model)
// ══════════════════════════════════════════════════════════════════════════════

enum ScanType { text, voice, image, video }

enum CallHistoryOutcome { missed, answered, outgoing, blocked, unknown }

class ScanHistoryEntry {
  final String id;
  final ScanType type;
  final DateTime timestamp;
  final String riskLevel; // LOW, MEDIUM, HIGH
  final int riskScore;
  final String summary;
  final String explanation;

  ScanHistoryEntry({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.riskLevel,
    required this.riskScore,
    required this.summary,
    required this.explanation,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'riskLevel': riskLevel,
      'riskScore': riskScore,
      'summary': summary,
      'explanation': explanation,
    };
  }

  factory ScanHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ScanHistoryEntry(
      id: json['id'] ?? '',
      type: ScanType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ScanType.text,
      ),
      timestamp: DateTime.parse(json['timestamp']),
      riskLevel: json['riskLevel'] ?? 'LOW',
      riskScore: json['riskScore'] ?? 0,
      summary: json['summary'] ?? '',
      explanation: json['explanation'] ?? '',
    );
  }
}

class CallHistoryEntry {
  final String id;
  final String personKey;
  final String displayName;
  final String phoneNumber;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;
  final String riskLevel; // LOW, MEDIUM, HIGH
  final int riskScore;
  final CallHistoryOutcome outcome;
  final String summary;

  const CallHistoryEntry({
    required this.id,
    required this.personKey,
    required this.displayName,
    required this.phoneNumber,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.riskLevel,
    required this.riskScore,
    required this.outcome,
    required this.summary,
  });

  Duration get duration => Duration(seconds: durationSeconds);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'personKey': personKey,
      'displayName': displayName,
      'phoneNumber': phoneNumber,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt.toIso8601String(),
      'durationSeconds': durationSeconds,
      'riskLevel': riskLevel,
      'riskScore': riskScore,
      'outcome': outcome.name,
      'summary': summary,
    };
  }

  factory CallHistoryEntry.fromJson(Map<String, dynamic> json) {
    return CallHistoryEntry(
      id: json['id']?.toString() ?? '',
      personKey: json['personKey']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Unknown caller',
      phoneNumber: json['phoneNumber']?.toString() ?? 'Unknown number',
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
          DateTime.now(),
      endedAt: DateTime.tryParse(json['endedAt']?.toString() ?? '') ??
          DateTime.now(),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      riskLevel: json['riskLevel']?.toString() ?? 'LOW',
      riskScore: (json['riskScore'] as num?)?.toInt() ?? 0,
      outcome: CallHistoryOutcome.values.firstWhere(
        (value) => value.name == json['outcome'],
        orElse: () => CallHistoryOutcome.unknown,
      ),
      summary: json['summary']?.toString() ?? '',
    );
  }

  CallHistoryEntry copyWith({
    String? id,
    String? personKey,
    String? displayName,
    String? phoneNumber,
    DateTime? startedAt,
    DateTime? endedAt,
    int? durationSeconds,
    String? riskLevel,
    int? riskScore,
    CallHistoryOutcome? outcome,
    String? summary,
  }) =>
      CallHistoryEntry(
        id: id ?? this.id,
        personKey: personKey ?? this.personKey,
        displayName: displayName ?? this.displayName,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        riskLevel: riskLevel ?? this.riskLevel,
        riskScore: riskScore ?? this.riskScore,
        outcome: outcome ?? this.outcome,
        summary: summary ?? this.summary,
      );
}

class CallHistoryGroup {
  final String personKey;
  final String displayName;
  final String phoneNumber;
  final List<CallHistoryEntry> calls;

  const CallHistoryGroup({
    required this.personKey,
    required this.displayName,
    required this.phoneNumber,
    required this.calls,
  });

  CallHistoryEntry get latestCall => calls.first;
}

// ══════════════════════════════════════════════════════════════════════════════
// BLOCKCHAIN EVIDENCE
// ══════════════════════════════════════════════════════════════════════════════

class BlockchainReportResult {
  final int evidenceId;
  final String ipfsCid;
  final String ipfsUrl;
  final String fileHash;
  final String filename;
  final String txHash;
  final int? batchId;
  final bool anchored;
  final String timestamp;
  final String profileUrl;
  final String threatType;
  final String aiResult;
  final double confidence;
  final String description;
  final String? merkleRoot;
  final String? explorerUrl;

  BlockchainReportResult({
    required this.evidenceId,
    required this.ipfsCid,
    required this.ipfsUrl,
    required this.fileHash,
    required this.filename,
    required this.txHash,
    this.batchId,
    required this.anchored,
    required this.timestamp,
    required this.profileUrl,
    required this.threatType,
    required this.aiResult,
    required this.confidence,
    required this.description,
    this.merkleRoot,
    this.explorerUrl,
  });

  factory BlockchainReportResult.fromJson(Map<String, dynamic> json) {
    final evidence = json['evidence'] as Map<String, dynamic>? ?? json;
    return BlockchainReportResult(
      evidenceId: evidence['id'] ?? 0,
      ipfsCid: evidence['ipfs_cid'] ?? '',
      ipfsUrl: json['ipfs_url'] ?? '',
      fileHash: evidence['file_hash'] ?? '',
      filename: evidence['filename'] ?? '',
      txHash: evidence['tx_hash'] ?? '',
      batchId: evidence['batch_id'] as int?,
      anchored: evidence['anchored'] == true || evidence['anchored'] == 1,
      timestamp: evidence['timestamp'] ?? '',
      profileUrl: evidence['profile_url'] ?? '',
      threatType: evidence['threat_type'] ?? '',
      aiResult: evidence['ai_result'] ?? '',
      confidence: (evidence['confidence'] ?? 0.0).toDouble(),
      description: evidence['description'] ?? '',
      merkleRoot: evidence['merkle_root'] as String?,
      explorerUrl: json['explorer_url'] as String?,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ADVANCED THREAT INTELLIGENCE
// ══════════════════════════════════════════════════════════════════════════════

class GlobalThreat {
  final String id;
  final String timestamp;
  final String region;
  final String cityOrZoneLabel;
  final String threatClass;
  final String mediaType;
  final String category;
  final String campaign;
  final String severity;
  final String confidenceBand;
  final String analysisSource;
  final String artifactSummary;
  final String description;
  final bool blockchainVerified;

  GlobalThreat({
    required this.id,
    required this.timestamp,
    required this.region,
    required this.cityOrZoneLabel,
    required this.threatClass,
    required this.mediaType,
    required this.category,
    required this.campaign,
    required this.severity,
    required this.confidenceBand,
    required this.analysisSource,
    required this.artifactSummary,
    required this.description,
    required this.blockchainVerified,
  });

  factory GlobalThreat.fromJson(Map<String, dynamic> json) {
    final threatClass =
        json['threatClass'] ?? json['threat_class'] ?? json['category'] ?? '';
    final mediaType = json['mediaType'] ?? json['media_type'] ?? '';
    final artifactSummary =
        json['artifactSummary'] ?? json['artifact_summary'] ?? '';
    return GlobalThreat(
      id: json['id'] ?? '',
      timestamp: json['timestamp'] ?? '',
      region: json['region'] ?? '',
      cityOrZoneLabel:
          json['cityOrZoneLabel'] ?? json['city_or_zone_label'] ?? '',
      threatClass: threatClass,
      mediaType: mediaType,
      category: json['category'] ?? threatClass,
      campaign: json['campaign'] ?? mediaType,
      severity: json['severity'] ?? 'LOW',
      confidenceBand:
          json['confidenceBand'] ?? json['confidence_band'] ?? '50-59%',
      analysisSource:
          json['analysisSource'] ?? json['analysis_source'] ?? 'local',
      artifactSummary: artifactSummary,
      description: json['description'] ?? artifactSummary,
      blockchainVerified:
          json['blockchainVerified'] ?? json['blockchain_verified'] ?? false,
    );
  }

  // ── Compatibility getters for threat_intelligence_screen ──────────────────
  /// Human-readable name/title for the threat artifact.
  String get mediaName => artifactSummary.isNotEmpty ? artifactSummary : threatClass;

  /// Numeric severity score (0-100) derived from severity label.
  double get score {
    switch (severity.toUpperCase()) {
      case 'CRITICAL': return 0.95;
      case 'HIGH':     return 0.75;
      case 'MEDIUM':   return 0.50;
      case 'LOW':      return 0.25;
      default:         return 0.30;
    }
  }

  /// URL to stream/play the threat media artifact (if available).
  String get mediaUrl => '';

  /// Preview text for the threat detail view.
  String get previewData => description.isNotEmpty ? description : artifactSummary;
}

class RealtimeMediaAnalysisResult {
  final String requestId;
  final String sessionId;
  final String mediaKind;
  final String captureStage;
  final String status;
  final String analysisSource;
  final double selectionConfidence;
  final double aiGeneratedProbability;
  final double confidence;
  final List<String> detectedPatterns;
  final String explanation;
  final bool isAiGenerated;
  final String analysisMethod;
  final String modelUsed;
  final double processingTimeMs;
  final Map<String, dynamic>? subScores;

  RealtimeMediaAnalysisResult({
    required this.requestId,
    required this.sessionId,
    required this.mediaKind,
    required this.captureStage,
    required this.status,
    required this.analysisSource,
    required this.selectionConfidence,
    required this.aiGeneratedProbability,
    required this.confidence,
    required this.detectedPatterns,
    required this.explanation,
    required this.isAiGenerated,
    required this.analysisMethod,
    required this.modelUsed,
    required this.processingTimeMs,
    this.subScores,
  });

  factory RealtimeMediaAnalysisResult.fromJson(Map<String, dynamic> json) {
    return RealtimeMediaAnalysisResult(
      requestId: json['requestId'] ?? '',
      sessionId: json['sessionId'] ?? '',
      mediaKind: json['mediaKind'] ?? 'screen_fallback',
      captureStage: json['captureStage'] ?? 'first_pass',
      status: json['status'] ?? 'ok',
      analysisSource: json['analysisSource'] ?? 'live_media',
      selectionConfidence: (json['selectionConfidence'] ?? 0.0).toDouble(),
      aiGeneratedProbability: (json['aiGeneratedProbability'] ?? 0.0)
          .toDouble(),
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      detectedPatterns: List<String>.from(json['detectedPatterns'] ?? []),
      explanation: json['explanation'] ?? '',
      isAiGenerated: json['isAiGenerated'] ?? false,
      analysisMethod: json['analysisMethod'] ?? 'unknown',
      modelUsed: json['modelUsed'] ?? 'unknown',
      processingTimeMs: (json['processingTimeMs'] ?? 0.0).toDouble(),
      subScores:
          (json['subScores'] as Map?)
              ?.map((key, value) => MapEntry('$key', value)),
    );
  }
}

class RiskHotspot {
  final double lat;
  final double lng;
  final double intensity;
  final String label;
  final String region;
  final int eventCount;
  final List<String> threatClasses;

  RiskHotspot({
    required this.lat,
    required this.lng,
    required this.intensity,
    required this.label,
    required this.region,
    required this.eventCount,
    required this.threatClasses,
  });

  factory RiskHotspot.fromJson(Map<String, dynamic> json) {
    final rawEventCount = json['eventCount'] ?? json['event_count'] ?? 0;
    return RiskHotspot(
      lat: (json['lat'] ?? 0.0).toDouble(),
      lng: (json['lng'] ?? 0.0).toDouble(),
      intensity: (json['intensity'] ?? 0.0).toDouble(),
      label: json['label'] ?? '',
      region: json['region'] ?? '',
      eventCount: rawEventCount is num ? rawEventCount.toInt() : 0,
      threatClasses:
          (json['threatClasses'] as List?)
              ?.map((entry) => entry.toString())
              .toList() ??
          (json['threat_classes'] as List?)
              ?.map((entry) => entry.toString())
              .toList() ??
          <String>[],
    );
  }
}

class UrlVerificationResult {
  final String url;
  final String status;
  final int riskScore;
  final String threatType;
  final String intelligenceSource;
  final String recommendation;
  final String? requestId;
  final double? latencyMs;
  final bool cacheHit;

  UrlVerificationResult({
    required this.url,
    required this.status,
    required this.riskScore,
    required this.threatType,
    required this.intelligenceSource,
    required this.recommendation,
    this.requestId,
    this.latencyMs,
    this.cacheHit = false,
  });

  factory UrlVerificationResult.fromJson(Map<String, dynamic> json) {
    final rawRiskScore = json['riskScore'] ?? json['risk_score'] ?? 0;
    final rawLatency = json['latencyMs'] ?? json['latency_ms'];
    return UrlVerificationResult(
      url: json['url'] ?? '',
      status: json['status'] ?? 'SAFE',
      riskScore: rawRiskScore is num ? rawRiskScore.toInt() : 0,
      threatType: json['threatType'] ?? json['threat_type'] ?? '',
      intelligenceSource:
          json['intelligenceSource'] ?? json['intelligence_source'] ?? '',
      recommendation: json['recommendation'] ?? '',
      requestId: json['requestId'] ?? json['request_id'],
      latencyMs: rawLatency is num ? rawLatency.toDouble() : null,
      cacheHit: json['cacheHit'] == true || json['cache_hit'] == true,
    );
  }
}
