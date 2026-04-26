import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/services/native_bridge.dart';

/// Screen shown at app launch to request permissions sequentially
class PermissionRequestScreen extends StatefulWidget {
  final VoidCallback onPermissionsGranted;

  const PermissionRequestScreen({
    super.key,
    required this.onPermissionsGranted,
  });

  @override
  State<PermissionRequestScreen> createState() =>
      _PermissionRequestScreenState();
}

class _PermissionRequestScreenState extends State<PermissionRequestScreen> {
  int _currentIndex = 0;
  bool _isRequesting = false;

  final List<dynamic> _permissionItems = [
    Permission.microphone,
    Permission.notification,
    Permission.phone,
    Permission.sms,
    'OVERLAY',
    'ACCESSIBILITY',
  ];

  @override
  Widget build(BuildContext context) {
    final currentItem = _permissionItems[_currentIndex];
    final progress = (_currentIndex + 1) / _permissionItems.length;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Progress Bar
              LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.darkCard,
                color: AppColors.primaryGold,
                borderRadius: BorderRadius.circular(4),
                minHeight: 6,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Step ${_currentIndex + 1} of ${_permissionItems.length}',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              const Spacer(),

              // Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryGold.withValues(alpha: 0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGold.withValues(alpha: 0.1),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  _getIconForItem(currentItem),
                  size: 50,
                  color: AppColors.primaryGold,
                ),
              ),

              const SizedBox(height: 40),

              // Title
              Text(
                _getNameForItem(currentItem),
                style: AppTextStyles.h2.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Description
              Text(
                _getDescriptionForItem(currentItem),
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(),

              // Allow Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isRequesting
                      ? null
                      : () => _handleItem(currentItem),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGold,
                    foregroundColor: AppColors.textOnGold,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isRequesting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AppColors.textOnGold,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Allow Access',
                          style: AppTextStyles.h4.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textOnGold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Skip Button
              TextButton(
                onPressed: _isRequesting ? null : _nextStep,
                child: Text(
                  'Skip for now',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleItem(dynamic item) async {
    setState(() => _isRequesting = true);

    if (item is Permission) {
      final status = await item.request();
      if (!status.isGranted) {
        if (mounted) {
          setState(() => _isRequesting = false);
        }
        return;
      }
    } else if (item == 'OVERLAY') {
      final granted = await NativeBridge.isOverlayPermissionGranted();
      if (!granted) {
        await NativeBridge.requestOverlayPermission();
        // We don't advance yet, let them come back
        setState(() => _isRequesting = false);
        return;
      }
    } else if (item == 'ACCESSIBILITY') {
      final granted = await NativeBridge.isAccessibilityPermissionGranted();
      if (!granted) {
        await NativeBridge.requestAccessibilityPermission();
        // We don't advance yet, let them come back
        setState(() => _isRequesting = false);
        return;
      }
    }

    _nextStep();
  }

  void _nextStep() {
    if (mounted) {
      setState(() {
        _isRequesting = false;
        if (_currentIndex < _permissionItems.length - 1) {
          _currentIndex++;
        } else {
          // Finished
          widget.onPermissionsGranted();
        }
      });
    }
  }

  IconData _getIconForItem(dynamic item) {
    if (item is Permission) {
      if (item == Permission.microphone) return Icons.mic_rounded;
      if (item == Permission.notification) return Icons.notifications_rounded;
      if (item == Permission.phone) return Icons.call_rounded;
      if (item == Permission.sms) return Icons.sms_rounded;
    } else {
      if (item == 'OVERLAY') return Icons.layers_rounded;
      if (item == 'ACCESSIBILITY') return Icons.security_rounded;
    }
    return Icons.settings;
  }

  String _getNameForItem(dynamic item) {
    if (item is Permission) {
      if (item == Permission.microphone) return 'Microphone Access';
      if (item == Permission.notification) return 'Notifications';
      if (item == Permission.phone) return 'Phone Access';
      if (item == Permission.sms) return 'SMS Filter';
    } else {
      if (item == 'OVERLAY') return 'Screen Overlay';
      if (item == 'ACCESSIBILITY') return 'Active Protection';
    }
    return 'Permission Required';
  }

  String _getDescriptionForItem(dynamic item) {
    if (item is Permission) {
      if (item == Permission.microphone) {
        return 'Required to analyze voice patterns and detect deepfake audio in real-time.';
      }
      if (item == Permission.notification) {
        return 'Stay informed about security threats and blocked scams instantly.';
      }
      if (item == Permission.phone) {
        return 'Needed to show the incoming and outgoing call protection overlay in real time.';
      }
      if (item == Permission.sms) {
        return 'Analyze incoming messages to filter out phishing attempts and malicious links.';
      }
    } else {
      if (item == 'OVERLAY') {
        return 'Show security alerts on top of other apps instantly when a threat is detected.';
      }
      if (item == 'ACCESSIBILITY') {
        return 'Critical for real-time monitoring of malicious links and identity theft attempts.\n\nSelect "RiskGuard Proactive Shield" in the list.';
      }
    }
    return 'This permission is needed for RiskGuard to function properly.';
  }
}
