/// Foreground notification service — shows "RiskGuard is protecting you"
/// persistent notification when real-time protection is ON.
/// Uses a platform channel to manage Android foreground service.
///
/// When ON:
///   - Starts Android ForegroundService with ongoing notification
///   - Notification shows: "RiskGuard is Active" + shield count
///
/// When OFF:
///   - Stops foreground service, removes notification
///   - Zero battery consumption
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NotificationService {
  static const _channel = MethodChannel('com.riskguard/notification');

  bool _isActive = false;
  bool get isActive => _isActive;
  bool get isSupported => !kIsWeb;

  /// Start the foreground service with persistent notification
  Future<void> startProtection({int shieldCount = 0}) async {
    if (!isSupported) {
      _isActive = true; // Simulate on web
      return;
    }
    try {
      await _channel.invokeMethod('startProtection', {
        'title': 'RiskGuard is Active',
        'message': '$shieldCount shields protecting you',
        'shieldCount': shieldCount,
      });
      _isActive = true;
    } catch (e) {
      debugPrint('NotificationService: Start failed: $e');
      _isActive = true; // Fallback: consider active even if notification fails
    }
  }

  /// Stop the foreground service and remove notification
  Future<void> stopProtection() async {
    if (!isSupported) {
      _isActive = false;
      return;
    }
    try {
      await _channel.invokeMethod('stopProtection');
      _isActive = false;
    } catch (e) {
      debugPrint('NotificationService: Stop failed: $e');
      _isActive = false;
    }
  }

  /// Update the notification text (e.g. when shield count changes)
  Future<void> updateNotification({required int shieldCount}) async {
    if (!isSupported || !_isActive) return;
    try {
      await _channel.invokeMethod('updateNotification', {
        'title': 'RiskGuard is Active',
        'message': '$shieldCount shields protecting you',
        'shieldCount': shieldCount,
      });
    } catch (e) {
      debugPrint('NotificationService: Update failed: $e');
    }
  }

  void dispose() {
    stopProtection();
  }
}
