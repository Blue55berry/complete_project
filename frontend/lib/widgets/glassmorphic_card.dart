import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/constants/app_constants.dart';

/// A glassmorphic card widget with blur effect and semi-transparent background
class GlassmorphicCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final double blur;
  final VoidCallback? onTap;

  const GlassmorphicCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = AppConstants.radiusLarge,
    this.backgroundColor,
    this.borderColor,
    this.blur = AppConstants.blurMedium,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor ?? AppColors.glassBg,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? AppColors.glassStroke,
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(borderRadius),
                child: Padding(
                  padding:
                      padding ?? const EdgeInsets.all(AppConstants.spaceMedium),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
