import 'package:flutter/material.dart';

import 'package:risk_guard/core/constants/app_constants.dart';

/// Light theme color palette
class LightColors {
  // Background colors
  static const Color lightBackground = Color(0xFFF5F7FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFAFBFC);

  // Primary colors
  static const Color primaryMint = Color(0xFF6EDEC5);
  static const Color primaryTeal = Color(0xFF4ECDB7);

  // Text colors
  static const Color textPrimary = Color(0xFF1A1F26);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textOnMint = Color(0xFF0F1419);

  // Semantic colors
  static const Color success = Color(0xFF10B981);
  static const Color successGreen = Color(0xFF059669);
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerRed = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // Glassmorphic effects
  static final Color glassBg = const Color(0xFFFFFFFF).withValues(alpha: 0.7);
  static final Color glassStroke = const Color(
    0xFF000000,
  ).withValues(alpha: 0.1);

  // Gradients
  static const LinearGradient mintGradient = LinearGradient(
    colors: [Color(0xFF6EDEC5), Color(0xFF4ECDB7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFFE5E7EB), Color(0xFFD1D5DB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Light theme configuration
class AppLightTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      colorScheme: ColorScheme.light(
        primary: LightColors.primaryMint,
        secondary: LightColors.primaryTeal,
        surface: LightColors.lightSurface,
        error: LightColors.danger,
      ),

      scaffoldBackgroundColor: LightColors.lightBackground,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: LightColors.textPrimary),
        titleTextStyle: TextStyle(
          color: LightColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Card
      cardTheme: CardThemeData(
        color: LightColors.lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
        ),
      ),

      // Icon
      iconTheme: const IconThemeData(color: LightColors.textSecondary),

      // Divider
      dividerTheme: DividerThemeData(
        color: LightColors.textTertiary.withValues(alpha: 0.2),
        thickness: 1,
      ),
    );
  }
}
