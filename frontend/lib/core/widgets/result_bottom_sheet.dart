/// Reusable production-grade result bottom sheet.
/// Handles overflow by constraining max height and making content scrollable.
/// Shows analysis results in a polished, consistent format across all screens.
library;
import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';

class ResultBottomSheet {
  /// Show an analysis result bottom sheet with scroll support.
  /// [resultColor] — green for safe, red for threat, gold for moderate
  /// [resultIcon] — icon to show in the header circle
  /// [title] — main heading (e.g. "Authentic Image", "Threat Detected")
  /// [explanation] — detailed explanation from backend
  /// [metrics] — key-value metric pairs to show (e.g. {"AI Probability": "52%"})
  /// [chips] — detected patterns/threats shown as tag chips
  /// [borderColor] — accent color for top border (defaults to resultColor)
  static Future<void> show({
    required BuildContext context,
    required String title,
    required String explanation,
    required Color resultColor,
    IconData? resultIcon, // Optional now as we compute it
    bool isAi = false,
    bool isThreat = false,
    Map<String, String>? metrics,
    List<String>? chips,
    Color? borderColor,
    String buttonText = 'Done',
    VoidCallback? onReportToBlockchain,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled:
          true, // Required for DraggableScrollableSheet behavior
      builder: (context) => _ResultSheetContent(
        title: title,
        explanation: explanation,
        resultColor: resultColor,
        resultIcon: resultIcon ?? (isAi ? Icons.smart_toy : Icons.person),
        isAi: isAi,
        isThreat: isThreat,
        metrics: metrics,
        chips: chips,
        borderColor: borderColor ?? resultColor,
        buttonText: buttonText,
        onReportToBlockchain: onReportToBlockchain,
      ),
    );
  }
}
class _ResultSheetContent extends StatelessWidget {
  final String title;
  final String explanation;
  final Color resultColor;
  final IconData resultIcon;
  final Map<String, String>? metrics;
  final List<String>? chips;
  final Color borderColor;
  final String buttonText;
  final VoidCallback? onReportToBlockchain;
  final bool isAi;
  final bool isThreat;

  const _ResultSheetContent({
    required this.title,
    required this.explanation,
    required this.resultColor,
    required this.resultIcon,
    this.isAi = false,
    this.isThreat = false,
    this.metrics,
    this.chips,
    required this.borderColor,
    required this.buttonText,
    this.onReportToBlockchain,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: borderColor, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon Badge
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: resultColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(resultIcon, color: resultColor, size: 28),
                    ),

                    const SizedBox(height: 14),

                    // Title
                    Text(
                      title,
                      style: AppTextStyles.h3.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 10),

                    // Explanation — scrollable if long
                    Text(
                      explanation,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),

                    // Metrics Row
                    if (metrics != null && metrics!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.darkBackground.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.border.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: _buildMetrics(),
                        ),
                      ),
                    ],

                    // Chips
                    if (chips != null && chips!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: chips!.take(4).map((label) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: resultColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: resultColor.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: resultColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // Button — always pinned at bottom, never scrolls
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onReportToBlockchain != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onReportToBlockchain!();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(
                              0xFF6C63FF,
                            ).withValues(alpha: 0.15),
                            foregroundColor: const Color(0xFF6C63FF),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: const Color(
                                  0xFF6C63FF,
                                ).withValues(alpha: 0.4),
                              ),
                            ),
                            elevation: 0,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.link, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Report to Cyber Cell',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGold,
                        foregroundColor: AppColors.darkBackground,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        buttonText,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMetrics() {
    final entries = metrics!.entries.toList();
    final List<Widget> widgets = [];

    for (int i = 0; i < entries.length; i++) {
      if (i > 0) {
        widgets.add(
          Container(
            width: 1,
            height: 36,
            color: AppColors.border.withValues(alpha: 0.3),
          ),
        );
      }
      widgets.add(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entries[i].key,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              entries[i].value,
              style: AppTextStyles.bodyMedium.copyWith(
                color: resultColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return widgets;
  }
}
