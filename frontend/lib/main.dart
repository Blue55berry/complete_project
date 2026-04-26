import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/light_theme.dart';
import 'core/theme/app_theme_provider.dart';
import 'core/theme/app_colors.dart';
import 'core/services/api_config.dart';
import 'core/services/scan_history_provider.dart';
import 'core/services/call_log_provider.dart';
import 'core/services/realtime_protection_provider.dart';
import 'core/services/user_settings_provider.dart';
import 'core/services/whitelist_provider.dart';
import 'core/services/model_download_service.dart';
import 'screens/app_initializer.dart';
import 'screens/voice/voice_analysis_screen.dart';
import 'screens/verification/message_verification_screen.dart';
import 'screens/overlay/risk_guard_overlay.dart';
import 'core/services/threat_intelligence_provider.dart';
import 'screens/intelligence/threat_intelligence_screen.dart';

@pragma('vm:entry-point')
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await ApiConfig.init();
  } catch (e) {
    debugPrint('🛡️ OverlayMain: ApiConfig.init failed (non-fatal): $e');
  }
  debugPrint('🛡️ OverlayMain: Starting overlay widget...');

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: RiskGuardOverlay(),
  ));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for cross-platform local storage
  await Hive.initFlutter();

  // Load dynamic backend URL (cloudflared tunnel support)
  await ApiConfig.init();

  // Set system UI overlay style for dark mode by default
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.darkBackground,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ScanHistoryProvider()),
        ChangeNotifierProvider(create: (_) => CallLogProvider()),
        ChangeNotifierProvider(create: (_) => RealtimeProtectionProvider()),
        ChangeNotifierProvider(create: (_) => UserSettingsProvider()),
        ChangeNotifierProvider(create: (_) => WhitelistProvider()),
        ChangeNotifierProvider(create: (_) => ThreatIntelligenceProvider()),
        ChangeNotifierProvider(create: (_) => ModelDownloadService()),
      ],
      child: const RiskGuardApp(),
    ),
  );
}

class RiskGuardApp extends StatefulWidget {
  const RiskGuardApp({super.key});

  @override
  State<RiskGuardApp> createState() => _RiskGuardAppState();
}

class _RiskGuardAppState extends State<RiskGuardApp> {
  @override
  void initState() {
    super.initState();
    // Load persisted state after the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScanHistoryProvider>().loadHistory();
      context.read<CallLogProvider>().loadLog();
      context.read<RealtimeProtectionProvider>().loadState();
      context.read<UserSettingsProvider>().init();
      context.read<WhitelistProvider>().loadState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    // Update system UI based on theme
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: themeProvider.isDarkMode
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarColor: themeProvider.isDarkMode
            ? AppColors.darkBackground
            : LightColors.lightBackground,
        systemNavigationBarIconBrightness: themeProvider.isDarkMode
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    return MaterialApp(
      title: 'RiskGuard',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: AppLightTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const AppInitializer(),
      routes: {
        '/voice': (context) => const VoiceAnalysisScreen(),
        '/verification': (context) => const MessageVerificationScreen(),
        '/intelligence': (context) => const ThreatIntelligenceScreen(),
      },
    );
  }
}
