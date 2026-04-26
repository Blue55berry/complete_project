import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/widgets/animated_toggle_switch.dart';

/// Compact feature card for the 2-column grid layout
class CompactFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final bool isEnabled;
  final ValueChanged<bool> onChanged;
  final bool isLarge;

  const CompactFeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.isEnabled,
    required this.onChanged,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isLarge ? 18 : 16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: isLarge ? _buildLargeCard() : _buildSmallCard(),
    );
  }

  Widget _buildLargeCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 28),
        ),
        const Spacer(),
        // Title
        Text(
          title.replaceAll(' ', '\n'),
          style: AppTextStyles.h4.copyWith(
            height: 1.1,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        // Subtitle
        Text(
          subtitle,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.8,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),
        // Toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ON',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
            AnimatedToggleSwitch(value: isEnabled, onChanged: onChanged),
          ],
        ),
      ],
    );
  }

  Widget _buildSmallCard() {
    return Row(
      children: [
        // Icon
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 12),
        // Text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        // Toggle
        AnimatedToggleSwitch(value: isEnabled, onChanged: onChanged),
      ],
    );
  }
}
