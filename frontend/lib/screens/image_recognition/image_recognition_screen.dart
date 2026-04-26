import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/services/api_service.dart';
import 'package:risk_guard/core/services/native_bridge.dart';
import 'package:risk_guard/core/models/analysis_models.dart';
import 'package:risk_guard/core/services/scan_history_provider.dart';
import 'package:risk_guard/core/widgets/result_bottom_sheet.dart';
import 'package:risk_guard/screens/blockchain/blockchain_report_screen.dart';
import 'package:risk_guard/screens/blockchain/evidence_tracker_screen.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Image Recognition/Deepfake Detection screen
class ImageRecognitionScreen extends StatefulWidget {
  const ImageRecognitionScreen({super.key});

  @override
  State<ImageRecognitionScreen> createState() => _ImageRecognitionScreenState();
}

class _ImageRecognitionScreenState extends State<ImageRecognitionScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final ApiService _apiService = ApiService();
  XFile? _selectedFile;
  Uint8List? _imageBytes; // for cross-platform display
  Uint8List? _lastFileBytes;
  bool _isVideo = false;
  bool _isAnalyzing = false;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedFile = image;
          _imageBytes = bytes;
          _isVideo = false;
        });
        _analyzeMedia();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting image: $e')),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );

      if (video != null) {
        setState(() {
          _selectedFile = video;
          _imageBytes = null;
          _isVideo = true;
        });
        _analyzeMedia();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting video: $e')),
        );
      }
    }
  }

  Future<void> _analyzeMedia() async {
    if (_selectedFile == null) return;
    setState(() => _isAnalyzing = true);

    try {
      Uint8List? fileBytes;
      if (kIsWeb) {
        fileBytes = await _selectedFile!.readAsBytes();
      } else {
        fileBytes = await io.File(_selectedFile!.path).readAsBytes();
      }

      if (fileBytes.isEmpty) {
        if (mounted) {
          setState(() => _isAnalyzing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read file')),
          );
        }
        return;
      }

      _lastFileBytes = fileBytes;

      if (_isVideo) {
        // Fast Frame Sampling Optimization
        final List<Uint8List> sampledFrames = [];
        if (!kIsWeb) {
          // Extract 3 representative frames (start, middle, end)
          final offsets = [0, 5000, 10000]; // ms
          for (var offset in offsets) {
            final frame = await VideoThumbnail.thumbnailData(
              video: _selectedFile!.path,
              imageFormat: ImageFormat.JPEG,
              maxWidth: 512,
              quality: 75,
              timeMs: offset,
            );
            if (frame != null) sampledFrames.add(frame);
          }
        }

        final result = sampledFrames.isNotEmpty
            ? await _apiService.analyzeVideoFrames(
                sampledFrames,
                filename: _selectedFile!.name,
              )
            : await _apiService.analyzeVideo(
                fileBytes,
                filename: _selectedFile!.name,
              );

        setState(() {
          _isAnalyzing = false;
        });
        if (mounted) {
          if (result.isSuccess && result.data != null) {
            _showVideoResult(result.data!);
          } else {
            _showErrorResult(result.error ?? 'Video analysis failed');
          }
        }
      } else {
        // Notify overlay for image scan
        await NativeBridge.sendMessageToOverlay({
          'sessionKind': 'media',
          'sourcePackage': 'com.example.risk_guard',
          'targetType': 'image',
          'targetLabel': _selectedFile!.name,
          'status': 'Analyzing image...',
          'analysisSource': 'manual_scan',
          'isThreat': false,
          'threatText': 'Scanning pixels...',
        });

        final result = await _apiService.analyzeImage(
          fileBytes,
          filename: _selectedFile!.name,
        );
        
        setState(() {
          _isAnalyzing = false;
        });
        if (mounted) {
          if (result.isSuccess && result.data != null) {
            // Success overlay update
            await NativeBridge.sendMessageToOverlay({
              'sessionKind': 'media',
              'sourcePackage': 'com.example.risk_guard',
              'targetType': 'image',
              'targetLabel': _selectedFile!.name,
              'status': 'Scan Complete',
              'analysisSource': 'manual_scan',
              'isThreat': result.data!.isAiGenerated,
              'threatText': result.data!.isAiGenerated 
                  ? 'AI-Generated Content Detected!' 
                  : 'Authentic Image',
              'riskScore': result.data!.aiGeneratedProbability,
              'threatType': 'AI Image',
              'recommendation': result.data!.isAiGenerated
                  ? 'Treat the image as synthetic until verified by additional evidence.'
                  : 'No strong AI-generation indicators were found in this image.',
            });
            _showImageResult(result.data!);
          } else {
            _showErrorResult(result.error ?? 'Image analysis failed');
          }
        }
      }
    } catch (e) {
      setState(() => _isAnalyzing = false);
      if (mounted) {
        _showErrorResult('Analysis error: $e');
      }
    }
  }

  void _showImageResult(ImageAnalysisResult data) {
    context.read<ScanHistoryProvider>().addScan(
      ScanHistoryEntry(
        id: const Uuid().v4(),
        type: ScanType.image,
        timestamp: DateTime.now(),
        riskLevel: data.aiGeneratedProbability >= 0.7
            ? 'HIGH'
            : (data.aiGeneratedProbability >= 0.3 ? 'MEDIUM' : 'LOW'),
        riskScore: (data.aiGeneratedProbability * 100).round(),
        summary: data.isAiGenerated
            ? 'AI-Generated Detected'
            : 'Authentic Image',
        explanation: data.explanation,
      ),
    );

    final bool isAi = data.isAiGenerated;
    final bool hasThreat = data.aiGeneratedProbability > 0.65; // High prob counts as threat if it's deepfake-like

    Color resultColor = AppColors.successGreen;
    if (isAi && !hasThreat) {
      resultColor = AppColors.warning;
    } else if (hasThreat) {
      resultColor = AppColors.dangerRed;
    }

    ResultBottomSheet.show(
      context: context,
      title: hasThreat
          ? 'Deepfake Threat Detected'
          : (isAi ? 'AI-Generated Image' : 'Authentic Image'),
      explanation: data.explanation,
      resultColor: resultColor,
      isAi: isAi,
      isThreat: hasThreat,
      metrics: {
        'AI Prob': '${(data.aiGeneratedProbability * 100).round()}%',
        'Confidence': '${(data.confidence * 100).round()}%',
      },
      chips: data.detectedPatterns,
      onReportToBlockchain: () => _navigateToBlockchainReport(
        threatType: hasThreat ? 'Deepfake' : 'AI-Generated',
        aiResult: isAi ? 'AI' : 'Human',
        confidence: data.aiGeneratedProbability,
      ),
    );
  }

  void _showVideoResult(VideoAnalysisResult data) {
    context.read<ScanHistoryProvider>().addScan(
      ScanHistoryEntry(
        id: const Uuid().v4(),
        type: ScanType.video,
        timestamp: DateTime.now(),
        riskLevel: data.deepfakeProbability >= 0.7
            ? 'HIGH'
            : (data.deepfakeProbability >= 0.3 ? 'MEDIUM' : 'LOW'),
        riskScore: (data.deepfakeProbability * 100).round(),
        summary: data.isDeepfake ? 'Deepfake Detected' : 'Authentic Video',
        explanation: data.explanation,
      ),
    );

    final bool isAi = data.deepfakeProbability > 0.45; // Lowered threshold to be more sensitive
    final bool hasThreat = data.isDeepfake;

    Color resultColor = AppColors.successGreen;
    if (isAi && !hasThreat) {
      resultColor = AppColors.warning;
    } else if (hasThreat) {
      resultColor = AppColors.dangerRed;
    }

    ResultBottomSheet.show(
      context: context,
      title: hasThreat
          ? 'Deepfake Video detected'
          : (isAi ? 'AI-Generated Video' : 'Authentic Video'),
      explanation: data.explanation,
      resultColor: resultColor,
      isAi: isAi,
      isThreat: hasThreat,
      metrics: {
        'Deepfake Prob': '${(data.deepfakeProbability * 100).round()}%',
        'Confidence': '${(data.confidence * 100).round()}%',
        'Frames': '${data.analyzedFrames}',
      },
      chips: data.detectedPatterns,
      onReportToBlockchain: () => _navigateToBlockchainReport(
        threatType: 'Deepfake Video',
        aiResult: 'Deepfake',
        confidence: data.deepfakeProbability,
      ),
    );
  }

  void _navigateToBlockchainReport({
    required String threatType,
    required String aiResult,
    required double confidence,
  }) {
    if (_lastFileBytes == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlockchainReportScreen(
          imageBytes: _lastFileBytes!,
          threatType: threatType,
          aiResult: aiResult,
          confidence: confidence,
          filename: _selectedFile?.name,
        ),
      ),
    );
  }

  void _showErrorResult(String error) {
    ResultBottomSheet.show(
      context: context,
      title: 'Analysis Failed',
      explanation: error,
      resultColor: AppColors.dangerRed,
      resultIcon: Icons.error_outline,
      buttonText: 'OK',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scanHistory = context.watch<ScanHistoryProvider>();
    
    // Global filter for image and video scans
    final relevantScans = scanHistory.entries
        .where((s) => s.type == ScanType.image || s.type == ScanType.video)
        .toList();
        
    // Limited list for "Recent Scans" display
    final recentScans = relevantScans.take(6).toList();

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deepfake Detector',
                        style: AppTextStyles.h2
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'AI-powered image & video analysis',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primaryGold.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.image_search_rounded,
                      color: AppColors.primaryGold,
                      size: 24,
                    ),
                  ),
                ],
              ).animate().fadeIn().slideX(begin: -0.1),

              const SizedBox(height: 24),

              // ── Scanner Area ────────────────────────────────────────────
              GestureDetector(
                onTap: _isAnalyzing ? null : () => _pickImage(ImageSource.gallery),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  height: _selectedFile != null ? 320 : 260,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isAnalyzing
                          ? AppColors.primaryPurple.withValues(alpha: 0.6)
                          : _selectedFile != null
                              ? AppColors.primaryGold.withValues(alpha: 0.4)
                              : AppColors.border,
                      width: _isAnalyzing ? 2 : 1,
                    ),
                    boxShadow: _isAnalyzing
                        ? [
                            BoxShadow(
                              color: AppColors.primaryPurple.withValues(alpha: 0.15),
                              blurRadius: 24,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(23),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // ── Image Preview (cross-platform) ────────────
                        if (_imageBytes != null && !_isVideo)
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: _isAnalyzing ? 0.4 : 1.0,
                            child: Image.memory(
                              _imageBytes!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),

                        // ── Empty State ───────────────────────────────
                        if (_selectedFile == null)
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGold.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.add_photo_alternate_rounded,
                                  size: 48,
                                  color: AppColors.primaryGold.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Tap to select media',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Image or video for AI analysis',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),

                        // ── Video Placeholder ─────────────────────────
                        if (_isVideo && _selectedFile != null)
                          Container(
                            color: AppColors.darkCard,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryGold.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.video_file_rounded,
                                    size: 48,
                                    color: AppColors.primaryGold.withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Video Selected',
                                  style: AppTextStyles.h4.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 32),
                                  child: Text(
                                    _selectedFile!.name,
                                    style: AppTextStyles.bodySmall
                                        .copyWith(color: AppColors.textSecondary),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // ── Scanning Overlay ──────────────────────────
                        if (_isAnalyzing) ...[
                          // Dark overlay with blur
                          Container(
                            color: Colors.black.withValues(alpha: 0.3),
                          ),
                          // Scanner line animation
                          Container(
                            width: double.infinity,
                            height: 3,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  AppColors.primaryPurple.withValues(alpha: 0.8),
                                  AppColors.primaryGold,
                                  AppColors.primaryPurple.withValues(alpha: 0.8),
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryPurple.withValues(alpha: 0.5),
                                  blurRadius: 16,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                          )
                              .animate(
                                onPlay: (c) => c.repeat(reverse: true),
                              )
                              .slideY(begin: -40, end: 40, duration: 2.seconds),
                          // Status text
                          Positioned(
                            bottom: 20,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.darkBackground.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: AppColors.primaryPurple.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primaryGold,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _isVideo
                                        ? 'Analyzing frames...'
                                        : 'Analyzing structure...',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),

              const SizedBox(height: 20),

              // ── Action Buttons ──────────────────────────────────────────
              Row(
                children: [
                  // Select Image
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: _isAnalyzing
                          ? null
                          : () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_rounded, size: 20),
                      label: const Text(
                        'Select Image',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGold,
                        foregroundColor: AppColors.darkBackground,
                        disabledBackgroundColor:
                            AppColors.primaryGold.withValues(alpha: 0.4),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Select Video
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: _isAnalyzing ? null : _pickVideo,
                      icon: const Icon(Icons.videocam_rounded, size: 20),
                      label: const Text(
                        'Video',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryGold,
                        side: BorderSide(
                          color: AppColors.primaryGold.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 28),

              // ── Stats Row ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    _buildStatItem(
                      Icons.image_rounded,
                      '${relevantScans.where((s) => s.type == ScanType.image).length}',
                      'Images',
                      AppColors.primaryGold,
                    ),
                    _buildStatDivider(),
                    _buildStatItem(
                      Icons.video_file_rounded,
                      '${relevantScans.where((s) => s.type == ScanType.video).length}',
                      'Videos',
                      AppColors.primaryPurple,
                    ),
                    _buildStatDivider(),
                    _buildStatItem(
                      Icons.warning_amber_rounded,
                      '${relevantScans.where((s) => s.riskLevel == 'HIGH').length}',
                      'Threats',
                      AppColors.dangerRed,
                    ),
                    _buildStatDivider(),
                    _buildStatItem(
                      Icons.check_circle_outline_rounded,
                      '${relevantScans.where((s) => s.riskLevel == 'LOW' || s.riskLevel == 'MEDIUM').length}',
                      'Safe',
                      AppColors.successGreen,
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),

              const SizedBox(height: 28),

              // ── Recent Scans ────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Scans',
                    style: AppTextStyles.h4.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EvidenceTrackerScreen(),
                        ),
                      );
                    },
                    icon: Icon(Icons.shield_outlined,
                        size: 16, color: AppColors.primaryGold),
                    label: Text(
                      'Cybecrime Reports',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.primaryGold),
                    ),
                  )
                ],
              ).animate().fadeIn(delay: 500.ms),
              const SizedBox(height: 12),
              if (recentScans.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        color: AppColors.textTertiary.withValues(alpha: 0.4),
                        size: 36,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No scans yet',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 600.ms)
              else
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: recentScans.length,
                    itemBuilder: (ctx, index) {
                      final scan = recentScans[index];
                      return _buildRecentScanCard(scan);
                    },
                  ),
                ).animate().fadeIn(delay: 600.ms).slideX(begin: 0.1),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTextStyles.h4.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.border,
    );
  }

  Widget _buildRecentScanCard(ScanHistoryEntry scan) {
    final color = scan.riskLevel == 'HIGH'
        ? AppColors.dangerRed
        : scan.riskLevel == 'MEDIUM'
            ? Colors.orange
            : AppColors.successGreen;
    final icon =
        scan.type == ScanType.video ? Icons.video_file_rounded : Icons.image_rounded;

    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            '${scan.riskScore}%',
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            scan.riskLevel,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
