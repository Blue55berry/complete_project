import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/constants/app_constants.dart';
import 'package:risk_guard/core/services/api_service.dart';
import 'package:risk_guard/core/services/native_bridge.dart';
import 'package:risk_guard/core/models/analysis_models.dart';
import 'package:risk_guard/core/services/scan_history_provider.dart';
import 'package:risk_guard/core/widgets/result_bottom_sheet.dart';
import 'widgets/message_card.dart';
import 'widgets/voting_button.dart';
import 'widgets/activity_item.dart';

/// Message verification screen for voting on message safety
class MessageVerificationScreen extends StatefulWidget {
  const MessageVerificationScreen({super.key});

  @override
  State<MessageVerificationScreen> createState() =>
      _MessageVerificationScreenState();
}

class _MessageVerificationScreenState extends State<MessageVerificationScreen> {
  int currentQuestion = 1;
  final int totalQuestions = 3;
  final ApiService _apiService = ApiService();
  bool _isAnalyzing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLarge),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RiskGuard',
                    style: AppTextStyles.h3.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ).animate().fadeIn(delay: 100.ms),
                  Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.darkCard,
                          shape: BoxShape.circle,
                        ),
                        child: Stack(
                          children: [
                            const Center(
                              child: Icon(
                                Icons.notifications_rounded,
                                color: AppColors.textPrimary,
                                size: 20,
                              ),
                            ),
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.dangerRed,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 150.ms)
                      .scale(begin: const Offset(0.8, 0.8)),
                ],
              ),
            ),

            // Progress Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceLarge,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'QUESTION $currentQuestion OF $totalQuestions',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spaceSmall,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusSmall,
                          ),
                          border: Border.all(color: AppColors.info, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.info,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'LIVE',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.info,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 200.ms),
                  const SizedBox(height: AppConstants.spaceSmall),

                  // Progress Bar
                  ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusSmall,
                        ),
                        child: LinearProgressIndicator(
                          value: currentQuestion / totalQuestions,
                          backgroundColor: AppColors.border,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primaryGold,
                          ),
                          minHeight: 4,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 250.ms)
                      .scaleX(begin: 0, alignment: Alignment.centerLeft),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceLarge),

            // Main Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceLarge,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Message Card
                    const MessageCard(
                      sender: 'ServiceAlert',
                      time: 'Just now',
                      message: 'Your account is locked.',
                      link: 'bit.ly/fraud-check',
                    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2),
                    const SizedBox(height: AppConstants.spaceLarge),

                    // Voting Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        VotingButton(
                              icon: Icons.check_circle_rounded,
                              label: 'Real',
                              subtitle: 'Safe sender',
                              isReal: true,
                              onTap: () {
                                // Handle Real vote
                                _showVoteSuccess(true);
                              },
                            )
                            .animate()
                            .fadeIn(delay: 400.ms)
                            .scale(begin: const Offset(0.8, 0.8)),
                        VotingButton(
                              icon: Icons.warning_rounded,
                              label: 'Scam',
                              subtitle: 'Phishing',
                              isReal: false,
                              onTap: () {
                                // Handle Scam vote
                                _showVoteSuccess(false);
                              },
                            )
                            .animate()
                            .fadeIn(delay: 500.ms)
                            .scale(begin: const Offset(0.8, 0.8)),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spaceLarge),

                    // Recent Activity
                    Text(
                      'RECENT ACTIVITY',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ).animate().fadeIn(delay: 600.ms),
                    const SizedBox(height: AppConstants.spaceMedium),

                    const ActivityItem(
                      name: 'Sarah M.',
                      role: 'Security Analyst',
                      vote: 'SCAM',
                    ).animate().fadeIn(delay: 650.ms).slideX(begin: -0.1),
                    const ActivityItem(
                      name: 'David K.',
                      role: 'New Member',
                      vote: 'SCAM',
                    ).animate().fadeIn(delay: 700.ms).slideX(begin: -0.1),
                    const SizedBox(height: AppConstants.spaceXXLarge),
                  ],
                ),
              ),
            ),

            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.all(AppConstants.spaceLarge),
              decoration: BoxDecoration(
                color: AppColors.darkCard.withValues(alpha: 0.8),
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  // Avatar Carousel
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 5,
                        itemBuilder: (context, index) {
                          return Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: AppColors.textTertiary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.darkCard,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.person,
                              color: AppColors.darkCard,
                              size: 20,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // Action buttons
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.mic_off_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.darkCard,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSmall),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.more_horiz_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.darkCard,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSmall),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: AppColors.textPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.darkBackground,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 750.ms).slideY(begin: 0.5),
          ],
        ),
      ),
    );
  }

  void _showVoteSuccess(bool isReal) {
    // Analyze the message via the backend
    _analyzeMessage('Your account is locked. bit.ly/fraud-check');
  }

  Future<void> _analyzeMessage(String text) async {
    if (_isAnalyzing) return;
    setState(() => _isAnalyzing = true);

    // Notify overlay for text scan
    await NativeBridge.sendMessageToOverlay({
      'sessionKind': 'media',
      'sourcePackage': 'com.example.risk_guard',
      'targetType': 'text',
      'targetLabel': 'Message verification',
      'status': 'Analyzing text...',
      'analysisSource': 'manual_scan',
      'isThreat': false,
      'threatText': 'Verifying message content...',
    });

    final result = await _apiService.analyzeText(text);

    setState(() => _isAnalyzing = false);

    if (result.isSuccess && result.data != null) {
      final data = result.data!;
      
      // Success overlay update
      await NativeBridge.sendMessageToOverlay({
        'sessionKind': 'media',
        'sourcePackage': 'com.example.risk_guard',
        'targetType': 'text',
        'targetLabel': 'Message verification',
        'status': 'Scan Complete',
        'analysisSource': 'manual_scan',
        'isThreat': !data.isSafe,
        'threatText': data.isSafe ? 'Safe Message' : 'Potential Scamm Detected!',
        'riskScore': data.riskScore / 100,
        'threatType': 'Text Scam',
        'recommendation': data.isSafe
            ? 'No strong scam indicators were detected in the message.'
            : 'Avoid acting on the message until the sender and request are verified.',
      });

      // Store in scan history
      if (!mounted) return;
      context.read<ScanHistoryProvider>().addScan(
        ScanHistoryEntry(
          id: const Uuid().v4(),
          type: ScanType.text,
          timestamp: DateTime.now(),
          riskLevel: data.riskScore >= 60
              ? 'HIGH'
              : (data.riskScore >= 30 ? 'MEDIUM' : 'LOW'),
          riskScore: data.riskScore,
          summary: data.isSafe
              ? 'Text: Safe'
              : 'Text: ${data.threats.join(", ")}',
          explanation: data.explanation,
        ),
      );

      // Show detailed result bottom sheet
      _showAnalysisResultSheet(data);

      // Move to next question
      if (currentQuestion < totalQuestions) {
        setState(() => currentQuestion++);
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Analysis failed'),
          backgroundColor: AppColors.dangerRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          ),
        ),
      );
    }
  }

  void _showAnalysisResultSheet(TextAnalysisResult data) {
    final bool isSafe = data.isSafe;
    ResultBottomSheet.show(
      context: context,
      title: isSafe ? 'Safe Message' : 'Threat Detected',
      explanation: data.explanation,
      resultColor: isSafe ? AppColors.successGreen : AppColors.dangerRed,
      resultIcon: isSafe ? Icons.check_circle_rounded : Icons.warning_rounded,
      metrics: {
        'Risk Score': '${data.riskScore}%',
        'AI Generated': '${(data.aiGeneratedProbability * 100).round()}%',
      },
      chips: data.threats,
    );
  }
}
