import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/analysis_models.dart';
import 'api_service.dart';

class ThreatIntelligenceProvider extends ChangeNotifier {
  ThreatIntelligenceProvider();

  final ApiService _apiService = ApiService();

  List<GlobalThreat> _globalThreats = <GlobalThreat>[];
  List<RiskHotspot> _hotspots = <RiskHotspot>[];
  bool _isLoading = false;
  bool _isVisible = false;
  Timer? _refreshTimer;

  List<GlobalThreat> get globalThreats => _globalThreats;
  List<GlobalThreat> get terminalThreats => _globalThreats.take(30).toList();
  List<RiskHotspot> get hotspots => _hotspots.take(20).toList();
  bool get isLoading => _isLoading;
  bool get isVisible => _isVisible;

  void attachScreen() {
    if (_isVisible) return;
    _isVisible = true;
    _startPolling();
    unawaited(refreshAll());
    notifyListeners();
  }

  void detachScreen() {
    if (!_isVisible) return;
    _isVisible = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    notifyListeners();
  }

  /// Safe version for dispose() — doesn't call notifyListeners (tree may be locked)
  void detachScreenSilent() {
    _isVisible = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _startPolling() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_isVisible) {
        unawaited(refreshAll());
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshAll() async {
    _isLoading = true;
    notifyListeners();

    final results = await Future.wait([
      _apiService.getGlobalThreats(),
      _apiService.getRiskMap(),
    ]);

    final threatResult = results[0] as ApiResult<List<GlobalThreat>>;
    final hotspotResult = results[1] as ApiResult<List<RiskHotspot>>;

    if (threatResult.isSuccess && threatResult.data != null) {
      _globalThreats = threatResult.data!;
    } else {
      _globalThreats = <GlobalThreat>[];
    }

    if (hotspotResult.isSuccess && hotspotResult.data != null) {
      _hotspots = hotspotResult.data!;
    } else {
      _hotspots = <RiskHotspot>[];
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<UrlVerificationResult?> verifyUrl(String url) async {
    final result = await _apiService.verifyUrl(url);
    if (result.isSuccess) {
      return result.data;
    }
    return null;
  }
}
