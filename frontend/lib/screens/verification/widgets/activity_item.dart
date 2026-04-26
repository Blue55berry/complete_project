import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/constants/app_constants.dart';

/// Activity item showing user vote history
class ActivityItem extends StatelessWidget {
  final String name;
  final String role;
  final String vote;
  final String? avatarUrl;

  const ActivityItem({
    super.key,
    required this.name,
    required this.role,
    required this.vote,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isScam = vote == 'SCAM';

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMedium),
      margin: const EdgeInsets.only(bottom: AppConstants.spaceSmall),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
            child: Text(
              name[0].toUpperCase(),
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.primaryPurple,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceMedium),

          // Name and role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.labelLarge),
                Text(
                  role,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Vote badge
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceSmall,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: isScam
                  ? AppColors.dangerRed.withValues(alpha: 0.2)
                  : AppColors.successGreen.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
              border: Border.all(
                color: isScam ? AppColors.dangerRed : AppColors.successGreen,
                width: 1,
              ),
            ),
            child: Text(
              'VOTED $vote',
              style: AppTextStyles.labelSmall.copyWith(
                color: isScam ? AppColors.dangerRed : AppColors.successGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
