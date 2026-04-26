import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;
import 'package:risk_guard/core/services/native_bridge.dart';

class CallMonitoringPermissionState {
  final bool phoneGranted;
  final bool overlayGranted;
  final bool accessibilityGranted;
  final bool contactsGranted;

  const CallMonitoringPermissionState({
    required this.phoneGranted,
    required this.overlayGranted,
    required this.accessibilityGranted,
    required this.contactsGranted,
  });

  bool get isReady => 
      phoneGranted && 
      overlayGranted && 
      accessibilityGranted && 
      contactsGranted;

  String get missingSummary {
    final missing = <String>[];
    if (!phoneGranted) missing.add('Phone');
    if (!overlayGranted) missing.add('Overlay');
    if (!accessibilityGranted) missing.add('Accessibility');
    if (!contactsGranted) missing.add('Contacts');
    return missing.join(', ');
  }
}

/// Service to handle all app permissions.
class PermissionService {
  /// Request all necessary permissions at app launch.
  static Future<Map<permission_handler.Permission, permission_handler.PermissionStatus>>
  requestAllPermissions() async {
    final Map<permission_handler.Permission, permission_handler.PermissionStatus>
    statuses = {};

    final List<permission_handler.Permission> permissions = [
      permission_handler.Permission.microphone,
      permission_handler.Permission.notification,
      permission_handler.Permission.sms,
      permission_handler.Permission.storage,
      permission_handler.Permission.photos,
      permission_handler.Permission.contacts,
    ];

    for (final permission in permissions) {
      final status = await permission.request();
      statuses[permission] = status;
    }

    return statuses;
  }

  static Future<bool> isPermissionGranted(
    permission_handler.Permission permission,
  ) async {
    return permission.isGranted;
  }

  static Future<bool> areAllCriticalPermissionsGranted() async {
    final microphone = await permission_handler.Permission.microphone.isGranted;
    final notification =
        await permission_handler.Permission.notification.isGranted;
    final sms = await permission_handler.Permission.sms.isGranted;

    return microphone && notification && sms;
  }

  static Future<bool> openAppSettings() async {
    return permission_handler.openAppSettings();
  }

  static Future<permission_handler.PermissionStatus> requestPermission(
    permission_handler.Permission permission,
  ) async {
    final status = await permission.status;

    if (status.isDenied) {
      return permission.request();
    }

    return status;
  }

  static String getPermissionName(permission_handler.Permission permission) {
    if (permission == permission_handler.Permission.microphone) {
      return 'Microphone';
    }
    if (permission == permission_handler.Permission.notification) {
      return 'Notifications';
    }
    if (permission == permission_handler.Permission.sms) return 'SMS';
    if (permission == permission_handler.Permission.storage) return 'Storage';
    if (permission == permission_handler.Permission.photos) return 'Photos';
    if (permission == permission_handler.Permission.phone) return 'Phone';
    return 'Unknown';
  }

  static String getPermissionDescription(
    permission_handler.Permission permission,
  ) {
    if (permission == permission_handler.Permission.microphone) {
      return 'Required for voice scan and scam detection';
    }
    if (permission == permission_handler.Permission.notification) {
      return 'Get alerts about security threats';
    }
    if (permission == permission_handler.Permission.sms) {
      return 'Scan messages for phishing attempts';
    }
    if (permission == permission_handler.Permission.storage) {
      return 'Access images for deepfake detection';
    }
    if (permission == permission_handler.Permission.photos) {
      return 'Analyze images for manipulation';
    }
    if (permission == permission_handler.Permission.phone) {
      return 'Required to monitor incoming and active calls';
    }
    return 'Required for app functionality';
  }

  static String getPermissionIcon(permission_handler.Permission permission) {
    if (permission == permission_handler.Permission.microphone) return 'Mic';
    if (permission == permission_handler.Permission.notification) {
      return 'Bell';
    }
    if (permission == permission_handler.Permission.sms) return 'SMS';
    if (permission == permission_handler.Permission.storage) return 'Files';
    if (permission == permission_handler.Permission.photos) return 'Photo';
    if (permission == permission_handler.Permission.phone) return 'Call';
    return 'Lock';
  }

  static Future<CallMonitoringPermissionState>
  getCallMonitoringPermissionState() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const CallMonitoringPermissionState(
        phoneGranted: true,
        overlayGranted: true,
        accessibilityGranted: true,
        contactsGranted: true,
      );
    }

    final phoneGranted = await permission_handler.Permission.phone.isGranted;
    final contactsGranted = await permission_handler.Permission.contacts.isGranted;
    final overlayGranted = await NativeBridge.isOverlayPermissionGranted();
    final accessibilityGranted =
        await NativeBridge.isAccessibilityPermissionGranted();

    return CallMonitoringPermissionState(
      phoneGranted: phoneGranted,
      overlayGranted: overlayGranted,
      accessibilityGranted: accessibilityGranted,
      contactsGranted: contactsGranted,
    );
  }

  static Future<CallMonitoringPermissionState>
  ensureCallMonitoringPermissions() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const CallMonitoringPermissionState(
        phoneGranted: true,
        overlayGranted: true,
        accessibilityGranted: true,
        contactsGranted: true,
      );
    }

    // 1. Phone permission
    final phoneStatus = await permission_handler.Permission.phone.status;
    if (!phoneStatus.isGranted) {
      final requestStatus = await permission_handler.Permission.phone.request();
      if (requestStatus.isPermanentlyDenied) {
        await permission_handler.openAppSettings();
      }
      return getCallMonitoringPermissionState();
    }

    // 2. Overlay permission
    final overlayGranted = await NativeBridge.isOverlayPermissionGranted();
    if (!overlayGranted) {
      await NativeBridge.requestOverlayPermission();
      // We return immediately because this opens Android Settings.
      // The app will check again via AppLifecycleState.resumed when they return.
      return getCallMonitoringPermissionState();
    }

    // 3. Accessibility permission
    final accessibilityGranted = await NativeBridge.isAccessibilityPermissionGranted();
    if (!accessibilityGranted) {
      await NativeBridge.requestAccessibilityPermission();
      // Return immediately for the same reason.
      return getCallMonitoringPermissionState();
    }

    // 4. Contacts permission
    final contactsStatus = await permission_handler.Permission.contacts.status;
    if (!contactsStatus.isGranted) {
      final requestStatus = await permission_handler.Permission.contacts.request();
      if (requestStatus.isPermanentlyDenied) {
        await permission_handler.openAppSettings();
      }
      return getCallMonitoringPermissionState();
    }

    return getCallMonitoringPermissionState();
  }
}
