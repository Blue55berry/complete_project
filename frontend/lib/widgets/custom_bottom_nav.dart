import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/constants/app_constants.dart';

/// Custom bottom navigation bar with smooth icon animations
class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppConstants.bottomNavHeight,
      margin: const EdgeInsets.all(AppConstants.spaceMedium),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppConstants.radiusXXLarge),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.history_rounded,
            isActive: currentIndex == 0,
            onTap: () => onTap(0),
          ),
          _NavItem(
            icon: Icons.mic_rounded,
            isActive: currentIndex == 1,
            onTap: () => onTap(1),
          ),
          _NavItem(
            icon: Icons.home_rounded,
            isActive: currentIndex == 2,
            onTap: () => onTap(2),
            isSpecial: true,
          ),
          _NavItem(
            icon: Icons.image_search_rounded,
            isActive: currentIndex == 3,
            onTap: () => onTap(3),
          ),
          _NavItem(
            icon: Icons.person_rounded,
            isActive: currentIndex == 4,
            onTap: () => onTap(4),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final bool isSpecial;

  const _NavItem({
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.isSpecial = false,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: -4.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(_NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.forward();
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Special styling for central/prominent button (Home)
    if (widget.isSpecial) {
      return GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: widget.isActive ? AppColors.primaryGold : AppColors.darkCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: AppColors.primaryGold.withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 0,
                    ),
                  ]
                : [],
          ),
          child: Icon(
            widget.icon,
            color: widget.isActive
                ? AppColors.darkBackground
                : AppColors.textSecondary,
            size: 28,
          ),
        ),
      );
    }

    // Regular nav item with smooth scale and slide animations
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _slideAnimation.value),
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.icon,
                      color: widget.isActive
                          ? AppColors.primaryGold
                          : AppColors.textSecondary.withValues(alpha: 0.6),
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      width: widget.isActive ? 4 : 0,
                      height: widget.isActive ? 4 : 0,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryGold,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
