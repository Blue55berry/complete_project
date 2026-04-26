import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/constants/app_constants.dart';

/// Large circular voting button for Real or Scam
class VotingButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isReal;
  final VoidCallback onTap;

  const VotingButton({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isReal,
    required this.onTap,
  });

  @override
  State<VotingButton> createState() => _VotingButtonState();
}

class _VotingButtonState extends State<VotingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Using colors since we switched from gradients for now
    final color = widget.isReal ? AppColors.successGreen : AppColors.dangerRed;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Column(
          children: [
            // Circular Button
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: color, size: 48),
            ),
            const SizedBox(height: AppConstants.spaceSmall),

            // Label
            Text(
              widget.label,
              style: AppTextStyles.h4.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.spaceXSmall),

            // Subtitle
            Text(
              widget.subtitle,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
