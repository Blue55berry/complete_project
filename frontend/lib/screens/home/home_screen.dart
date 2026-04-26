import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/services/scan_history_provider.dart';
import 'package:risk_guard/core/services/realtime_protection_provider.dart';
import 'package:risk_guard/core/services/user_settings_provider.dart';
import 'package:risk_guard/core/services/model_download_service.dart';
import 'package:risk_guard/core/models/analysis_models.dart';

import 'widgets/security_status_card.dart';

/// Main home screen showing security overview
class HomeScreen extends StatefulWidget {
  final Function(int)? onSwitchTab;
  const HomeScreen({super.key, this.onSwitchTab});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final GlobalKey _bellKey = GlobalKey();
  OverlayEntry? _notifOverlay;

  @override
  void initState() {
    super.initState();
    // Check backend health when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RealtimeProtectionProvider>().checkBackendHealth();
    });
  }

  @override
  void dispose() {
    hideNotificationPanel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final historyProvider = context.watch<ScanHistoryProvider>();
    final protectionProvider = context.watch<RealtimeProtectionProvider>();
    final userSettings = context.watch<UserSettingsProvider>();
    final recentScans = historyProvider.recentEntries;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Stack(
          children: [
            // Main Content
            SingleChildScrollView(
              padding: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: 100, // Space for nav bar
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primaryGold,
                                width: 2,
                              ),
                            ),
                            child: Builder(
                              builder: (context) {
                                final img = _buildAvatarImage(userSettings);
                                return CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppColors.darkCard,
                                  backgroundImage: img,
                                  onBackgroundImageError: img != null ? (_, _) {} : null,
                                  child: img == null
                                      ? const Icon(
                                          Icons.person,
                                          color: AppColors.textSecondary,
                                        )
                                      : null,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome Back',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                userSettings.displayName,
                                style: AppTextStyles.h4.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Connection Status + Notification Bell
                      Row(
                        children: [
                          // Backend status indicator
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: protectionProvider.isBackendConnected
                                  ? AppColors.successGreen
                                  : AppColors.dangerRed,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (protectionProvider.isBackendConnected
                                              ? AppColors.successGreen
                                              : AppColors.dangerRed)
                                          .withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          // ── Notification Bell ────────────────────────────
                          GestureDetector(
                            key: _bellKey,
                            onTap: () => _showNotificationPanel(context,
                                historyProvider, protectionProvider),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.darkCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Stack(
                                children: [
                                  const Center(
                                    child: Icon(
                                      Icons.notifications_outlined,
                                      color: AppColors.textPrimary,
                                      size: 22,
                                    ),
                                  ),
                                  if (historyProvider.threatsBlocked > 0)
                                    Positioned(
                                      top: 10,
                                      right: 12,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppColors.primaryGold,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ).animate().fadeIn(delay: 100.ms).slideY(begin: -0.2),

                  const SizedBox(height: 24),

                  // Digital Security Card
                  const SecurityStatusCard()
                      .animate()
                      .fadeIn(delay: 200.ms)
                      .slideY(begin: 0.1),
                  const SizedBox(height: 16),

                  // World Intelligence Card (NEW)
                  _buildIntelligenceCard(context)
                      .animate()
                      .fadeIn(delay: 250.ms)
                      .slideY(begin: 0.1),
                  const SizedBox(height: 16),

                  // Risk Level & Active Shields
                  Row(
                    children: [
                      // Risk Level — dynamic based on scan history
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.darkCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getOverallRiskColor(
                                    historyProvider,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _getOverallRiskLabel(historyProvider),
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: _getOverallRiskColor(
                                      historyProvider,
                                    ),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _getOverallRiskMessage(historyProvider),
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Active Shields
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.darkCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.shield,
                                    color: protectionProvider.isActive
                                        ? AppColors.primaryPurple
                                        : AppColors.textSecondary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    protectionProvider.isActive
                                        ? '${userSettings.activeShieldCount} Active'
                                        : 'Inactive',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                protectionProvider.isActive
                                    ? 'Shields enabled'
                                    : 'Enable protection',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),

                  const SizedBox(height: 24),

                  // Security Log Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Security Log', style: AppTextStyles.h4),
                      Text(
                        '${historyProvider.totalScans} total',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primaryGold,
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 400.ms),
                  const SizedBox(height: 16),

                  // Security Log List — from scan history provider
                  if (recentScans.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'No scans yet. Use Voice, Image, or Text analysis to get started.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: 500.ms)
                  else
                    Column(
                      children: recentScans.take(5).map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildLogItem(
                            entry.summary,
                            entry.explanation.length > 50
                                ? '${entry.explanation.substring(0, 50)}...'
                                : entry.explanation,
                            _formatTimeAgo(entry.timestamp),
                            _getIconForScanType(entry.type),
                            _getColorForRiskLevel(entry.riskLevel),
                          ),
                        );
                      }).toList(),
                    ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dynamic helpers based on scan history ────────────────────────────────

  Color _getOverallRiskColor(ScanHistoryProvider provider) {
    if (provider.threatsBlocked > 0) return AppColors.dangerRed;
    if (provider.moderateThreats > 0) return Colors.orange;
    return AppColors.successGreen;
  }

  String _getOverallRiskLabel(ScanHistoryProvider provider) {
    if (provider.threatsBlocked > 0) return 'HIGH RISK';
    if (provider.moderateThreats > 0) return 'MODERATE';
    return 'LOW RISK';
  }

  String _getOverallRiskMessage(ScanHistoryProvider provider) {
    if (provider.totalScans == 0) return 'No scans yet';
    if (provider.threatsBlocked > 0) {
      return '${provider.threatsBlocked} threats found';
    }
    return 'Your device is safe';
  }

  IconData _getIconForScanType(ScanType type) {
    switch (type) {
      case ScanType.voice:
        return Icons.mic_none_rounded;
      case ScanType.image:
        return Icons.image_rounded;
      case ScanType.video:
        return Icons.videocam_rounded;
      case ScanType.text:
        return Icons.message_rounded;
    }
  }

  Color _getColorForRiskLevel(String level) {
    switch (level) {
      case 'HIGH':
        return AppColors.dangerRed;
      case 'MEDIUM':
        return Colors.orange;
      default:
        return AppColors.successGreen;
    }
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  ImageProvider? _buildAvatarImage(UserSettingsProvider settings) {
    if (settings.hasProfileImage) {
      return MemoryImage(settings.profileImageBytes!);
    }
    return null;
  }

  Widget _buildIntelligenceCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/intelligence'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E293B),
              AppColors.darkCard,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.cyanAccent.withValues(alpha: 0.05),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.public, color: Colors.cyanAccent, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'World Intelligence',
                        style: AppTextStyles.h4.copyWith(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ).animate(onPlay: (c) => c.repeat()).fadeOut(duration: 500.ms).fadeIn(duration: 500.ms),
                    ],
                  ),
                  Text(
                    'Real-time global threat feed & map',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(
    String title,
    String subtitle,
    String time,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            time,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Notification Panel Implementation ──────────────────────────────────────

  void _showNotificationPanel(
    BuildContext context,
    ScanHistoryProvider history,
    RealtimeProtectionProvider protection,
  ) {
    if (_notifOverlay != null) {
      _notifOverlay!.remove();
      _notifOverlay = null;
      return;
    }

    final RenderBox renderBox =
        _bellKey.currentContext!.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    _notifOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Dismiss barrier
          GestureDetector(
            onTap: () {
              _notifOverlay?.remove();
              _notifOverlay = null;
            },
            child: Container(color: Colors.transparent),
          ),
          // Panel
          Positioned(
            top: offset.dy + 56,
            right: 20,
            width: 300,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primaryGold.withValues(alpha: 0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Notifications',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          // ── TFLite Download Button ────────────────────────
                          Consumer<ModelDownloadService>(
                            builder: (context, downloadService, child) {
                              if (downloadService.allModelsExist) {
                                return const Icon(
                                  Icons.verified_rounded,
                                  color: AppColors.successGreen,
                                  size: 18,
                                );
                              }
                              if (downloadService.isDownloading) {
                                return SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    value: downloadService.progress,
                                    strokeWidth: 2,
                                    valueColor: const AlwaysStoppedAnimation(
                                        AppColors.primaryGold),
                                  ),
                                );
                              }
                              return InkWell(
                                onTap: () => downloadService.downloadModels(),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryGold.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.primaryGold.withValues(alpha: 0.3)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.download_for_offline_rounded,
                                        color: AppColors.primaryGold,
                                        size: 16,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'DL AI',
                                        style: TextStyle(
                                          color: AppColors.primaryGold,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primaryGold.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${history.threatsBlocked} Alerts',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.primaryGold,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    // Content
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: Consumer<ModelDownloadService>(
                        builder: (context, downloadService, child) {
                          return ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            children: [
                              if (downloadService.isDownloading)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      LinearProgressIndicator(
                                        value: downloadService.progress,
                                        backgroundColor: AppColors.darkBackground,
                                        valueColor: const AlwaysStoppedAnimation(AppColors.primaryGold),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        downloadService.statusMessage ?? 'Downloading...',
                                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.primaryGold),
                                      ),
                                    ],
                                  ),
                                ),
                              if (!protection.isBackendConnected)
                                _buildNotifItem(
                                  icon: Icons.cloud_off_rounded,
                                  color: AppColors.dangerRed,
                                  title: 'Server Disconnected',
                                  subtitle:
                                      'Proactive analysis is currently offline.',
                                  time: 'Now',
                                ),
                              if (protection.isActive)
                                _buildNotifItem(
                                  icon: Icons.verified_user_rounded,
                                  color: AppColors.successGreen,
                                  title: 'Shield Active',
                                  subtitle: 'Real-time protection is monitoring.',
                                  time: 'Active',
                                ),
                              ...history.recentEntries
                                  .where((e) => e.riskLevel == 'HIGH')
                                  .take(3)
                                  .map((e) => _buildNotifItem(
                                        icon: Icons.gpp_maybe_rounded,
                                        color: AppColors.dangerRed,
                                        title: 'Threat Blocked',
                                        subtitle: e.summary,
                                        time: _formatTimeAgo(e.timestamp),
                                      )),
                            ],
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    // Footer
                    TextButton(
                      onPressed: () {
                        hideNotificationPanel();
                        widget.onSwitchTab?.call(0);
                      },
                      child: Text(
                        'View All Activity',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primaryGold,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.05, end: 0),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_notifOverlay!);
  }

  void hideNotificationPanel() {
    _notifOverlay?.remove();
    _notifOverlay = null;
  }

  Widget _buildNotifItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String time,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
