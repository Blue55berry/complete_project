import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/constants/app_constants.dart';

/// Pill-style tab switcher for Overview/Network/Privacy
class TabSwitcher extends StatelessWidget {
  final int selectedIndex;
  final List<String> tabs;
  final ValueChanged<int> onTabChanged;

  const TabSwitcher({
    super.key,
    required this.selectedIndex,
    required this.tabs,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.primaryGold.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(
          tabs.length,
          (index) => Expanded(
            child: _TabItem(
              label: tabs[index],
              isSelected: selectedIndex == index,
              onTap: () => onTabChanged(index),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.normalAnimation,
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGold : Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelLarge.copyWith(
            color: isSelected ? AppColors.textOnGold : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
