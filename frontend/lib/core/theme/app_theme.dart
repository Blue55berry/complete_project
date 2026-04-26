import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import '../constants/app_constants.dart';

/// Dark theme configuration for RiskGuard
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // Color Scheme
      colorScheme: ColorScheme.dark(
        primary: AppColors.primaryGold,
        secondary: AppColors.primaryPurple,
        surface: AppColors.darkSurface,
        error: AppColors.danger,
        onPrimary: AppColors.textOnGold,
        onSecondary: AppColors.textPrimary,
        onSurface: AppColors.textPrimary,
        onError: AppColors.textPrimary,
      ),

      // Scaffold
      scaffoldBackgroundColor: AppColors.darkBackground,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),

      // Card
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
        ),
      ),

      // Text Theme
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme.copyWith(
          displayLarge: GoogleFonts.inter(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
          headlineLarge: GoogleFonts.inter(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
          headlineMedium: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
          bodyLarge: GoogleFonts.inter(
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
          bodyMedium: GoogleFonts.inter(
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
          labelMedium: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ),

      // Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGold,
          foregroundColor: AppColors.textOnGold,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceLarge,
            vertical: AppConstants.spaceMedium,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Icon Theme
      iconTheme: const IconThemeData(
        color: AppColors.textPrimary,
        size: AppConstants.iconMedium,
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          borderSide: const BorderSide(color: AppColors.primaryGold, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMedium,
          vertical: AppConstants.spaceMedium,
        ),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
