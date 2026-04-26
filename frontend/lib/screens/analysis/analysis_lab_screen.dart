import 'package:flutter/material.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/screens/voice/voice_analysis_screen.dart';
import 'package:risk_guard/screens/text/text_analysis_screen.dart';

/// Combined Analysis Lab — Voice and Text analysis in sub-tabs
/// Replaces the Voice tab in bottom navigation
class AnalysisLabScreen extends StatefulWidget {
  const AnalysisLabScreen({super.key});

  @override
  State<AnalysisLabScreen> createState() => _AnalysisLabScreenState();
}

class _AnalysisLabScreenState extends State<AnalysisLabScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Tab Selector
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppColors.primaryGold,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: AppColors.darkBackground,
                  unselectedLabelColor: AppColors.textSecondary,
                  labelStyle: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelStyle: AppTextStyles.bodySmall,
                  padding: const EdgeInsets.all(4),
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mic_rounded, size: 18),
                          SizedBox(width: 6),
                          Text('Voice'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.text_snippet_rounded, size: 18),
                          SizedBox(width: 6),
                          Text('Text'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const BouncingScrollPhysics(),
                children: const [
                  VoiceAnalysisScreen(),
                  TextAnalysisScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
