import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:risk_guard/core/services/biometric_service.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/screens/main_navigation_scaffold.dart';
import 'package:risk_guard/screens/onboarding/permission_request_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App Initializer:
/// 1. Shows permission request on first launch
/// 2. Shows biometric lock screen when biometrics are enabled
/// 3. Proceeds to MainNavigationScaffold
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isFirstLaunch = true;
  bool _isLoading = true;
  bool _biometricRequired = false;
  bool _isAuthenticated = false;
  bool _authFailed = false;
  bool _authInProgress = false;
  bool _initialAuthScheduled = false;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenPermissions = prefs.getBool('has_seen_permissions') ?? false;

    bool bioEnabled = false;
    try {
      final settingsBox = await Hive.openBox('user_settings');
      bioEnabled = settingsBox.get('biometricsEnabled', defaultValue: false);
    } catch (_) {}

    setState(() {
      _isFirstLaunch = !hasSeenPermissions;
      _biometricRequired = bioEnabled && !_isFirstLaunch;
      _isLoading = false;
    });

    _scheduleInitialAuthentication();
  }

  void _scheduleInitialAuthentication() {
    if (!_biometricRequired || _isAuthenticated || _initialAuthScheduled) {
      return;
    }

    _initialAuthScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_biometricRequired || _isAuthenticated) {
        return;
      }
      _authenticateUser();
    });
  }

  Future<void> _authenticateUser() async {
    if (_authInProgress) return;

    _authInProgress = true;
    if (mounted) {
      setState(() => _authFailed = false);
    }

    try {
      final bio = BiometricService();
      final isAvailable = await bio.isAvailable();

      if (!isAvailable) {
        if (mounted) {
          setState(() => _isAuthenticated = true);
        }
        return;
      }

      final success = await bio.authenticate(
        reason: 'Authenticate to access RiskGuard',
      );

      if (mounted) {
        setState(() {
          _isAuthenticated = success;
          _authFailed = !success;
        });
      }
    } finally {
      _authInProgress = false;
    }
  }

  Future<void> _onPermissionsComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_permissions', true);

    setState(() {
      _isFirstLaunch = false;
    });

    _scheduleInitialAuthentication();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleInitialAuthentication();

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/logo.png',
                width: 80,
                height: 80,
              ),
              const SizedBox(height: 16),
              Text(
                'RiskGuard',
                style: AppTextStyles.h2.copyWith(
                  color: AppColors.primaryGold,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isFirstLaunch) {
      return PermissionRequestScreen(
        onPermissionsGranted: _onPermissionsComplete,
      );
    }

    if (_biometricRequired && !_isAuthenticated) {
      return _buildLockScreen();
    }

    return const MainNavigationScaffold();
  }

  Widget _buildLockScreen() {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'RiskGuard is Locked',
                  style: AppTextStyles.h2.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Authenticate to access your security dashboard',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (_authFailed) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.dangerRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Authentication failed. Try again.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.dangerRed,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _authenticateUser,
                    icon: const Icon(Icons.fingerprint_rounded, size: 24),
                    label: Text(
                      _authFailed ? 'Try Again' : 'Unlock with Biometrics',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGold,
                      foregroundColor: AppColors.darkBackground,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Fingerprint, Face ID, or Device PIN',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
