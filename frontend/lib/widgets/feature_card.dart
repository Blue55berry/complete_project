import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/constants/app_constants.dart';
import 'glassmorphic_card.dart';
import 'animated_toggle_switch.dart';

/// Feature card component for displaying features like Voice Scan, SMS Check, etc.
class FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool hasToggle;
  final bool? isEnabled;
  final ValueChanged<bool>? onToggleChanged;
  final VoidCallback? onTap;
  final Color? iconColor;

  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.hasToggle = false,
    this.isEnabled,
    this.onToggleChanged,
    this.onTap,
    this.iconColor,
  });

  @override
  State<FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<FeatureCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: AppConstants.fastAnimation,
        child: GlassmorphicCard(
          backgroundColor: AppColors.darkCard.withValues(alpha: 0.6),
          borderRadius: AppConstants.radiusLarge,
          padding: const EdgeInsets.all(AppConstants.spaceLarge),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (widget.iconColor ?? AppColors.primaryGold).withValues(
                    alpha: 0.2,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  color: widget.iconColor ?? AppColors.primaryGold,
                  size: AppConstants.iconMedium,
                ),
              ),
              const SizedBox(width: AppConstants.spaceMedium),

              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: AppTextStyles.h4),
                    const SizedBox(height: AppConstants.spaceXSmall),
                    Text(
                      widget.subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primaryGold,
                      ),
                    ),
                  ],
                ),
              ),

              // Toggle or arrow
              if (widget.hasToggle && widget.isEnabled != null)
                AnimatedToggleSwitch(
                  value: widget.isEnabled!,
                  onChanged: widget.onToggleChanged ?? (_) {},
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                  size: AppConstants.iconMedium,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
