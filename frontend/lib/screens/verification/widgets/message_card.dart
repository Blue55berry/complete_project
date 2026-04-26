import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/constants/app_constants.dart';

/// Message card showing the content to be verified
class MessageCard extends StatelessWidget {
  final String sender;
  final String time;
  final String message;
  final String link;
  final int votes;

  const MessageCard({
    super.key,
    required this.sender,
    required this.time,
    required this.message,
    required this.link,
    this.votes = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spaceLarge),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusXLarge),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGold.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Is this message safe\nor a scam?',
                  style: AppTextStyles.h3.copyWith(
                    color: AppColors.textOnGold,
                    fontSize: 22,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceSmall),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.textOnGold.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.shield_rounded,
                  color: AppColors.textOnGold,
                  size: AppConstants.iconMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceLarge),

          // Sender Info
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.textOnGold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_rounded,
                  color: AppColors.textOnGold,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSmall),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sender,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.textOnGold,
                    ),
                  ),
                  Text(
                    time,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textOnGold.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceMedium),

          // Message Content
          RichText(
            text: TextSpan(
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textOnGold,
              ),
              children: [
                TextSpan(
                  text: 'URGENT: ',
                  style: TextStyle(
                    color: AppColors.dangerRed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(text: message),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spaceSmall),

          // Link
          Text(
            'Verify now: $link',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textOnGold.withValues(alpha: 0.8),
              decoration: TextDecoration.underline,
            ),
          ),
          const SizedBox(height: AppConstants.spaceMedium),

          // Vote count
          Row(
            children: [
              Icon(
                Icons.thumb_up_rounded,
                size: 16,
                color: AppColors.textOnGold.withValues(alpha: 0.7),
              ),
              const SizedBox(width: AppConstants.spaceXSmall),
              Icon(
                Icons.thumb_down_rounded,
                size: 16,
                color: AppColors.textOnGold.withValues(alpha: 0.7),
              ),
              const SizedBox(width: AppConstants.spaceSmall),
              Text(
                '+1.2k voted',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textOnGold.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              Text(
                '@security_bot',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textOnGold.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
