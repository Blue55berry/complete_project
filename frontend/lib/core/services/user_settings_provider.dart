/// User settings provider — stores profile, preferences, and feature toggles in Hive.
library;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'api_config.dart';
import 'native_bridge.dart';

class UserSettingsProvider extends ChangeNotifier {
  static const String _boxName = 'user_settings';

  Box? _box;

  // ── Profile fields ─────────────────────────────────────────────────────────
  String _displayName = 'Alex Morgan';
  String _email = 'alex@riskguard.io';
  Uint8List? _profileImageBytes;
  bool _notificationsEnabled = true;
  bool _biometricsEnabled = false;
  bool _darkModeEnabled = true;

  // ── Feature toggles ────────────────────────────────────────────────────────
  bool _voiceDetectionEnabled = true;
  bool _imageDetectionEnabled = true;
  bool _textDetectionEnabled = true;
  bool _videoDetectionEnabled = true;
  bool _blockchainEnabled = true;
  bool _callMonitoringEnabled = true;
  bool _mediaSharingEnabled = true;

  // ── Backend URL ────────────────────────────────────────────────────────────
  String _backendUrl = ApiConfig.defaultUrl;

  // ── Getters ────────────────────────────────────────────────────────────────
  String get displayName => _displayName;
  String get email => _email;
  Uint8List? get profileImageBytes => _profileImageBytes;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get biometricsEnabled => _biometricsEnabled;
  bool get darkModeEnabled => _darkModeEnabled;

  bool get voiceDetectionEnabled => _voiceDetectionEnabled;
  bool get imageDetectionEnabled => _imageDetectionEnabled;
  bool get textDetectionEnabled => _textDetectionEnabled;
  bool get videoDetectionEnabled => _videoDetectionEnabled;
  bool get blockchainEnabled => _blockchainEnabled;
  bool get callMonitoringEnabled => _callMonitoringEnabled;
  bool get mediaSharingEnabled => _mediaSharingEnabled;
  String get backendUrl => _backendUrl;

  /// Number of active feature shields
  int get activeShieldCount {
    int count = 0;
    if (_voiceDetectionEnabled) count++;
    if (_imageDetectionEnabled) count++;
    if (_textDetectionEnabled) count++;
    if (_videoDetectionEnabled) count++;
    if (_blockchainEnabled) count++;
    if (_callMonitoringEnabled) count++;
    if (_mediaSharingEnabled) count++;
    return count;
  }

  /// Whether the profile has a valid image (works on web + mobile)
  bool get hasProfileImage =>
      _profileImageBytes != null && _profileImageBytes!.isNotEmpty;

  /// Initialize from Hive on startup
  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _displayName =
        _box?.get('displayName', defaultValue: 'Alex Morgan') ?? 'Alex Morgan';
    _email =
        _box?.get('email', defaultValue: 'alex@riskguard.io') ??
        'alex@riskguard.io';
    // Load profile image from base64 string
    final b64 = _box?.get('profileImageBase64') as String?;
    if (b64 != null && b64.isNotEmpty) {
      try {
        _profileImageBytes = base64Decode(b64);
      } catch (_) {
        _profileImageBytes = null;
      }
    }
    _notificationsEnabled =
        _box?.get('notificationsEnabled', defaultValue: true) ?? true;
    _biometricsEnabled =
        _box?.get('biometricsEnabled', defaultValue: false) ?? false;
    _darkModeEnabled = _box?.get('darkModeEnabled', defaultValue: true) ?? true;

    // Feature toggles
    _voiceDetectionEnabled =
        _box?.get('voiceDetectionEnabled', defaultValue: true) ?? true;
    _imageDetectionEnabled =
        _box?.get('imageDetectionEnabled', defaultValue: true) ?? true;
    _textDetectionEnabled =
        _box?.get('textDetectionEnabled', defaultValue: true) ?? true;
    _videoDetectionEnabled =
        _box?.get('videoDetectionEnabled', defaultValue: true) ?? true;
    _blockchainEnabled =
        _box?.get('blockchainEnabled', defaultValue: true) ?? true;
    _callMonitoringEnabled =
        _box?.get('callMonitoringEnabled', defaultValue: true) ?? true;
    _mediaSharingEnabled =
        _box?.get('mediaSharingEnabled', defaultValue: true) ?? true;

    // Backend URL
    _backendUrl =
        _box?.get('backend_url', defaultValue: ApiConfig.defaultUrl) ??
        ApiConfig.defaultUrl;

    notifyListeners();
  }

  // ── Profile setters ────────────────────────────────────────────────────────

  Future<void> setDisplayName(String name) async {
    _displayName = name;
    await _box?.put('displayName', name);
    notifyListeners();
  }

  Future<void> setEmail(String email) async {
    _email = email;
    await _box?.put('email', email);
    notifyListeners();
  }

  /// Set profile image from bytes (works on web + mobile)
  Future<void> setProfileImageBytes(Uint8List? bytes) async {
    _profileImageBytes = bytes;
    if (bytes != null && bytes.isNotEmpty) {
      await _box?.put('profileImageBase64', base64Encode(bytes));
    } else {
      await _box?.delete('profileImageBase64');
    }
    notifyListeners();
  }

  Future<void> clearProfileImage() async {
    _profileImageBytes = null;
    await _box?.delete('profileImageBase64');
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    await _box?.put('notificationsEnabled', value);
    notifyListeners();
  }

  Future<void> setBiometricsEnabled(bool value) async {
    _biometricsEnabled = value;
    await _box?.put('biometricsEnabled', value);
    notifyListeners();
  }

  Future<void> setDarkModeEnabled(bool value) async {
    _darkModeEnabled = value;
    await _box?.put('darkModeEnabled', value);
    notifyListeners();
  }

  // ── Feature toggles ───────────────────────────────────────────────────────

  Future<void> setVoiceDetectionEnabled(bool value) async {
    _voiceDetectionEnabled = value;
    await _box?.put('voiceDetectionEnabled', value);
    await _syncNativeSecuritySettings();
    notifyListeners();
  }

  Future<void> setImageDetectionEnabled(bool value) async {
    _imageDetectionEnabled = value;
    await _box?.put('imageDetectionEnabled', value);
    await _syncNativeSecuritySettings();
    notifyListeners();
  }

  Future<void> setTextDetectionEnabled(bool value) async {
    _textDetectionEnabled = value;
    await _box?.put('textDetectionEnabled', value);
    await _syncNativeSecuritySettings();
    notifyListeners();
  }

  Future<void> setVideoDetectionEnabled(bool value) async {
    _videoDetectionEnabled = value;
    await _box?.put('videoDetectionEnabled', value);
    await _syncNativeSecuritySettings();
    notifyListeners();
  }

  Future<void> setBlockchainEnabled(bool value) async {
    _blockchainEnabled = value;
    await _box?.put('blockchainEnabled', value);
    await _syncNativeSecuritySettings();
    notifyListeners();
  }

  Future<void> setCallMonitoringEnabled(bool value) async {
    _callMonitoringEnabled = value;
    await _box?.put('callMonitoringEnabled', value);
    await _syncNativeSecuritySettings();
    notifyListeners();
  }

  Future<void> setMediaSharingEnabled(bool value) async {
    _mediaSharingEnabled = value;
    await _box?.put('mediaSharingEnabled', value);
    notifyListeners();
  }

  /// Enable/disable all features at once (Master Control).
  /// Note: This is only responsible for toggling the 7 functional toggles,
  /// not the "Real-time Protection" state (proactive_shield).
  Future<void> setAllFeaturesEnabled(bool value) async {
    _voiceDetectionEnabled = value;
    _imageDetectionEnabled = value;
    _textDetectionEnabled = value;
    _videoDetectionEnabled = value;
    _blockchainEnabled = value;
    _callMonitoringEnabled = value;
    _mediaSharingEnabled = value;
    await _box?.put('voiceDetectionEnabled', value);
    await _box?.put('imageDetectionEnabled', value);
    await _box?.put('textDetectionEnabled', value);
    await _box?.put('videoDetectionEnabled', value);
    await _box?.put('blockchainEnabled', value);
    await _box?.put('callMonitoringEnabled', value);
    await _box?.put('mediaSharingEnabled', value);
    await _syncNativeSecuritySettings();
    notifyListeners();
  }

  // ── Backend URL ────────────────────────────────────────────────────────────

  /// Update the backend URL (e.g., cloudflared tunnel link).
  /// Propagates to ALL API calls immediately via ApiConfig.
  Future<void> setBackendUrl(String url) async {
    final normalized = ApiConfig.normalizeBaseUrl(url);
    _backendUrl = normalized;
    await ApiConfig.setBaseUrl(normalized);
    notifyListeners();
  }

  Future<void> resetBackendUrl() async {
    _backendUrl = ApiConfig.defaultUrl;
    await ApiConfig.resetToDefault();
    notifyListeners();
  }

  // ── Clear all ──────────────────────────────────────────────────────────────

  /// Clear all settings (for logout)
  Future<void> clearAll() async {
    await _box?.clear();
    _displayName = 'Alex Morgan';
    _email = 'alex@riskguard.io';
    _profileImageBytes = null;
    _notificationsEnabled = true;
    _biometricsEnabled = false;
    _darkModeEnabled = true;
    _voiceDetectionEnabled = true;
    _imageDetectionEnabled = true;
    _textDetectionEnabled = true;
    _videoDetectionEnabled = true;
    _blockchainEnabled = true;
    _callMonitoringEnabled = true;
    _mediaSharingEnabled = true;
    _backendUrl = ApiConfig.defaultUrl;
    await ApiConfig.resetToDefault();
    await _syncNativeSecuritySettings();
    notifyListeners();
  }

  Future<void> _syncNativeSecuritySettings() async {
    try {
      final whitelistBox = await Hive.openBox('whitelist_settings');
      final enabledPkgs = <String>[];
      final keys =
          whitelistBox.keys.where((key) => key.toString().startsWith('wl_'));
      for (final key in keys) {
        if (whitelistBox.get(key) == true) {
          enabledPkgs.add(key.toString().replaceFirst('wl_', ''));
        }
      }

      final isProtectionActive =
          _box?.get('realtime_protection_enabled', defaultValue: false) ??
          false;

      await NativeBridge.syncSecuritySettings(
        isProtectionActive: isProtectionActive,
        whitelistedPackages: enabledPkgs,
        voiceDetectionEnabled: _voiceDetectionEnabled,
        imageDetectionEnabled: _imageDetectionEnabled,
        textDetectionEnabled: _textDetectionEnabled,
        videoDetectionEnabled: _videoDetectionEnabled,
        blockchainEnabled: _blockchainEnabled,
        callMonitoringEnabled: _callMonitoringEnabled,
      );

      await NativeBridge.sendPolicyUpdateToOverlay(
        isProtectionActive: isProtectionActive,
        voiceDetectionEnabled: _voiceDetectionEnabled,
        imageDetectionEnabled: _imageDetectionEnabled,
        textDetectionEnabled: _textDetectionEnabled,
        videoDetectionEnabled: _videoDetectionEnabled,
        blockchainEnabled: _blockchainEnabled,
        callMonitoringEnabled: _callMonitoringEnabled,
      );
    } catch (_) {}
  }
}
