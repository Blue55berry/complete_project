import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

class NativeBridge {
  static const MethodChannel _channel = MethodChannel('com.example.risk_guard/native');
  
  static Function(String url, String? packageName)? _onUrlDetected;

  /// Initialize native bridge and set up call handlers
  static void init({Function(String url, String? packageName)? onUrlDetected}) {
    if (kIsWeb) return;
    _onUrlDetected = onUrlDetected;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onUrlDetected') {
        final String? url = call.arguments['url'];
        final String? packageName = call.arguments['packageName'];
        if (url != null && _onUrlDetected != null) {
          _onUrlDetected!(url, packageName);
        }
      } else if (call.method == 'onCallDetected') {
        final String? state = call.arguments['state'];
        final String? phoneNumber = call.arguments['phoneNumber'];
        if (_onCallDetected != null) {
          _onCallDetected!(state, phoneNumber);
        }
      }
    });
  }

  static Function(String? state, String? phoneNumber)? _onCallDetected;

  static void setCallListener(Function(String? state, String? phoneNumber) listener) {
    _onCallDetected = listener;
  }

  /// Fetches the icon of an Android app as a byte array.
  static Future<Uint8List?> getAppIcon(String packageName) async {
    if (kIsWeb) return null;
    try {
      final Uint8List? icon = await _channel.invokeMethod('getAppIcon', {
        'packageName': packageName,
      });
      return icon;
    } on PlatformException catch (e) {
      debugPrint("Failed to get app icon: '${e.message}'.");
      return null;
    }
  }

  /// Checks if the overlay (draw over other apps) permission is granted.
  static Future<bool> isOverlayPermissionGranted() async {
    if (kIsWeb) return true;
    try {
      return await _channel.invokeMethod('isOverlayPermissionGranted');
    } on PlatformException catch (e) {
      debugPrint("Failed to check overlay permission: '${e.message}'.");
      return false;
    }
  }

  /// Requests the overlay permission by opening system settings.
  static Future<void> requestOverlayPermission() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException catch (e) {
      debugPrint("Failed to request overlay permission: '${e.message}'.");
    }
  }

  /// Checks if the accessibility service permission is granted.
  static Future<bool> isAccessibilityPermissionGranted() async {
    if (kIsWeb) return true;
    try {
      return await _channel.invokeMethod('isAccessibilityPermissionGranted');
    } on PlatformException catch (e) {
      debugPrint("Failed to check accessibility permission: '${e.message}'.");
      return false;
    }
  }

  /// Requests the accessibility permission by opening system settings.
  static Future<void> requestAccessibilityPermission() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('requestAccessibilityPermission');
    } on PlatformException catch (e) {
      debugPrint("Failed to request accessibility permission: '${e.message}'.");
    }
  }

  /// Get all installed apps that have a launch intent
  static Future<List<Map<String, dynamic>>> getInstalledApps() async {
    if (kIsWeb) return [];
    try {
      final List<dynamic> apps = await _channel.invokeMethod('getInstalledApps');
      return apps.map((e) => Map<String, dynamic>.from(e)).toList();
    } on PlatformException catch (e) {
      debugPrint("Failed to get installed apps: '${e.message}'.");
      return [];
    }
  }

  /// Send a message to the overlay window
  static Future<void> sendMessageToOverlay(Map<String, dynamic> data) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('sendMessageToOverlay', data);
    } on PlatformException catch (e) {
      debugPrint("Failed to send message to overlay: '${e.message}'.");
    }
  }

  /// Sync security settings (Master Toggle + Whitelist) to native SharedPreferences.
  /// This ensures the Accessibility Service can operate even if the Flutter engine is detached.
  static Future<void> syncSecuritySettings({
    required bool isProtectionActive,
    required List<String> whitelistedPackages,
    required bool voiceDetectionEnabled,
    required bool imageDetectionEnabled,
    required bool textDetectionEnabled,
    required bool videoDetectionEnabled,
    required bool blockchainEnabled,
    required bool callMonitoringEnabled,
  }) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('syncSecuritySettings', {
        'isProtectionActive': isProtectionActive,
        'whitelistedPackages': whitelistedPackages,
        'voiceDetectionEnabled': voiceDetectionEnabled,
        'imageDetectionEnabled': imageDetectionEnabled,
        'textDetectionEnabled': textDetectionEnabled,
        'videoDetectionEnabled': videoDetectionEnabled,
        'blockchainEnabled': blockchainEnabled,
        'callMonitoringEnabled': callMonitoringEnabled,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to sync security settings: '${e.message}'.");
    }
  }

  /// Start the native RiskGuard foreground service
  static Future<void> startForegroundService() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('startForegroundService');
    } on PlatformException catch (e) {
      debugPrint("Failed to start foreground service: '${e.message}'.");
    }
  }

  /// Whether the native foreground service is currently marked as running.
  static Future<bool> isForegroundServiceRunning() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod('isForegroundServiceRunning') ?? false;
    } on PlatformException catch (e) {
      debugPrint("Failed to read foreground service state: '${e.message}'.");
      return false;
    }
  }

  /// Stop the native RiskGuard foreground service
  static Future<void> stopForegroundService() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('stopForegroundService');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop foreground service: '${e.message}'.");
    }
  }

  /// Requests user consent for Android screen capture via MediaProjection.
  /// Returns true when the capture session becomes active.
  static Future<bool> requestMediaProjectionPermission() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod('requestMediaProjectionPermission') ??
          false;
    } on PlatformException catch (e) {
      debugPrint("Failed to request screen capture permission: '${e.message}'.");
      return false;
    }
  }

  /// Whether the native MediaProjection capture session is active.
  static Future<bool> isMediaProjectionActive() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod('isMediaProjectionActive') ?? false;
    } on PlatformException catch (e) {
      debugPrint("Failed to read screen capture state: '${e.message}'.");
      return false;
    }
  }

  /// Request a one-shot frame capture from the active screen-capture service.
  static Future<bool> requestRealtimeMediaCapture({
    String? sourcePackage,
    String reason = 'manual',
    String? sessionId,
    String captureStage = 'first_pass',
  }) async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod('requestRealtimeMediaCapture', {
            'sourcePackage': sourcePackage,
            'reason': reason,
            'sessionId': sessionId,
            'captureStage': captureStage,
          }) ??
          false;
    } on PlatformException catch (e) {
      debugPrint("Failed to request realtime media capture: '${e.message}'.");
      return false;
    }
  }

  /// Stop the MediaProjection-based capture service.
  static Future<void> stopMediaProjectionService() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('stopMediaProjectionService');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop screen capture service: '${e.message}'.");
    }
  }

  /// Clears native Android protection prefs that are outside FlutterSharedPreferences.
  static Future<void> clearNativeProtectionState() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('clearNativeProtectionState');
    } on PlatformException catch (e) {
      debugPrint("Failed to clear native protection state: '${e.message}'.");
    }
  }

  /// Push a lightweight policy update into the overlay queue so active sessions
  /// can be dismissed immediately when a feature is turned off.
  static Future<void> sendPolicyUpdateToOverlay({
    required bool isProtectionActive,
    required bool voiceDetectionEnabled,
    required bool imageDetectionEnabled,
    required bool textDetectionEnabled,
    required bool videoDetectionEnabled,
    required bool blockchainEnabled,
    required bool callMonitoringEnabled,
  }) async {
    await sendMessageToOverlay({
      'targetType': 'policy',
      'status': 'POLICY_UPDATE',
      'type': 'policy_update',
      'isProtectionActive': isProtectionActive,
      'voiceDetectionEnabled': voiceDetectionEnabled,
      'imageDetectionEnabled': imageDetectionEnabled,
      'textDetectionEnabled': textDetectionEnabled,
      'videoDetectionEnabled': videoDetectionEnabled,
      'blockchainEnabled': blockchainEnabled,
      'callMonitoringEnabled': callMonitoringEnabled,
    });
  }
}
