import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/constants/app_constants.dart';

/// Custom animated toggle switch with smooth transitions
class AnimatedToggleSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final double width;
  final double height;

  const AnimatedToggleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 46,
    this.height = 24,
  });

  @override
  State<AnimatedToggleSwitch> createState() => _AnimatedToggleSwitchState();
}

class _AnimatedToggleSwitchState extends State<AnimatedToggleSwitch>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _circleAnimation;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppConstants.normalAnimation,
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
    );

    _circleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _colorAnimation = ColorTween(
      begin: AppColors.textTertiary,
      end: AppColors.primaryGold,
    ).animate(_controller);
  }

  @override
  void didUpdateWidget(AnimatedToggleSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onChanged(!widget.value);
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: _colorAnimation.value?.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(widget.height / 2),
              border: Border.all(
                color: _colorAnimation.value ?? AppColors.textTertiary,
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(2),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: AppConstants.normalAnimation,
                  curve: Curves.easeInOut,
                  left: _circleAnimation.value * (widget.width - widget.height),
                  child: Container(
                    width: widget.height - 4,
                    height: widget.height - 4,
                    decoration: BoxDecoration(
                      color: _colorAnimation.value,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:
                              (_colorAnimation.value ?? AppColors.textTertiary)
                                  .withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
