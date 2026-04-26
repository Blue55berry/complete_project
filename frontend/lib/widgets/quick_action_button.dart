import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';

/// Quick action button for features
class QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color iconColor;
  final VoidCallback? onTap;
  final bool isActive;

  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.iconColor = AppColors.primaryGold,
    this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circular button
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.darkCard,
              border: Border.all(
                color: isActive ? iconColor : AppColors.glassStroke,
                width: 2,
              ),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 6),
          // Label
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              height: 1.2,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
