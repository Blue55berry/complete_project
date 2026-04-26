import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/services/api_config.dart';
import 'package:risk_guard/core/services/permission_service.dart';
import 'package:risk_guard/core/services/user_settings_provider.dart';
import 'package:risk_guard/core/services/scan_history_provider.dart';
import 'package:risk_guard/core/services/realtime_protection_provider.dart';
import 'package:risk_guard/core/services/whitelist_provider.dart';
import 'package:risk_guard/core/services/api_service.dart';
import 'package:risk_guard/core/services/biometric_service.dart';
import 'package:risk_guard/core/services/native_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:risk_guard/screens/app_initializer.dart';
import 'package:risk_guard/screens/blockchain/evidence_tracker_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<UserSettingsProvider>();
    final whitelist = context.watch<WhitelistProvider>();

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // ── Profile Header ─────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primaryGold,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryGold.withValues(
                                  alpha: 0.2,
                                ),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: GestureDetector(
                            onTap: () => _pickProfileImage(settings),
                            child: Builder(
                              builder: (context) {
                                final img = _buildAvatarImage(settings);
                                return CircleAvatar(
                                  radius: 50,
                                  backgroundColor: AppColors.darkCard,
                                  backgroundImage: img,
                                  onBackgroundImageError: img != null ? (_, _) {} : null,
                                  child: img == null
                                      ? const Icon(
                                          Icons.person,
                                          size: 50,
                                          color: AppColors.textSecondary,
                                        )
                                      : null,
                                );
                              },
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => _pickProfileImage(settings),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primaryPurple,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.darkBackground,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      settings.displayName,
                      style: AppTextStyles.h3.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      settings.email,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'PRO MEMBER',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textOnGold,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: 0.1),

              const SizedBox(height: 32),


              // ── General ────────────────────────────────────────────────
              _buildSectionHeader('General'),
              const SizedBox(height: 12),
              _buildSettingsTile(
                icon: Icons.person_outline_rounded,
                title: 'Personal Info',
                subtitle: settings.displayName,
                onTap: () => _showEditProfileDialog(context, settings),
              ).animate().fadeIn(delay: 150.ms),
              const SizedBox(height: 12),
              FutureBuilder<String>(
                future: BiometricService().getBiometricLabel(),
                builder: (context, snap) {
                  final label = snap.data ?? 'Checking...';
                  return _buildSettingsTile(
                    icon: Icons.shield_outlined,
                    title: 'Security',
                    subtitle: settings.biometricsEnabled
                        ? 'Biometrics On ($label)'
                        : 'Biometrics Off',
                    onTap: () =>
                        _showSecuritySettingsDialog(context, settings),
                  );
                },
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 12),
              _buildSettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: settings.notificationsEnabled
                    ? 'Enabled'
                    : 'Disabled',
                onTap: () {},
                trailing: Switch(
                  value: settings.notificationsEnabled,
                  onChanged: (v) => settings.setNotificationsEnabled(v),
                  activeThumbColor: AppColors.primaryGold,
                  activeTrackColor: AppColors.primaryGold.withValues(
                    alpha: 0.3,
                  ),
                ),
              ).animate().fadeIn(delay: 250.ms),

              const SizedBox(height: 32),

              // ── Feature Controls (Master + Mini Toggles) ───────────────
              _buildSectionHeader('Feature Controls'),
              const SizedBox(height: 12),
              // Master toggle
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryGold.withValues(alpha: 0.15),
                      AppColors.primaryGold.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primaryGold.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGold.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.security_rounded,
                        color: AppColors.primaryGold,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Master Control',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${settings.activeShieldCount}/7 shields active',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.primaryGold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: settings.activeShieldCount == 7,
                      onChanged: (v) => settings.setAllFeaturesEnabled(v),
                      activeThumbColor: AppColors.primaryGold,
                      activeTrackColor: AppColors.primaryGold.withValues(
                        alpha: 0.3,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 12),
              // Mini toggles
              _buildFeatureToggle(
                icon: Icons.mic_outlined,
                title: 'Voice Detection',
                enabled: settings.voiceDetectionEnabled,
                onChanged: (v) => settings.setVoiceDetectionEnabled(v),
              ).animate().fadeIn(delay: 350.ms),
              const SizedBox(height: 8),
              _buildFeatureToggle(
                icon: Icons.image_outlined,
                title: 'Image Detection',
                enabled: settings.imageDetectionEnabled,
                onChanged: (v) => settings.setImageDetectionEnabled(v),
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 8),
              _buildFeatureToggle(
                icon: Icons.text_fields_rounded,
                title: 'Text Detection',
                enabled: settings.textDetectionEnabled,
                onChanged: (v) => settings.setTextDetectionEnabled(v),
              ).animate().fadeIn(delay: 450.ms),
              const SizedBox(height: 8),
              _buildFeatureToggle(
                icon: Icons.video_library_outlined,
                title: 'Video Detection',
                enabled: settings.videoDetectionEnabled,
                onChanged: (v) => settings.setVideoDetectionEnabled(v),
              ).animate().fadeIn(delay: 480.ms),
              const SizedBox(height: 8),
              _buildFeatureToggle(
                icon: Icons.link_rounded,
                title: 'Blockchain Reporting',
                enabled: settings.blockchainEnabled,
                onChanged: (v) => settings.setBlockchainEnabled(v),
              ).animate().fadeIn(delay: 500.ms),
              const SizedBox(height: 8),
              _buildFeatureToggle(
                icon: Icons.phone_in_talk_rounded,
                title: 'Call Monitoring',
                enabled: settings.callMonitoringEnabled,
                onChanged: (v) => _handleCallMonitoringToggle(v),
              ).animate().fadeIn(delay: 520.ms),
              const SizedBox(height: 8),
              _buildFeatureToggle(
                icon: Icons.share_rounded,
                title: 'Intelligence Sharing',
                enabled: settings.mediaSharingEnabled,
                onChanged: (v) => settings.setMediaSharingEnabled(v),
              ).animate().fadeIn(delay: 540.ms),

              const SizedBox(height: 32),

              // ── Privacy & Whitelist ────────────────────────────────────
              _buildSectionHeader('Privacy & Whitelist'),
              const SizedBox(height: 12),
              _buildSettingsTile(
                icon: Icons.apps_rounded,
                title: 'Whitelisted Apps',
                subtitle: whitelist.enabledCount > 0
                    ? '${whitelist.enabledCount} apps monitored'
                    : 'No apps monitored',
                onTap: () => _showWhitelistDialog(context, whitelist),
              ).animate().fadeIn(delay: 550.ms),

              const SizedBox(height: 32),

              // ── Data & Storage ─────────────────────────────────────────
              _buildSectionHeader('Data & Storage'),
              const SizedBox(height: 12),
              _buildSettingsTile(
                icon: Icons.delete_sweep_outlined,
                title: 'Clear Scan History',
                subtitle:
                    '${context.watch<ScanHistoryProvider>().totalScans} scans stored',
                onTap: () => _showClearHistoryDialog(context),
              ).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 12),
              _buildSettingsTile(
                icon: Icons.shield_rounded,
                title: 'Cybercrime Reports',
                subtitle: 'Track your submitted evidence',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EvidenceTrackerScreen(),
                    ),
                  );
                },
              ).animate().fadeIn(delay: 620.ms),

              const SizedBox(height: 32),

              // ── Support ────────────────────────────────────────────────
              _buildSectionHeader('Support'),
              const SizedBox(height: 12),
              _buildSettingsTile(
                icon: Icons.help_outline_rounded,
                title: 'Help Center',
                subtitle: 'FAQs and Support',
                onTap: () => _showHelpDialog(context),
              ).animate().fadeIn(delay: 650.ms),
              const SizedBox(height: 12),
              _buildSettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'About RiskGuard',
                subtitle: 'v3.0.0 (Pro Edition)',
                onTap: () => _showAboutDialog(context),
              ).animate().fadeIn(delay: 700.ms),
              const SizedBox(height: 12),
              _buildSettingsTile(
                icon: Icons.cloud_outlined,
                title: 'Backend URL',
                subtitle: settings.backendUrl == ApiConfig.defaultUrl
                    ? 'localhost (default)'
                    : settings.backendUrl.replaceFirst('https://', '').replaceFirst('http://', ''),
                onTap: () => _showBackendUrlDialog(context, settings),
              ).animate().fadeIn(delay: 720.ms),

              const SizedBox(height: 40),

              // ── Logout ─────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showLogoutDialog(context, settings),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerRed,
                    side: const BorderSide(color: AppColors.dangerRed),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 750.ms),



              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  // ── Avatar Helpers ──────────────────────────────────────────────────────

  ImageProvider? _buildAvatarImage(UserSettingsProvider settings) {
    if (settings.hasProfileImage) {
      return MemoryImage(settings.profileImageBytes!);
    }
    return null;
  }

  Future<void> _pickProfileImage(UserSettingsProvider settings) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 400,
        maxHeight: 400,
      );
      if (image == null) return;

      // Read bytes (works on both web and mobile)
      final bytes = await image.readAsBytes();
      await settings.setProfileImageBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile image updated'),
            backgroundColor: AppColors.successGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────

  void _showBackendUrlDialog(
    BuildContext context,
    UserSettingsProvider settings,
  ) {
    final controller = TextEditingController(text: settings.backendUrl);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Backend URL',
                style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your Cloudflared tunnel URL or use localhost for local testing. This updates ALL API connections.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              _buildTextField(
                'Backend URL',
                controller,
                Icons.cloud_outlined,
                hint: 'https://your-tunnel.trycloudflare.com',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        controller.text = ApiConfig.defaultUrl;
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Reset to Default'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final url = controller.text.trim();
                        await settings.setBackendUrl(url);
                        if (!context.mounted) return;
                        // Test connectivity
                        final healthy =
                            await ApiService().isBackendHealthy();
                        if (!context.mounted) return;
                        context
                            .read<RealtimeProtectionProvider>()
                            .checkBackendHealth();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              healthy
                                  ? '✅ Connected to backend'
                                  : '⚠️ URL saved but backend not reachable',
                            ),
                            backgroundColor: healthy
                                ? AppColors.successGreen
                                : Colors.orange,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGold,
                        foregroundColor: AppColors.darkBackground,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Save & Test',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditProfileDialog(
    BuildContext context,
    UserSettingsProvider settings,
  ) {
    final nameController = TextEditingController(text: settings.displayName);
    final emailController = TextEditingController(text: settings.email);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Edit Profile',
                style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _buildTextField('Display Name', nameController, Icons.person),
              const SizedBox(height: 16),
              _buildTextField('Email', emailController, Icons.email),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    settings.setDisplayName(nameController.text.trim());
                    settings.setEmail(emailController.text.trim());
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Profile updated'),
                        backgroundColor: AppColors.successGreen,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGold,
                    foregroundColor: AppColors.darkBackground,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    String? hint,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: TextStyle(
          color: AppColors.textTertiary.withValues(alpha: 0.5),
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: AppColors.primaryGold, size: 20),
        filled: true,
        fillColor: AppColors.darkBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primaryGold),
        ),
      ),
    );
  }

  void _showSecuritySettingsDialog(
    BuildContext context,
    UserSettingsProvider settings,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Security Settings',
              style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _buildSwitchRow(
              'Biometric Authentication',
              Icons.fingerprint,
              settings.biometricsEnabled,
              (v) async {
                final bio = BiometricService();
                if (v) {
                  final available = await bio.isAvailable();
                  if (!available) {
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Biometric hardware not available on this device',
                          ),
                          backgroundColor: AppColors.dangerRed,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    }
                    return;
                  }
                  final authenticated = await bio.authenticate(
                    reason: 'Verify your identity to enable biometrics',
                  );
                  if (!authenticated) {
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Authentication failed'),
                          backgroundColor: AppColors.dangerRed,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    }
                    return;
                  }
                }
                settings.setBiometricsEnabled(v);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        v ? 'Biometrics enabled' : 'Biometrics disabled',
                      ),
                      backgroundColor: v
                          ? AppColors.successGreen
                          : AppColors.textSecondary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
              },
            ),
            const Divider(color: AppColors.border, height: 32),
            Consumer<RealtimeProtectionProvider>(
              builder: (context, protection, child) {
                return _buildSwitchRow(
                  'Real-time Protection',
                  Icons.shield_rounded,
                  protection.isActive,
                  (v) async {
                    final activated = await context
                        .read<RealtimeProtectionProvider>()
                        .setProtection(v);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          activated == v
                              ? (v
                                    ? 'Real-time protection enabled'
                                    : 'Real-time protection disabled')
                              : 'RiskGuard could not enable real-time protection yet. Check overlay and accessibility access once, then try again.',
                        ),
                        backgroundColor: activated == v
                              ? (v
                                    ? AppColors.successGreen
                                    : AppColors.textSecondary)
                              : AppColors.dangerRed,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showWhitelistDialog(
    BuildContext context,
    WhitelistProvider whitelist,
  ) {
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filtered = searchQuery.isEmpty
              ? whitelist.apps
              : whitelist.apps
                  .where((a) => a.displayName
                      .toLowerCase()
                      .contains(searchQuery.toLowerCase()))
                  .toList();

          return Container(
            padding: const EdgeInsets.all(24),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            decoration: const BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'App Whitelist',
                          style: AppTextStyles.h3
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${whitelist.enabledCount}/${whitelist.totalCount} monitored',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primaryGold,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () async {
                            await whitelist.rescan();
                            setSheetState(() {});
                          },
                          icon: whitelist.isScanning
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryGold,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded,
                                  color: AppColors.primaryGold, size: 22),
                          tooltip: 'Rescan installed apps',
                        ),
                        TextButton(
                          onPressed: () {
                            if (whitelist.enabledCount ==
                                whitelist.apps.length) {
                              whitelist.disableAll();
                            } else {
                              whitelist.enableAll();
                            }
                            setSheetState(() {});
                          },
                          child: Text(
                            whitelist.enabledCount == whitelist.apps.length
                                ? 'Disable All'
                                : 'Enable All',
                            style: const TextStyle(
                              color: AppColors.primaryGold,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setSheetState(() => searchQuery = v),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search apps...',
                    hintStyle: TextStyle(
                      color: AppColors.textTertiary.withValues(alpha: 0.5),
                    ),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.textSecondary, size: 20),
                    filled: true,
                    fillColor: AppColors.darkBackground,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(
                      color: AppColors.border,
                      height: 1,
                    ),
                    itemBuilder: (ctx, index) {
                      final app = filtered[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: app.iconBytes != null ? Colors.transparent : app.brandColorValue,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: app.isEnabled
                                  ? AppColors.primaryGold.withValues(alpha: 0.8)
                                  : app.brandColorValue.withValues(alpha: 0.5),
                              width: app.isEnabled ? 2.0 : 1.0,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Center(
                              child: app.iconBytes != null
                                  ? Image.memory(
                                      app.iconBytes!,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                    )
                                  : Text(
                                      app.displayName.isNotEmpty
                                          ? app.displayName[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: _textColorForBg(app.brandColorValue),
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        title: Text(
                          app.displayName,
                          style: AppTextStyles.bodyMedium
                              .copyWith(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          app.category +
                              (app.isSystemDetected ? '' : ' \u2022 Manual'),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                        trailing: Switch(
                          value: app.isEnabled,
                          onChanged: (v) {
                            whitelist.setAppEnabled(app.packageName, v);
                            setSheetState(() {});
                          },
                          activeThumbColor: AppColors.primaryGold,
                          activeTrackColor:
                              AppColors.primaryGold.withValues(alpha: 0.3),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Returns white or black text color for best contrast on [bg]
  Color _textColorForBg(Color bg) {
    return bg.computeLuminance() > 0.4 ? Colors.black87 : Colors.white;
  }



  Widget _buildSwitchRow(
    String label,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryGold, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primaryGold,
          activeTrackColor: AppColors.primaryGold.withValues(alpha: 0.3),
        ),
      ],
    );
  }

  void _showClearHistoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear History?',
          style: AppTextStyles.h4.copyWith(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'All scan history will be permanently deleted. This cannot be undone.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              context.read<ScanHistoryProvider>().clearHistory();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Scan history cleared'),
                  backgroundColor: AppColors.primaryGold,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
            child: const Text(
              'Clear',
              style: TextStyle(
                color: AppColors.dangerRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Help Center',
              style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildHelpItem(
              Icons.mic_rounded,
              'Voice Analysis',
              'Record audio to detect AI-generated voices',
            ),
            _buildHelpItem(
              Icons.image_rounded,
              'Image Detection',
              'Upload images to check for AI manipulation',
            ),
            _buildHelpItem(
              Icons.message_rounded,
              'Text Analysis',
              'Verify messages for scam patterns',
            ),
            _buildHelpItem(
              Icons.shield_rounded,
              'Real-time Protection',
              'Enable the master toggle for live monitoring',
            ),
            _buildHelpItem(
              Icons.apps_rounded,
              'App Whitelist',
              'Choose which apps to monitor for threats',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.darkBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.email_rounded,
                    color: AppColors.primaryGold,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'support@riskguard.io',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primaryGold, size: 20),
          ),
          const SizedBox(width: 14),
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
                  desc,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: AppColors.goldGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: Colors.black,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'RiskGuard',
              style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'v3.0.0 Pro Edition',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.darkBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _buildAboutRow('Backend', 'FastAPI v3.0.0'),
                  _buildAboutRow('AI Models', 'HuggingFace Transformers'),
                  _buildAboutRow('Storage', 'Hive (local)'),
                  _buildAboutRow('Blockchain', 'Polygon Amoy Testnet'),
                  _buildAboutRow('Platform', 'Android + Web'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FutureBuilder<bool>(
              future: _checkBackendHealth(),
              builder: (context, snapshot) {
                final isHealthy = snapshot.data ?? false;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (isHealthy
                                ? AppColors.successGreen
                                : AppColors.dangerRed)
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          (isHealthy
                                  ? AppColors.successGreen
                                  : AppColors.dangerRed)
                              .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isHealthy
                              ? AppColors.successGreen
                              : AppColors.dangerRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isHealthy
                            ? 'Backend Connected'
                            : 'Backend Not Available',
                        style: TextStyle(
                          color: isHealthy
                              ? AppColors.successGreen
                              : AppColors.dangerRed,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _checkBackendHealth() async {
    try {
      return await ApiService().isBackendHealthy();
    } catch (_) {
      return false;
    }
  }

  void _showLogoutDialog(BuildContext context, UserSettingsProvider settings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Log Out?',
          style: AppTextStyles.h4.copyWith(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Your local settings and scan history will be cleared.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              // 1. Stop ALL active services and close overlay
              try {
                final protection = context.read<RealtimeProtectionProvider>();
                if (protection.isActive) {
                  await protection.setProtection(false);
                }
              } catch (e) {
                debugPrint('Logout: Failed to stop services: $e');
              }

              // 2. Nuclear wipe — clear ALL provider data
              try {
                await settings.clearAll();
              } catch (e) {
                debugPrint('Logout: settings.clearAll failed: $e');
              }
              if (!context.mounted) return;
              try { await context.read<ScanHistoryProvider>().clearHistory(); } catch (_) {}
              if (!context.mounted) return;
              try { await context.read<WhitelistProvider>().clearAll(); } catch (_) {}

              // 3. Clear native Android protection state that lives outside Flutter prefs
              try {
                await NativeBridge.clearNativeProtectionState();
              } catch (e) {
                debugPrint('Logout: Native protection clear failed: $e');
              }

              // 4. Clear the first-launch flags and FlutterSharedPreferences keys
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
              } catch (e) {
                debugPrint('Logout: SharedPreferences clear failed: $e');
              }

              // 5. Close dialog, then navigate to fresh start
              if (ctx.mounted) Navigator.pop(ctx);

              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const AppInitializer()),
                  (route) => false,
                );
              }
            },
            child: const Text(
              'Log Out',
              style: TextStyle(
                color: AppColors.dangerRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reusable Widgets ──────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 1.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            color: AppColors.darkBackground,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.primaryGold, size: 24),
        ),
        title: Text(
          title,
          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          subtitle,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        trailing:
            trailing ??
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
            ),
      ),
    );
  }

  Widget _buildFeatureToggle({
    required IconData icon,
    required String title,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled
              ? AppColors.primaryGold.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: enabled ? AppColors.primaryGold : AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w500,
                color: enabled
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onChanged,
            activeThumbColor: AppColors.primaryGold,
            activeTrackColor: AppColors.primaryGold.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCallMonitoringToggle(bool enabled) async {
    final settings = context.read<UserSettingsProvider>();

    if (!enabled) {
      await settings.setCallMonitoringEnabled(false);
      return;
    }

    final permissionState =
        await PermissionService.ensureCallMonitoringPermissions();
    if (!mounted) return;

    if (!permissionState.isReady) {
      await settings.setCallMonitoringEnabled(false);
      if (!mounted) return;
      await NativeBridge.sendMessageToOverlay({'action': 'stop'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Allow ${permissionState.missingSummary} access before enabling Call Monitoring.',
          ),
          backgroundColor: AppColors.dangerRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    await settings.setCallMonitoringEnabled(true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Call Monitoring enabled successfully.'),
        backgroundColor: AppColors.successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
