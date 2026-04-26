import 'package:flutter/material.dart';

/// App-wide color palette for RiskGuard
/// App-wide color palette for RiskGuard
class AppColors {
  AppColors._();

  // Dark Background Colors
  static const Color darkBackground = Color(0xFF050505); // Deep black
  static const Color darkSurface = Color(0xFF121212);
  static const Color darkCard = Color(0xFF1E1E24);
  static const Color darkCardLight = Color(0xFF2A2A35);

  // Primary Accents (Gold/Yellow)
  static const Color primaryGold = Color(0xFFFFD700);
  static const Color primaryYellow = Color(0xFFFFC107);
  static const Color accentGold = Color(0xFFFFB512);

  // Secondary Accents (Purple)
  static const Color primaryPurple = Color(0xFF6C63FF);
  static const Color deepPurple = Color(0xFF4A148C);
  static const Color purpleGlow = Color(0xFF9D4EDD);

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color successGreen = Color(0xFF00E676);
  static const Color danger = Color(0xFFFF5252);
  static const Color dangerRed = Color(0xFFD50000);
  static const Color warning = Color(0xFFFFAB00);
  static const Color info = Color(0xFF2196F3);

  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textTertiary = Color(0xFF757575);
  static const Color textOnGold = Color(0xFF000000);

  // Border Colors
  static const Color border = Color(0xFF2C2C2C);
  static const Color borderLight = Color(0xFF3E3E3E);

  // Gradient Colors
  static const Color gradientStart = Color(0xFF232526);
  static const Color gradientEnd = Color(0xFF414345);

  // Glassmorphic overlay
  static Color glassBg = const Color(0xFF2A2A35).withValues(alpha: 0.5);
  static Color glassStroke = const Color(0xFFFFFFFF).withValues(alpha: 0.1);

  // Gradients
  static LinearGradient goldGradient = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryGold, primaryYellow],
  );

  static LinearGradient purpleGradient = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryPurple, deepPurple],
  );

  static LinearGradient darkGradient = const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [darkBackground, Color(0xFF121212)],
  );
}
