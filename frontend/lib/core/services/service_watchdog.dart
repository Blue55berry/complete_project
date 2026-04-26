/// service_watchdog.dart — FIX-12
/// ────────────────────────────────────────────────────────────────────────────
/// Watches the overlay foreground service and restarts it automatically if it
/// is killed by the OS (common on OEM ROMs: Xiaomi MIUI, Samsung One UI,
/// OnePlus OxygenOS with aggressive battery management).
///
/// Usage:
///   final watchdog = ServiceWatchdog(nativeBridge: bridge, prefs: prefs);
///   watchdog.start();   // Call after real-time protection is enabled
///   watchdog.stop();    // Call when protection is disabled
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServiceWatchdog {
  ServiceWatchdog({
    this.checkIntervalSeconds = 30,
    this.maxRestartAttempts = 5,
  });

  /// How often the watchdog polls the service health (default 30 s).
  final int checkIntervalSeconds;

  /// Give up restarting after this many consecutive failures to avoid
  /// battery drain on devices where the service cannot stay alive at all.
  final int maxRestartAttempts;

  static const _channel = MethodChannel('com.riskguard/service_watchdog');
  static const _prefLastHeartbeat = 'watchdog_last_heartbeat_ms';
  static const _prefRestartCount = 'watchdog_restart_count';

  Timer? _timer;
  bool _running = false;
  int _consecutiveFailures = 0;

  bool get isRunning => _running;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Start periodic health checks.
  void start() {
    if (_running) return;
    _running = true;
    _consecutiveFailures = 0;
    dev.log('[Watchdog] Started — check every ${checkIntervalSeconds}s',
        name: 'ServiceWatchdog');
    _timer = Timer.periodic(
      Duration(seconds: checkIntervalSeconds),
      (_) => _check(),
    );
  }

  /// Stop and cancel the watchdog timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    dev.log('[Watchdog] Stopped', name: 'ServiceWatchdog');
  }

  /// Record a heartbeat — called by the overlay service periodically via
  /// method channel so the watchdog knows it is alive.
  Future<void> recordHeartbeat() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _prefLastHeartbeat, DateTime.now().millisecondsSinceEpoch);
    _consecutiveFailures = 0; // Reset on evidence of life
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<void> _check() async {
    if (!_running) return;

    final isAlive = await _isServiceAlive();
    if (isAlive) {
      _consecutiveFailures = 0;
      dev.log('[Watchdog] ✅ Service alive', name: 'ServiceWatchdog');
      return;
    }

    _consecutiveFailures++;
    dev.log(
      '[Watchdog] ⚠️  Service down — attempt $_consecutiveFailures/$maxRestartAttempts',
      name: 'ServiceWatchdog',
    );

    if (_consecutiveFailures > maxRestartAttempts) {
      dev.log(
        '[Watchdog] ❌ Max restart attempts reached — giving up to save battery.',
        name: 'ServiceWatchdog',
      );
      stop();
      return;
    }

    await _restartService();

    // Log restart count for diagnostics
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getInt(_prefRestartCount) ?? 0;
    await prefs.setInt(_prefRestartCount, prev + 1);
  }

  Future<bool> _isServiceAlive() async {
    try {
      // Fast path: ask native side
      final result =
          await _channel.invokeMethod<bool>('isServiceRunning') ?? false;
      return result;
    } on MissingPluginException {
      // No native implementation yet (web / desktop) — assume alive
      return true;
    } catch (e) {
      dev.log('[Watchdog] isServiceRunning error: $e', name: 'ServiceWatchdog');
      // Fallback: check heartbeat timestamp — if last heartbeat was more than
      // 2× the check interval ago, treat it as dead.
      return await _checkHeartbeatFallback();
    }
  }

  Future<bool> _checkHeartbeatFallback() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_prefLastHeartbeat) ?? 0;
      if (lastMs == 0) return true; // Never set — assume alive on first boot
      final elapsed =
          DateTime.now().millisecondsSinceEpoch - lastMs;
      final maxMs = checkIntervalSeconds * 2 * 1000;
      return elapsed < maxMs;
    } catch (_) {
      return true; // Safe default
    }
  }

  Future<void> _restartService() async {
    try {
      dev.log('[Watchdog] Restarting overlay service…',
          name: 'ServiceWatchdog');
      await _channel.invokeMethod<void>('restartService');
      dev.log('[Watchdog] 🔄 Restart signal sent', name: 'ServiceWatchdog');
    } on MissingPluginException {
      dev.log('[Watchdog] restartService: no native impl', name: 'ServiceWatchdog');
    } catch (e) {
      dev.log('[Watchdog] Restart failed: $e', name: 'ServiceWatchdog');
    }
  }
}
