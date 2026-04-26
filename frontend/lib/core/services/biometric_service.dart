import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Service for biometric authentication (fingerprint, face recognition).
/// Wraps `local_auth` with error handling and graceful degradation.
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final LocalAuthentication _auth = LocalAuthentication();

  /// Check if biometric hardware is available on this device
  Future<bool> isAvailable() async {
    try {
      // Don't attempt on web
      if (kIsWeb) return false;

      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheck || isDeviceSupported;
    } on PlatformException {
      return false;
    }
  }

  /// Get list of available biometric types (fingerprint, face, iris)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      if (kIsWeb) return [];
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  /// Authenticate user with biometrics.
  /// Returns true if authentication succeeded.
  Future<bool> authenticate({
    String reason = 'Authenticate to access RiskGuard',
  }) async {
    try {
      if (kIsWeb) return true; // Skip on web

      final isAvail = await isAvailable();
      if (!isAvail) return true; // No biometric hardware — allow access

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow PIN/pattern as fallback
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('BiometricService auth error: ${e.message}');
      return false;
    }
  }

  /// Get a human-readable label for available biometrics
  Future<String> getBiometricLabel() async {
    final types = await getAvailableBiometrics();
    if (types.isEmpty) return 'Not Available';
    if (types.contains(BiometricType.face)) return 'Face ID';
    if (types.contains(BiometricType.fingerprint)) return 'Fingerprint';
    if (types.contains(BiometricType.iris)) return 'Iris';
    return 'Device Lock';
  }
}
