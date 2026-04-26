import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';

/// Small stat item component for displaying numeric statistics
class StatItem extends StatelessWidget {
  final String value;
  final String label;

  const StatItem({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTextStyles.h4.copyWith(
            color: AppColors.textOnGold,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textOnGold.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
