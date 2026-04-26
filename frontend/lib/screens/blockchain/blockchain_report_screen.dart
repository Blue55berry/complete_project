import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/services/api_service.dart';
import 'package:risk_guard/core/models/analysis_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Blockchain Evidence Report Screen
/// Lets users file evidence to IPFS + blockchain after a threat is detected.
class BlockchainReportScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String threatType;
  final String aiResult;
  final double confidence;
  final String? filename;

  const BlockchainReportScreen({
    super.key,
    required this.imageBytes,
    required this.threatType,
    required this.aiResult,
    required this.confidence,
    this.filename,
  });

  @override
  State<BlockchainReportScreen> createState() => _BlockchainReportScreenState();
}

class _BlockchainReportScreenState extends State<BlockchainReportScreen> {
  final _profileUrlController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _api = ApiService();

  bool _isSubmitting = false;
  BlockchainReportResult? _result;
  String? _error;

  Future<void> _submitReport() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final result = await _api.fileBlockchainReport(
      imageBytes: widget.imageBytes,
      filename: widget.filename ?? 'evidence.png',
      profileUrl: _profileUrlController.text.trim(),
      threatType: widget.threatType,
      aiResult: widget.aiResult,
      confidence: widget.confidence,
      description: _descriptionController.text.trim(),
    );

    setState(() {
      _isSubmitting = false;
      if (result.isSuccess) {
        _result = result.data;
        SharedPreferences.getInstance().then((prefs) {
          final saved = prefs.getStringList('my_evidence_ids') ?? [];
          saved.add(result.data!.evidenceId.toString());
          prefs.setStringList('my_evidence_ids', saved);
        });
      } else {
        _error = result.error ?? 'Failed to submit evidence';
      }
    });
  }

  @override
  void dispose() {
    _profileUrlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Report to Cyber Cell'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _result != null ? _buildSuccess() : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primaryPurple.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.security,
                  color: AppColors.primaryPurple,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Report Evidence to Blockchain',
                style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Evidence will be hashed (SHA-256), uploaded to IPFS, and recorded in the Nimirdhu Nill Evidence Ledger.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),

        const SizedBox(height: 20),

        // Evidence Preview
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Evidence Preview',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 10),
              _buildMediaPreview(),
              const SizedBox(height: 12),
              _infoRow('AI Result', widget.aiResult),
              _infoRow('Confidence', '${(widget.confidence * 100).toInt()}%'),
              _infoRow('Threat Type', widget.threatType),
            ],
          ),
        ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

        const SizedBox(height: 20),

        // Profile URL Input
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PROFILE URL (OPTIONAL)',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _profileUrlController,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g., instagram.com/suspected_account',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: AppColors.darkBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primaryGold),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'DESCRIPTION (OPTIONAL)',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Add any additional context, description, or notes for the Cyber Cell investigation.',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: AppColors.darkBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primaryGold),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

        const SizedBox(height: 24),

        // Error
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _error!,
              style: TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),

        // Submit Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.security_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Authorize & Submit Report',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
          ),
        ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

        const SizedBox(height: 12),

        Center(
          child: Text(
            'By tapping Submit, you authorize RiskGuard to transmit this evidence to the Forensic Cyber Crime site.',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    final r = _result!;
    return Column(
      children: [
        // Success Badge
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.successGreen.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.successGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified,
                  color: AppColors.successGreen,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Evidence Filed Successfully',
                style: AppTextStyles.h3.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.successGreen,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Evidence has been hashed, uploaded to IPFS, and recorded in the Nimirdhu Nill Evidence Ledger.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95)),

        const SizedBox(height: 20),

        // Details
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EVIDENCE DETAILS',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              _infoRow('Evidence ID', '#${r.evidenceId}'),
              _infoRow(
                'SHA-256 Hash',
                r.fileHash.isNotEmpty
                    ? '${r.fileHash.substring(0, 16)}...'
                    : '—',
              ),
              _infoRow(
                'IPFS CID',
                r.ipfsCid.isNotEmpty ? '${r.ipfsCid.substring(0, 20)}...' : '—',
              ),
              _infoRow(
                'Status',
                r.anchored ? '✅ Blockchain Verified' : '⏳ Pending Anchor',
              ),
            ],
          ),
        ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

        const SizedBox(height: 24),

        // Done Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.maybePop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGold,
              foregroundColor: AppColors.darkBackground,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Done',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview() {
    final name = (widget.filename ?? '').toLowerCase();
    bool isImage =
        name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg');
    bool isAudio =
        name.endsWith('.wav') || name.endsWith('.mp3') || name.endsWith('.m4a');
    bool isText = name.endsWith('.txt');

    if (isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          widget.imageBytes,
          width: double.infinity,
          height: 180,
          fit: BoxFit.cover,
        ),
      );
    } else if (isText) {
      final text = utf8.decode(widget.imageBytes);
      return Container(
        width: double.infinity,
        height: 120,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.darkBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: SingleChildScrollView(
          child: Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              fontFamily: 'monospace',
              color: AppColors.primaryGold,
            ),
          ),
        ),
      );
    } else {
      // Audio or Unknown
      return Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.darkBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAudio
                    ? Icons.audiotrack_rounded
                    : Icons.insert_drive_file_rounded,
                color: AppColors.primaryGold,
                size: 40,
              ),
              const SizedBox(height: 8),
              Text(
                isAudio ? 'Audio Evidence' : 'Binary Evidence',
                style: AppTextStyles.labelSmall,
              ),
            ],
          ),
        ),
      );
    }
  }
}
