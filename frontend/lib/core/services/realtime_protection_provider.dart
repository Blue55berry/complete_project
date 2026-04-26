import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_service.dart';
import 'native_bridge.dart';
import 'service_watchdog.dart';

enum ProtectionRuntimeState {
  off,
  starting,
  active,
  degraded,
  stopping,
}

/// Real-time protection provider for the Android background protection stack.
class RealtimeProtectionProvider extends ChangeNotifier {
  static const String _boxName = 'user_settings';
  static const String _activeKey = 'realtime_protection_enabled';
  static const MethodChannel _overlayChannel =
      MethodChannel('x-slayer/overlay_channel');

  bool _desiredEnabled = false;
  bool _permissionsReady = false;
  bool _nativeServicesRunning = false;
  bool _overlayRuntimeReady = false;
  bool _mediaCaptureReady = false;
  bool _isBackendConnected = false;
  bool _loaded = false;
  bool _showAccessibilityGuidance = false;
  bool _isTransitioning = false;
  String? _lastProtectionError;
  String? _activeForegroundSource;
  String? _activeSessionKind;
  ProtectionRuntimeState _runtimeState = ProtectionRuntimeState.off;

  final Set<String> _processedUrls = <String>{};
  final ServiceWatchdog _watchdog = ServiceWatchdog();

  bool get isActive => _desiredEnabled;
  bool get desiredEnabled => _desiredEnabled;
  bool get permissionsReady => _permissionsReady;
  bool get nativeServicesRunning => _nativeServicesRunning;
  bool get overlayRuntimeReady => _overlayRuntimeReady;
  bool get mediaCaptureReady => _mediaCaptureReady;
  bool get isBackendConnected => _isBackendConnected;
  bool get showAccessibilityGuidance => _showAccessibilityGuidance;
  bool get isTransitioning => _isTransitioning;
  bool get isDegraded => _runtimeState == ProtectionRuntimeState.degraded;
  String? get lastProtectionError => _lastProtectionError;
  String? get activeForegroundSource => _activeForegroundSource;
  String? get activeSessionKind => _activeSessionKind;
  ProtectionRuntimeState get runtimeState => _runtimeState;

  Future<void> loadState() async {
    if (_loaded) return;

    try {
      final box = await Hive.openBox(_boxName);
      _desiredEnabled = box.get(_activeKey, defaultValue: false);
      _loaded = true;

      NativeBridge.init(onUrlDetected: _handleUrlDetected);
      NativeBridge.setCallListener(_handleCallDetected);

      await checkBackendHealth();

      if (Platform.isAndroid) {
        _nativeServicesRunning = await NativeBridge.isForegroundServiceRunning();
        _overlayRuntimeReady = await _isOverlayActive();
        _mediaCaptureReady = await NativeBridge.isMediaProjectionActive();
      }

      await syncToNative();

      if (_desiredEnabled && Platform.isAndroid) {
        await setProtection(true, allowPrompts: false, force: true);
      } else {
        _updateRuntimeState();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('RealtimeProtectionProvider: Failed to load: $e');
      _loaded = true;
      _lastProtectionError = e.toString();
      _updateRuntimeState();
    }
  }

  Future<bool> toggleProtection() async {
    return setProtection(!_desiredEnabled);
  }

  Future<bool> setProtection(
    bool value, {
    bool allowPrompts = true,
    bool force = false,
  }) async {
    if (_isTransitioning) return _desiredEnabled;
    if (!force && _desiredEnabled == value) {
      await _refreshRuntimeHealth();
      return _desiredEnabled;
    }

    _isTransitioning = true;
    _runtimeState = value
        ? ProtectionRuntimeState.starting
        : ProtectionRuntimeState.stopping;
    notifyListeners();

    try {
      if (value && Platform.isAndroid) {
        _desiredEnabled = true;
        _lastProtectionError = null;
        await _persistState();
        await syncToNative();
        notifyListeners();

        final ready = await _ensureAndroidPrerequisites(
          allowPrompts: allowPrompts,
        );
        if (!ready) {
          _desiredEnabled = false;
          _nativeServicesRunning = false;
          _overlayRuntimeReady = false;
          _processedUrls.clear();
          await _persistState();
          await syncToNative();
          _updateRuntimeState();
          notifyListeners();
          return false;
        }

        final monitoringStarted = await _startNativeMonitoring();
        _nativeServicesRunning =
            monitoringStarted || await NativeBridge.isForegroundServiceRunning();
        _overlayRuntimeReady = await _ensureOverlayRuntimeReady();
        _mediaCaptureReady = await NativeBridge.isMediaProjectionActive();
        if (!_mediaCaptureReady && allowPrompts) {
          final granted = await NativeBridge.requestMediaProjectionPermission();
          _mediaCaptureReady =
              granted || await NativeBridge.isMediaProjectionActive();
          if (!_mediaCaptureReady) {
            _lastProtectionError =
                'Screen capture permission was not granted. URL and call monitoring remain active.';
          }
        }

        if (!_nativeServicesRunning) {
          _desiredEnabled = false;
          _lastProtectionError = 'Native realtime service failed to start.';
          await _persistState();
          await syncToNative();
          _updateRuntimeState();
          notifyListeners();
          return false;
        }

        await _persistState();
        await syncToNative();
        _updateRuntimeState();
        // Start the service watchdog — will auto-restart on OEM kill
        if (Platform.isAndroid) _watchdog.start();
        notifyListeners();
        return true;
      }

      _desiredEnabled = value;
      await _persistState();
      await syncToNative();

      if (Platform.isAndroid) {
        await _stopNativeMonitoring();
      }

        if (!value) {
          _watchdog.stop(); // Kill watchdog when protection is turned off
          _processedUrls.clear();
          _showAccessibilityGuidance = false;
          _permissionsReady = false;
          _nativeServicesRunning = false;
          _overlayRuntimeReady = false;
          _mediaCaptureReady = false;
          _activeForegroundSource = null;
          _activeSessionKind = null;
          _lastProtectionError = null;
        }

      _updateRuntimeState();
      notifyListeners();
      return _desiredEnabled;
    } finally {
      _isTransitioning = false;
      _updateRuntimeState();
      notifyListeners();
    }
  }

  Future<void> syncToNative() async {
    try {
      final whitelistBox = await Hive.openBox('whitelist_settings');
      final settingsBox = await Hive.openBox(_boxName);
      final enabledPkgs = <String>[];
      final keys =
          whitelistBox.keys.where((key) => key.toString().startsWith('wl_'));

      for (final key in keys) {
        if (whitelistBox.get(key) == true) {
          enabledPkgs.add(key.toString().replaceFirst('wl_', ''));
        }
      }

      final voiceDetectionEnabled =
          settingsBox.get('voiceDetectionEnabled', defaultValue: true) ?? true;
      final imageDetectionEnabled =
          settingsBox.get('imageDetectionEnabled', defaultValue: true) ?? true;
      final textDetectionEnabled =
          settingsBox.get('textDetectionEnabled', defaultValue: true) ?? true;
      final videoDetectionEnabled =
          settingsBox.get('videoDetectionEnabled', defaultValue: true) ?? true;
      final blockchainEnabled =
          settingsBox.get('blockchainEnabled', defaultValue: true) ?? true;
      final callMonitoringEnabled =
          settingsBox.get('callMonitoringEnabled', defaultValue: true) ?? true;

      await NativeBridge.syncSecuritySettings(
        isProtectionActive: _desiredEnabled,
        whitelistedPackages: enabledPkgs,
        voiceDetectionEnabled: voiceDetectionEnabled,
        imageDetectionEnabled: imageDetectionEnabled,
        textDetectionEnabled: textDetectionEnabled,
        videoDetectionEnabled: videoDetectionEnabled,
        blockchainEnabled: blockchainEnabled,
        callMonitoringEnabled: callMonitoringEnabled,
      );
      await NativeBridge.sendPolicyUpdateToOverlay(
        isProtectionActive: _desiredEnabled,
        voiceDetectionEnabled: voiceDetectionEnabled,
        imageDetectionEnabled: imageDetectionEnabled,
        textDetectionEnabled: textDetectionEnabled,
        videoDetectionEnabled: videoDetectionEnabled,
        blockchainEnabled: blockchainEnabled,
        callMonitoringEnabled: callMonitoringEnabled,
      );
    } catch (e) {
      debugPrint('RealtimeProtectionProvider: Sync failed: $e');
    }
  }

  Future<void> checkBackendHealth() async {
    final healthy = await ApiService().isBackendHealthy();
    if (_isBackendConnected != healthy) {
      _isBackendConnected = healthy;
      notifyListeners();
    }
  }

  void dismissAccessibilityGuidance() {
    if (!_showAccessibilityGuidance) return;
    _showAccessibilityGuidance = false;
    notifyListeners();
  }

  Future<bool> _ensureAndroidPrerequisites({
    required bool allowPrompts,
  }) async {
    _permissionsReady = false;

    final overlayGranted = await _isOverlayPermissionGranted();
    if (!overlayGranted) {
      if (allowPrompts) {
        await NativeBridge.requestOverlayPermission();
      }
      _lastProtectionError = 'Overlay permission is required.';
      return false;
    }

    final accessibilityGranted =
        await NativeBridge.isAccessibilityPermissionGranted();
    if (!accessibilityGranted) {
      _showAccessibilityGuidance = true;
      notifyListeners();
      if (allowPrompts) {
        await NativeBridge.requestAccessibilityPermission();
      }
      _lastProtectionError = 'Accessibility service is required.';
      return false;
    }

    final phoneStatus = await Permission.phone.status;
    if (!phoneStatus.isGranted) {
      if (!allowPrompts) {
        _lastProtectionError = 'Phone permission is required.';
        return false;
      }

      final requestedStatus = await Permission.phone.request();
      if (!requestedStatus.isGranted) {
        _lastProtectionError = 'Phone permission is required.';
        return false;
      }
    }

    if (_showAccessibilityGuidance) {
      _showAccessibilityGuidance = false;
    }

    _permissionsReady = true;
    _lastProtectionError = null;
    notifyListeners();
    return true;
  }

  Future<bool> _startNativeMonitoring() async {
    try {
      if (await NativeBridge.isForegroundServiceRunning()) {
        return true;
      }

      await NativeBridge.startForegroundService();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return await NativeBridge.isForegroundServiceRunning();
    } catch (e) {
      _lastProtectionError = 'Failed to start foreground monitoring.';
      debugPrint('RealtimeProtectionProvider: Failed to start service: $e');
      return false;
    }
  }

  Future<void> _stopNativeMonitoring() async {
    try {
      await NativeBridge.stopMediaProjectionService();
    } catch (e) {
      debugPrint(
        'RealtimeProtectionProvider: Failed to stop media projection: $e',
      );
    }

    try {
      if (await _isOverlayActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (e) {
      debugPrint('RealtimeProtectionProvider: Failed to close overlay: $e');
    }

    try {
      await NativeBridge.stopForegroundService();
    } catch (e) {
      debugPrint('RealtimeProtectionProvider: Failed to stop service: $e');
    }

    _nativeServicesRunning = false;
    _overlayRuntimeReady = false;
    _mediaCaptureReady = false;
  }

  Future<bool> _ensureOverlayRuntimeReady() async {
    if (await _isOverlayActive()) {
      return true;
    }

    try {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: false,
        flag: OverlayFlag.defaultFlag,
        alignment: OverlayAlignment.centerRight,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.none,
        height: 1,
        width: 1,
        overlayTitle: 'RiskGuard Active',
        overlayContent: 'Realtime protection is active in the background.',
      );
    } catch (e) {
      _lastProtectionError = 'Overlay runtime could not be started.';
      debugPrint('RealtimeProtectionProvider: Failed to show overlay: $e');
      return false;
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    final isActive = await _isOverlayActive();
    if (!isActive) {
      _lastProtectionError = 'Overlay runtime did not become active.';
    }
    return isActive;
  }

  Future<void> _handleUrlDetected(String url, String? packageName) async {
    if (!_desiredEnabled) return;
    if (_processedUrls.contains(url)) return;

    _processedUrls.add(url);
    _activeSessionKind = 'url';
    _activeForegroundSource = packageName;
    _overlayRuntimeReady = await _ensureOverlayRuntimeReady();
    _nativeServicesRunning = await NativeBridge.isForegroundServiceRunning();
    _updateRuntimeState();
    notifyListeners();
  }

  Future<void> _handleCallDetected(String? state, String? phoneNumber) async {
    if (!_desiredEnabled || state == null) return;

    _activeForegroundSource = phoneNumber ?? 'phone_service';
    _activeSessionKind = state == 'IDLE' ? null : 'call';
    if (state == 'RINGING' || state == 'OFFHOOK') {
      _overlayRuntimeReady = await _ensureOverlayRuntimeReady();
    }

    _nativeServicesRunning = await NativeBridge.isForegroundServiceRunning();
    _updateRuntimeState();
    notifyListeners();
  }

  Future<bool> _isOverlayPermissionGranted() async {
    try {
      final granted =
          await _overlayChannel.invokeMethod<bool>('checkPermission');
      if (granted != null) {
        return granted;
      }
    } catch (e) {
      debugPrint(
        'RealtimeProtectionProvider: Plugin overlay permission check failed: $e',
      );
    }

    return NativeBridge.isOverlayPermissionGranted();
  }

  Future<bool> _isOverlayActive() async {
    try {
      return await _overlayChannel.invokeMethod<bool>('isOverlayActive') ??
          false;
    } catch (e) {
      debugPrint('RealtimeProtectionProvider: Overlay active check failed: $e');
      return false;
    }
  }

  Future<void> _refreshRuntimeHealth() async {
    if (!Platform.isAndroid) {
      _updateRuntimeState();
      return;
    }

    _nativeServicesRunning = await NativeBridge.isForegroundServiceRunning();
    _overlayRuntimeReady = await _isOverlayActive();
    _mediaCaptureReady = await NativeBridge.isMediaProjectionActive();
    _updateRuntimeState();
    notifyListeners();
  }

  void _updateRuntimeState() {
    if (!_desiredEnabled) {
      _runtimeState = ProtectionRuntimeState.off;
      return;
    }

    if (_isTransitioning) {
      return;
    }

    if (_nativeServicesRunning && _overlayRuntimeReady) {
      if (!_mediaCaptureReady) {
        _runtimeState = ProtectionRuntimeState.degraded;
        return;
      }
      _runtimeState = ProtectionRuntimeState.active;
      return;
    }

    if (_nativeServicesRunning) {
      _runtimeState = ProtectionRuntimeState.degraded;
      return;
    }

    _runtimeState = ProtectionRuntimeState.starting;
  }

  Future<void> _persistState() async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_activeKey, _desiredEnabled);
    } catch (e) {
      debugPrint('RealtimeProtectionProvider: Failed to persist: $e');
    }
  }

  @override
  void dispose() {
    _watchdog.stop();
    super.dispose();
  }
}
