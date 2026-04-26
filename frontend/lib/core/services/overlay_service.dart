/// Overlay service — manages the floating "Command Center" overlay on Android.
/// Uses flutter_overlay_window to display a persistent floating icon over other apps.
///
/// States:
///   1. Collapsed: Small circular RiskGuard icon (draggable)
///   2. Expanded:  Horizontal pill with action buttons (Text, Voice, Image, Video)
///   3. Feedback:  Shows analysis result card
///
/// This is an Android-only feature. On web/iOS, overlay functionality is disabled.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Overlay state enum
enum OverlayState { hidden, collapsed, expanded, feedback }

/// Service that manages the floating overlay window.
/// Currently a stub — requires `flutter_overlay_window` package on Android.
class OverlayService {
  static const _channel = MethodChannel('com.riskguard/overlay');

  OverlayState _state = OverlayState.hidden;
  OverlayState get state => _state;

  bool get isSupported => !kIsWeb; // Only Android supports overlay

  /// Check if overlay permission is granted (SYSTEM_ALERT_WINDOW)
  Future<bool> hasOverlayPermission() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('hasOverlayPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('OverlayService: Permission check failed: $e');
      return false;
    }
  }

  /// Request SYSTEM_ALERT_WINDOW permission
  Future<bool> requestOverlayPermission() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('requestOverlayPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('OverlayService: Permission request failed: $e');
      return false;
    }
  }

  /// Show the collapsed overlay icon
  Future<void> showOverlay() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('showOverlay');
      _state = OverlayState.collapsed;
    } catch (e) {
      debugPrint('OverlayService: Show overlay failed: $e');
    }
  }

  /// Hide the overlay
  Future<void> hideOverlay() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('hideOverlay');
      _state = OverlayState.hidden;
    } catch (e) {
      debugPrint('OverlayService: Hide overlay failed: $e');
    }
  }

  /// Expand the overlay to show action buttons
  Future<void> expandOverlay() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('expandOverlay');
      _state = OverlayState.expanded;
    } catch (e) {
      debugPrint('OverlayService: Expand overlay failed: $e');
    }
  }

  /// Show feedback result in the overlay
  Future<void> showFeedback({
    required String title,
    required String message,
    required bool isSafe,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('showFeedback', {
        'title': title,
        'message': message,
        'isSafe': isSafe,
      });
      _state = OverlayState.feedback;
    } catch (e) {
      debugPrint('OverlayService: Feedback show failed: $e');
    }
  }

  void dispose() {
    hideOverlay();
  }
}
