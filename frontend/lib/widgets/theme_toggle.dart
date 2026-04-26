import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:risk_guard/core/theme/app_theme_provider.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/light_theme.dart';

/// Animated theme toggle widget
class ThemeToggle extends StatelessWidget {
  final double size;

  const ThemeToggle({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;

    return GestureDetector(
      onTap: () => themeProvider.toggleTheme(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: size * 2,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size / 2),
          color: isDark ? AppColors.darkCard : LightColors.lightCard,
          border: Border.all(
            color: isDark ? AppColors.glassStroke : LightColors.glassStroke,
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            // Toggle circle
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              left: isDark ? size * 0.05 : size * 1.05,
              top: size * 0.05,
              child: Container(
                width: size * 0.9,
                height: size * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? AppColors.primaryGold
                      : LightColors.primaryMint,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (isDark
                                  ? AppColors.primaryGold
                                  : LightColors.primaryMint)
                              .withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  isDark ? Icons.dark_mode : Icons.light_mode,
                  size: size * 0.5,
                  color: isDark ? AppColors.textOnGold : LightColors.textOnMint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
