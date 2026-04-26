/// Local deterministic scanner to provide accurate fallback scores 
/// when cloud and TFLite models are unavailable.
class LocalHeuristicScanner {
  LocalHeuristicScanner._();

  /// Scam keywords for text analysis
  static const List<String> _scamKeywords = [
    'bank', 'password', 'verify', 'urgent', 'prize', 'winner', 
    'lottery', 'account', 'blocked', 'suspended', 'ssn', 'social security',
    'crypto', 'wallet', 'seed phrase', 'emergency', 'unauthorized',
    'security alert', 'gift card', 'irs', 'police', 'fine'
  ];

  /// Analyze text for common scam patterns
  static Map<String, dynamic> analyzeText(String text) {
    final lowerText = text.toLowerCase();
    final detectedPatterns = <String>[];
    int score = 15; // Base low risk

    // 1. Keyword check
    int keywordMatches = 0;
    for (final keyword in _scamKeywords) {
      if (lowerText.contains(keyword)) {
        keywordMatches++;
        detectedPatterns.add('Scam keyword: "$keyword"');
      }
    }
    score += (keywordMatches * 15);

    // 2. Urgency check
    if (lowerText.contains('now') || lowerText.contains('immediately') || lowerText.contains('hurry')) {
      score += 10;
      detectedPatterns.add('High urgency detected');
    }

    // 3. Link check (heuristic)
    if (lowerText.contains('http') || lowerText.contains('.com') || lowerText.contains('.ly')) {
      score += 5;
    }

    if (score > 100) score = 100;

    return {
      'riskScore': score,
      'riskLevel': score > 70 ? 'HIGH' : (score > 40 ? 'MEDIUM' : 'LOW'),
      'patterns': detectedPatterns,
      'explanation': score > 70 
          ? 'High risk: Contains multiple scam keywords and urgency patterns.'
          : 'Low to moderate risk based on local heuristic patterns.',
      'method': 'Deterministic Heuristics (Offline Fallback)'
    };
  }

  /// Analyze URL for phishing markers
  static Map<String, dynamic> analyzeUrl(String url) {
    final lowerUrl = url.toLowerCase();
    int score = 20;
    final patterns = <String>[];

    // 1. IP Address check
    final ipRegex = RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}');
    if (ipRegex.hasMatch(lowerUrl)) {
      score += 40;
      patterns.add('Direct IP address in URL');
    }

    // 2. Suspicious TLDs
    final suspiciousTLDs = ['.xyz', '.top', '.loan', '.click', '.win', '.monster'];
    for (final tld in suspiciousTLDs) {
      if (lowerUrl.endsWith(tld)) {
        score += 20;
        patterns.add('Suspicious TLD: $tld');
      }
    }

    // 3. Length check
    if (lowerUrl.length > 80) {
      score += 15;
      patterns.add('Excessively long URL');
    }

    if (score > 100) score = 100;

    return {
      'riskScore': score,
      'riskLevel': score > 70 ? 'HIGH' : (score > 40 ? 'MEDIUM' : 'LOW'),
      'patterns': patterns,
      'explanation': 'Local structural analysis of the URL detected suspicious markers.',
      'method': 'URL Structure Heuristics'
    };
  }
}
