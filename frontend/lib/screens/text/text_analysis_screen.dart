import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/services/api_service.dart';
import 'package:risk_guard/core/models/analysis_models.dart';
import 'package:risk_guard/core/services/scan_history_provider.dart';
import 'package:risk_guard/core/widgets/result_bottom_sheet.dart';
import 'package:risk_guard/screens/blockchain/blockchain_report_screen.dart';

/// Text / Message analysis screen — paste suspicious text for phishing & AI detection
class TextAnalysisScreen extends StatefulWidget {
  const TextAnalysisScreen({super.key});

  @override
  State<TextAnalysisScreen> createState() => _TextAnalysisScreenState();
}

class _TextAnalysisScreenState extends State<TextAnalysisScreen> {
  final TextEditingController _textController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isAnalyzing = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _analyzeText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isAnalyzing = true);

    try {
      final result = await _apiService.analyzeText(text);

      if (mounted) {
        setState(() => _isAnalyzing = false);

        if (result.isSuccess && result.data != null) {
          _showTextResult(result.data!);
        } else {
          _showError(result.error ?? 'Text analysis failed');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        _showError('Analysis error: $e');
      }
    }
  }

  void _showTextResult(TextAnalysisResult data) {
    context.read<ScanHistoryProvider>().addScan(
      ScanHistoryEntry(
        id: const Uuid().v4(),
        type: ScanType.text,
        timestamp: DateTime.now(),
        riskLevel: data.riskScore >= 70
            ? 'HIGH'
            : (data.riskScore >= 30 ? 'MEDIUM' : 'LOW'),
        riskScore: data.riskScore,
        summary: data.isSafe ? 'Safe Text' : 'Threat Detected',
        explanation: data.explanation,
      ),
    );

    final metrics = <String, String>{
      'Risk Score': '${data.riskScore}/100',
      'AI Generated': '${(data.aiGeneratedProbability * 100).round()}%',
      'Confidence': '${(data.aiConfidence * 100).round()}%',
      'Method': data.analysisMethod,
    };

    ResultBottomSheet.show(
      context: context,
      title: data.isSafe ? 'Text Looks Safe' : 'Threat Detected',
      explanation: data.explanation.isNotEmpty
          ? data.explanation
          : data.aiExplanation,
      resultColor: data.isSafe ? AppColors.successGreen : AppColors.dangerRed,
      resultIcon: data.isSafe
          ? Icons.check_circle_rounded
          : Icons.warning_rounded,
      metrics: metrics,
      chips: [...data.threats, ...data.patterns],
      onReportToBlockchain: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BlockchainReportScreen(
              imageBytes: utf8.encode(_textController.text),
              threatType: data.isSafe ? 'Other' : (data.threats.isNotEmpty ? data.threats.first : 'Other'),
              aiResult: data.isSafe ? 'Safe' : 'Threat',
              confidence: data.riskScore / 100,
              filename: 'text_evidence.txt',
            ),
          ),
        );
      },
    );
  }

  void _showError(String error) {
    ResultBottomSheet.show(
      context: context,
      title: 'Analysis Failed',
      explanation: error,
      resultColor: AppColors.dangerRed,
      resultIcon: Icons.error_outline,
      buttonText: 'OK',
    );
  }

  void _loadExample(String example) {
    _textController.text = example;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Text Analysis',
                        style: AppTextStyles.h2
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Paste message, email, or URL to scan',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primaryPurple.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.text_snippet_rounded,
                      color: AppColors.primaryPurple,
                      size: 24,
                    ),
                  ),
                ],
              ).animate().fadeIn().slideX(begin: -0.1),

              const SizedBox(height: 24),

              // Quick Examples
              Text(
                'QUICK EXAMPLES',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickChip(
                      '🔗 Phishing Link',
                      'URGENT: Your account will be suspended! Click here to verify: http://secure-bank-login.tk/verify',
                    ),
                    const SizedBox(width: 8),
                    _buildQuickChip(
                      '🤖 AI Message',
                      'I hope this message finds you well. As an AI language model, I can provide comprehensive analysis and detailed insights into various topics.',
                    ),
                    const SizedBox(width: 8),
                    _buildQuickChip(
                      '✅ Normal Text',
                      'Hey, are you coming to the meeting tomorrow at 3 PM? Let me know if you need a ride.',
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 20),

              // Text Input Area
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isAnalyzing
                        ? AppColors.primaryPurple.withValues(alpha: 0.6)
                        : AppColors.border,
                    width: _isAnalyzing ? 2 : 1,
                  ),
                  boxShadow: _isAnalyzing
                      ? [
                          BoxShadow(
                            color: AppColors.primaryPurple.withValues(alpha: 0.1),
                            blurRadius: 20,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _textController,
                      maxLines: 8,
                      minLines: 5,
                      enabled: !_isAnalyzing,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Paste suspicious text, message, or URL here...',
                        hintStyle: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textTertiary,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(20),
                      ),
                    ),
                    // Character count & clear
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ValueListenableBuilder(
                            valueListenable: _textController,
                            builder: (_, _, _) => Text(
                              '${_textController.text.length} characters',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                          if (_textController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () => _textController.clear(),
                              child: Text(
                                'Clear',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.primaryGold,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),

              const SizedBox(height: 20),

              // Analyze Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isAnalyzing ? null : _analyzeText,
                  icon: _isAnalyzing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.darkBackground,
                          ),
                        )
                      : const Icon(Icons.search_rounded, size: 20),
                  label: Text(
                    _isAnalyzing ? 'Analyzing...' : 'Scan for Threats',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGold,
                    foregroundColor: AppColors.darkBackground,
                    disabledBackgroundColor:
                        AppColors.primaryGold.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 28),

              // What we check
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What we check',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCheckItem(
                      Icons.link_rounded,
                      'Phishing URLs',
                      'Detects fake/malicious links',
                      AppColors.dangerRed,
                    ),
                    _buildCheckItem(
                      Icons.smart_toy_rounded,
                      'AI-Generated Text',
                      'NLP analysis for synthetic writing',
                      AppColors.primaryPurple,
                    ),
                    _buildCheckItem(
                      Icons.warning_amber_rounded,
                      'Social Engineering',
                      'Urgency, fear, impersonation patterns',
                      Colors.orange,
                    ),
                    _buildCheckItem(
                      Icons.pattern_rounded,
                      'Scam Patterns',
                      'Known fraud templates & keywords',
                      AppColors.primaryGold,
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),

              const SizedBox(height: 100),
            ],
          ),
    );
  }

  Widget _buildQuickChip(String label, String text) {
    return GestureDetector(
      onTap: () => _loadExample(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildCheckItem(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
