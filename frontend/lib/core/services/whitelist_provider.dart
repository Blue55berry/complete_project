/// Whitelist provider — manages which apps RiskGuard monitors.
/// On Android: uses platform channel to detect installed apps.
/// On Web/iOS: shows a comprehensive predefined list + user can add custom apps.
/// All selections are persisted in Hive.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'native_bridge.dart';

/// Represents an app that can be whitelisted for RiskGuard monitoring.
class WhitelistedApp {
  final String packageName;
  final String displayName;
  final String category;
  final String brandColor; // hex brand color e.g. '#E1306C'
  bool isEnabled;
  final bool isSystemDetected;
  Uint8List? iconBytes;

  WhitelistedApp({
    required this.packageName,
    required this.displayName,
    this.category = 'Other',
    this.brandColor = '#6C63FF',
    this.isEnabled = false,
    this.isSystemDetected = false,
    this.iconBytes,
  });

  Color get brandColorValue {
    try {
      final hex = brandColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF6C63FF);
    }
  }
}

class WhitelistProvider extends ChangeNotifier {
  static const String _boxName = 'whitelist_settings';
  static const String _customAppsKey = 'custom_apps';

  Box? _box;
  bool _loaded = false;
  bool _isScanning = false;

  final List<WhitelistedApp> _apps = [];

  List<WhitelistedApp> get apps => List.unmodifiable(_apps);
  List<WhitelistedApp> get enabledApps =>
      _apps.where((a) => a.isEnabled).toList();
  int get enabledCount => _apps.where((a) => a.isEnabled).length;
  int get totalCount => _apps.length;
  bool get isScanning => _isScanning;

  // Predefined social/messaging apps — offline brand colors
  static final List<Map<String, String>> _knownApps = [
    {'pkg': 'com.instagram.android',         'name': 'Instagram',    'cat': 'Social',    'color': 'E1306C'},
    {'pkg': 'com.whatsapp',                  'name': 'WhatsApp',     'cat': 'Messaging', 'color': '25D366'},
    {'pkg': 'com.facebook.katana',           'name': 'Facebook',     'cat': 'Social',    'color': '1877F2'},
    {'pkg': 'org.telegram.messenger',        'name': 'Telegram',     'cat': 'Messaging', 'color': '0088CC'},
    {'pkg': 'com.twitter.android',           'name': 'X (Twitter)',  'cat': 'Social',    'color': '000000'},
    {'pkg': 'com.snapchat.android',          'name': 'Snapchat',     'cat': 'Social',    'color': 'FFFC00'},
    {'pkg': 'com.zhiliaoapp.musically',      'name': 'TikTok',       'cat': 'Social',    'color': 'FF2D55'},
    {'pkg': 'com.linkedin.android',          'name': 'LinkedIn',     'cat': 'Social',    'color': '0A66C2'},
    {'pkg': 'com.discord',                   'name': 'Discord',      'cat': 'Messaging', 'color': '5865F2'},
    {'pkg': 'com.reddit.frontpage',          'name': 'Reddit',       'cat': 'Social',    'color': 'FF4500'},
    {'pkg': 'com.pinterest',                 'name': 'Pinterest',    'cat': 'Social',    'color': 'E60023'},
    {'pkg': 'com.google.android.youtube',    'name': 'YouTube',      'cat': 'Media',     'color': 'FF0000'},
    {'pkg': 'com.spotify.music',             'name': 'Spotify',      'cat': 'Media',     'color': '1DB954'},
    {'pkg': 'com.skype.raider',              'name': 'Skype',        'cat': 'Messaging', 'color': '00AFF0'},
    {'pkg': 'com.viber.voip',                'name': 'Viber',        'cat': 'Messaging', 'color': '665CAC'},
    {'pkg': 'jp.naver.line.android',         'name': 'LINE',         'cat': 'Messaging', 'color': '00C300'},
    {'pkg': 'com.google.android.apps.messaging', 'name': 'Messages', 'cat': 'Messaging', 'color': '4285F4'},
    {'pkg': 'com.bumble.app',                'name': 'Bumble',       'cat': 'Social',    'color': 'FFC629'},
    {'pkg': 'com.tinder',                    'name': 'Tinder',       'cat': 'Social',    'color': 'FD5564'},
    {'pkg': 'com.Slack',                     'name': 'Slack',        'cat': 'Messaging', 'color': '4A154B'},
  ];

  /// Load state: detect installed apps (Android) or use predefined list (web)
  Future<void> loadState() async {
    if (_loaded) return;
    try {
      _box = await Hive.openBox(_boxName);
      _isScanning = true;
      notifyListeners();

      if (!kIsWeb) {
        // Android: try to get all installed apps
        await _loadInstalledApps();
      } else {
        // Web: use predefined list
        _loadPredefinedApps();
      }

      // Also load any custom user-added apps
      _loadCustomApps();

      // Restore enabled states from Hive
      for (final app in _apps) {
        app.isEnabled = _box?.get('wl_${app.packageName}', defaultValue: false) ?? false;
      }

      _isScanning = false;
      _loaded = true;
      notifyListeners();
      await _syncToNative();
    } catch (e) {
      debugPrint('WhitelistProvider: Failed to load: $e');
      _loadPredefinedApps(); // Fallback
      _isScanning = false;
      _loaded = true;
      notifyListeners();
    }
  }

  /// Android: detect installed apps via native platform channel
  static const _channel = MethodChannel('com.example.risk_guard/native');

  Future<void> _loadInstalledApps() async {
    try {
      final List<dynamic>? result =
          await _channel.invokeMethod('getInstalledApps');
      if (result != null && result.isNotEmpty) {
        final apps = result.cast<Map>();
        apps.sort((a, b) => (a['name'] as String)
            .toLowerCase()
            .compareTo((b['name'] as String).toLowerCase()));

        for (final app in apps) {
          final pkg = app['packageName'] as String;
          final name = app['name'] as String;
          final known = _knownApps.firstWhere(
            (k) => k['pkg'] == pkg,
            orElse: () => {'cat': 'Other'},
          );
          _apps.add(WhitelistedApp(
            packageName: pkg,
            displayName: name,
            category: known['cat'] ?? 'Other',
            brandColor: known['color'] ?? '6C63FF',
            isSystemDetected: true,
          ));
        }
        // Asynchronously load icons to keep UI responsive
        _loadIcons();
      } else {
        _loadPredefinedApps();
      }
    } catch (e) {
      debugPrint('WhitelistProvider: Platform channel not available: $e');
      _loadPredefinedApps(); // Fallback
    }
  }

  /// Web/fallback: use the predefined known apps list
  void _loadPredefinedApps() {
    for (final known in _knownApps) {
      if (!_apps.any((a) => a.packageName == known['pkg'])) {
        _apps.add(WhitelistedApp(
          packageName: known['pkg']!,
          displayName: known['name']!,
          category: known['cat']!,
          brandColor: known['color'] ?? '6C63FF',
          isSystemDetected: false,
        ));
      }
    }
  }

  /// Load user-added custom apps from Hive
  void _loadCustomApps() {
    final customList = _box?.get(_customAppsKey, defaultValue: <String>[]) ?? <String>[];
    // customList is stored as List<String> of "packageName|displayName|category"
    for (final entry in (customList as List)) {
      final parts = entry.toString().split('|');
      if (parts.length >= 2) {
        final pkg = parts[0];
        final name = parts[1];
        final cat = parts.length > 2 ? parts[2] : 'Other';
        if (!_apps.any((a) => a.packageName == pkg)) {
          _apps.add(WhitelistedApp(
            packageName: pkg,
            displayName: name,
            category: cat,
            isSystemDetected: false,
          ));
        }
      }
    }
  }

  /// Rescan for installed apps (Android only, pull-to-refresh)
  Future<void> rescan() async {
    _isScanning = true;
    notifyListeners();

    // Save current enabled states
    final enabledPkgs = <String>{};
    for (final app in _apps.where((a) => a.isEnabled)) {
      enabledPkgs.add(app.packageName);
    }

    _apps.clear();

    if (!kIsWeb) {
      await _loadInstalledApps();
    } else {
      _loadPredefinedApps();
    }
    _loadCustomApps();

    // Restore enabled states
    for (final app in _apps) {
      app.isEnabled = enabledPkgs.contains(app.packageName) ||
          (_box?.get('wl_${app.packageName}', defaultValue: false) ?? false);
    }

    _isScanning = false;
    notifyListeners();
  }

  /// Toggle a specific app's whitelist status
  Future<void> toggleApp(String packageName) async {
    final idx = _apps.indexWhere((a) => a.packageName == packageName);
    if (idx < 0) return;
    _apps[idx].isEnabled = !_apps[idx].isEnabled;
    await _box?.put('wl_$packageName', _apps[idx].isEnabled);
    notifyListeners();
    await _syncToNative();
  }

  /// Set a specific app's whitelist status
  Future<void> setAppEnabled(String packageName, bool enabled) async {
    final idx = _apps.indexWhere((a) => a.packageName == packageName);
    if (idx < 0) return;
    if (_apps[idx].isEnabled == enabled) return;
    _apps[idx].isEnabled = enabled;
    await _box?.put('wl_$packageName', enabled);
    notifyListeners();
    await _syncToNative();
  }

  /// Enable all apps
  Future<void> enableAll() async {
    for (final app in _apps) {
      app.isEnabled = true;
      await _box?.put('wl_${app.packageName}', true);
    }
    notifyListeners();
    await _syncToNative();
  }

  /// Disable all apps
  Future<void> disableAll() async {
    for (final app in _apps) {
      app.isEnabled = false;
      await _box?.put('wl_${app.packageName}', false);
    }
    notifyListeners();
    await _syncToNative();
  }

  /// Add a custom app manually (for new/unknown apps)
  Future<void> addCustomApp(String name, {String category = 'Other'}) async {
    final pkg = 'custom.${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    if (_apps.any((a) => a.packageName == pkg || a.displayName.toLowerCase() == name.toLowerCase())) {
      return; // Already exists
    }
    _apps.add(WhitelistedApp(
      packageName: pkg,
      displayName: name,
      category: category,
      isEnabled: true,
      isSystemDetected: false,
    ));
    await _box?.put('wl_$pkg', true);

    // Save to custom apps list
    final customList = (_box?.get(_customAppsKey, defaultValue: <String>[]) ?? <String>[]) as List;
    customList.add('$pkg|$name|$category');
    await _box?.put(_customAppsKey, customList);

    notifyListeners();
  }

  /// Remove a custom app
  Future<void> removeCustomApp(String packageName) async {
    _apps.removeWhere((a) => a.packageName == packageName && !a.isSystemDetected);
    await _box?.delete('wl_$packageName');

    // Remove from custom list
    final customList = (_box?.get(_customAppsKey, defaultValue: <String>[]) ?? <String>[]) as List;
    customList.removeWhere((e) => e.toString().startsWith('$packageName|'));
    await _box?.put(_customAppsKey, customList);

    notifyListeners();
  }

  /// Check if an app is whitelisted
  bool isWhitelisted(String packageName) {
    return _apps.any((a) => a.packageName == packageName && a.isEnabled);
  }

  /// Get apps grouped by category
  Map<String, List<WhitelistedApp>> get appsByCategory {
    final map = <String, List<WhitelistedApp>>{};
    for (final app in _apps) {
      map.putIfAbsent(app.category, () => []).add(app);
    }
    return map;
  }

  /// Load app icons from native bridge
  Future<void> _loadIcons() async {
    if (kIsWeb) return;
    for (var i = 0; i < _apps.length; i++) {
      if (_apps[i].iconBytes == null && _apps[i].isSystemDetected) {
        try {
          final bytes = await _channel.invokeMethod('getAppIcon', {'packageName': _apps[i].packageName});
          if (bytes != null) {
            _apps[i].iconBytes = bytes;
            notifyListeners();
          }
        } catch (e) {
          // Silent fail for icons
        }
      }
    }
  }

  /// Sync enabled apps to native persistence
  Future<void> _syncToNative() async {
    try {
      if (kIsWeb) return;
      final enabledPkgs = enabledApps.map((a) => a.packageName).toList();
      
      // We need the protection status too, read from Hive directly for accuracy
      final settingsBox = await Hive.openBox('user_settings');
      final bool isProtectionActive = settingsBox.get('realtime_protection_enabled', defaultValue: false);
      final bool voiceDetectionEnabled =
          settingsBox.get('voiceDetectionEnabled', defaultValue: true) ?? true;
      final bool imageDetectionEnabled =
          settingsBox.get('imageDetectionEnabled', defaultValue: true) ?? true;
      final bool textDetectionEnabled =
          settingsBox.get('textDetectionEnabled', defaultValue: true) ?? true;
      final bool videoDetectionEnabled =
          settingsBox.get('videoDetectionEnabled', defaultValue: true) ?? true;
      final bool blockchainEnabled =
          settingsBox.get('blockchainEnabled', defaultValue: true) ?? true;
      final bool callMonitoringEnabled =
          settingsBox.get('callMonitoringEnabled', defaultValue: true) ?? true;

      await NativeBridge.syncSecuritySettings(
        isProtectionActive: isProtectionActive,
        whitelistedPackages: enabledPkgs,
        voiceDetectionEnabled: voiceDetectionEnabled,
        imageDetectionEnabled: imageDetectionEnabled,
        textDetectionEnabled: textDetectionEnabled,
        videoDetectionEnabled: videoDetectionEnabled,
        blockchainEnabled: blockchainEnabled,
        callMonitoringEnabled: callMonitoringEnabled,
      );
      await NativeBridge.sendPolicyUpdateToOverlay(
        isProtectionActive: isProtectionActive,
        voiceDetectionEnabled: voiceDetectionEnabled,
        imageDetectionEnabled: imageDetectionEnabled,
        textDetectionEnabled: textDetectionEnabled,
        videoDetectionEnabled: videoDetectionEnabled,
        blockchainEnabled: blockchainEnabled,
        callMonitoringEnabled: callMonitoringEnabled,
      );
    } catch (e) {
      debugPrint('WhitelistProvider: Sync failed: $e');
    }
  }

  /// Clear all whitelist settings (for logout)
  Future<void> clearAll() async {
    try {
      final box = _box ?? await Hive.openBox(_boxName);
      _box = box;
      await box.clear();
      for (final app in _apps) {
        app.isEnabled = false;
      }
      _loaded = true;
      notifyListeners();
      await _syncToNative();
    } catch (e) {
      debugPrint('WhitelistProvider: Failed to clear: $e');
    }
  }
}
