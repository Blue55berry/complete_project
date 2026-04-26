import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:isolate';

// The callback function for the foreground task
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(RiskGuardTaskHandler());
}

class RiskGuardTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) async {
    debugPrint('Foreground task started at $timestamp');
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    // This runs every 'interval' ms.
    // We could check the current app here or perform fast scans.
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) async {
    debugPrint('Foreground task destroyed at $timestamp');
  }
}

class ForegroundServiceHandler {
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'riskguard_foreground_service',
        channelName: 'Real-time Protection',
        channelDescription: 'Monitors active apps for threats',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> startService() async {
    if (await FlutterForegroundTask.isRunningService) {
      return true;
    }

    return await FlutterForegroundTask.startService(
      notificationTitle: 'RiskGuard Protection Active',
      notificationText: 'Monitoring system for threats',
      callback: startCallback,
    );
  }

  static Future<bool> stopService() async {
    return await FlutterForegroundTask.stopService();
  }
}
