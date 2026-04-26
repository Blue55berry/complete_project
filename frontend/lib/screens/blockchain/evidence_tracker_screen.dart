import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/services/api_service.dart';
import 'package:risk_guard/core/models/analysis_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EvidenceTrackerScreen extends StatefulWidget {
  const EvidenceTrackerScreen({super.key});

  @override
  State<EvidenceTrackerScreen> createState() => _EvidenceTrackerScreenState();
}

class _EvidenceTrackerScreenState extends State<EvidenceTrackerScreen> {
  final _apiService = ApiService();
  bool _isLoading = true;
  String? _error;
  List<BlockchainReportResult> _reports = [];
  String _currentFilter = 'all';
  List<String> _myEvidenceIds = [];

  @override
  void initState() {
    super.initState();
    _loadMyEvidenceIds().then((_) => _fetchReports());
  }

  Future<void> _loadMyEvidenceIds() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myEvidenceIds = prefs.getStringList('my_evidence_ids') ?? [];
    });
  }

  Future<void> _fetchReports() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final result = await _apiService.getBlockchainReports();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.isSuccess && result.data != null) {
          _reports = result.data!;
        } else {
          _error = result.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Cybercrime Tracker'),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Sync latest verification status',
            onPressed: _fetchReports,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGold))
          : _error != null
              ? _buildErrorState()
              : _reports.where((r) => _myEvidenceIds.contains(r.evidenceId.toString())).isEmpty
                  ? _buildEmptyState()
                  : _buildList(),
    );
  }

  // ── Summary banner ──────────────────────────────────────────────────────────

  Widget _buildSummaryBanner() {
    final myReports = _reports.where((r) => _myEvidenceIds.contains(r.evidenceId.toString())).toList();
    final verifiedCount = myReports.where((r) => r.anchored).length;
    final pendingCount = myReports.length - verifiedCount;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryGold.withValues(alpha: 0.4),
            AppColors.primaryGold.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(23),
        ),
        child: Row(
          children: [
            _summaryItem('${myReports.length}', 'TOTAL', AppColors.primaryGold),
            _vDivider(),
            _summaryItem('$verifiedCount', 'VERIFIED', const Color(0xFF22C55E)),
            _vDivider(),
            _summaryItem('$pendingCount', 'PENDING', const Color(0xFFF59E0B)),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _vDivider() => Container(height: 30, width: 1, color: Colors.white10);

  Widget _summaryItem(String count, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(count,
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: -1)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textTertiary,
                  letterSpacing: 1.5)),
        ],
      ),
    );
  }

  // ── States ──────────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text('No evidence filed yet',
              style:
                  AppTextStyles.h4.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('Evidence submitted in the app will appear here',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textTertiary)),
        ],
      ).animate().fadeIn(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text('Could not sync with server',
                style: AppTextStyles.h4.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(_error ?? 'Check that the backend is running.',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textTertiary),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGold,
                  foregroundColor: Colors.black),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: _fetchReports,
            ),
          ],
        ).animate().fadeIn(),
      ),
    );
  }

  Widget _buildList() {
    // Apply filter
    final filteredReports = _reports.where((r) {
      if (!_myEvidenceIds.contains(r.evidenceId.toString())) return false;
      if (_currentFilter == 'all') return true;
      final type = _getFileType(r.filename);
      return type == _currentFilter;
    }).toList();

    return Column(
      children: [
        _buildSummaryBanner(),
        _buildFilterBar(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: filteredReports.length,
            itemBuilder: (context, index) {
              return _buildCard(filteredReports[index])
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 60 * index))
                  .slideY(begin: 0.08, end: 0);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          _filterChip('all', 'All', Icons.grid_view_rounded),
          _filterChip('image', 'Images', Icons.image_rounded),
          _filterChip('audio', 'Audio', Icons.mic_rounded),
          _filterChip('video', 'Video', Icons.videocam_rounded),
          _filterChip('text', 'Documents', Icons.description_rounded),
        ],
      ),
    );
  }

  Widget _filterChip(String filterKey, String label, IconData icon) {
    final isSelected = _currentFilter == filterKey;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () => setState(() => _currentFilter = filterKey),
        child: AnimatedContainer(
          duration: 300.ms,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryGold : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppColors.primaryGold : Colors.white12,
              width: 1,
            ),
            boxShadow: isSelected ? [
              BoxShadow(
                color: AppColors.primaryGold.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            ] : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.black : AppColors.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.black : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  fontSize: 12,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getFileType(String filename) {
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    if (['png', 'jpg', 'jpeg', 'webp', 'heic', 'gif', 'bmp'].contains(ext)) return 'image';
    if (['mp4', 'avi', 'mov', 'mkv', 'webm', '3gp'].contains(ext)) return 'video';
    if (['mp3', 'wav', 'm4a', 'ogg', 'aac', 'flac'].contains(ext)) return 'audio';
    if (['pdf', 'doc', 'docx', 'txt', 'csv', 'eml'].contains(ext)) return 'text';
    return 'text'; // Default to text if unknown
  }

  // ── Report Card ─────────────────────────────────────────────────────────────

  Widget _buildCard(BlockchainReportResult r) {
    final bool isVerified = r.anchored;
    final Color statusColor = isVerified ? Colors.green : Colors.orange;

    // Determine file type from filename
    final String displayName =
        r.filename.isNotEmpty ? r.filename : 'evidence_${r.evidenceId}';
    final String ext = displayName.contains('.')
        ? displayName.split('.').last.toLowerCase()
        : '';
    final IconData fileIcon = _fileIcon(ext);
    final String fileType = _getFileType(r.filename);
    Color typeColor;
    if (fileType == 'image') {
      typeColor = const Color(0xFF6366f1);
    } else if (fileType == 'audio') {
      typeColor = const Color(0xFFf59e0b);
    } else if (fileType == 'video') {
      typeColor = const Color(0xFFec4899);
    } else {
      typeColor = const Color(0xFF22c55e);
    }

    // AI result coloring
    final bool isThreat = r.aiResult.toLowerCase().contains('ai') ||
        r.aiResult.toLowerCase().contains('fake') ||
        r.aiResult.toLowerCase().contains('neural') ||
        r.aiResult.toLowerCase().contains('generated');
    final Color threatColor = isThreat ? Colors.redAccent : Colors.green;
    final int confPct = (r.confidence * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  statusColor.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(fileIcon, color: typeColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FORENSIC ID #${r.evidenceId}',
                          style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 2),
                      Text(displayName,
                          style: AppTextStyles.bodyMedium
                              .copyWith(fontWeight: FontWeight.w900, fontSize: 15),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: typeColor.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    fileType == 'text' ? 'DOCS' : fileType.toUpperCase(),
                    style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status indicator
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(isVerified ? Icons.verified_rounded : Icons.pending_actions_rounded, 
                           size: 16, color: statusColor),
                      const SizedBox(width: 8),
                      Text(
                        isVerified ? 'VERIFIED BY FORENSIC UNIT' : 'PENDING INVESTIGATION',
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // AI Detection + Confidence
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AI RISK ASSESSMENT',
                                style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2)),
                            const SizedBox(height: 6),
                            Text(
                              r.aiResult.isNotEmpty
                                  ? r.aiResult.toUpperCase()
                                  : 'UNKNOWN',
                              style: TextStyle(
                                  color: threatColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Confidence arc
                    SizedBox(
                      width: 62,
                      height: 62,
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: const Size(62, 62),
                            painter: _ArcPainter(
                                confPct / 100, threatColor),
                          ),
                          Center(
                            child: Text('$confPct%',
                                style: TextStyle(
                                    color: threatColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Info rows
                _infoRow(Icons.category_outlined, 'Threat Type',
                    r.threatType.isNotEmpty ? r.threatType : 'N/A'),
                _infoRow(
                    Icons.calendar_today_outlined,
                    'Filed',
                    r.timestamp.length >= 10
                        ? r.timestamp.substring(0, 10)
                        : r.timestamp),
                if (r.description.isNotEmpty)
                  _infoRow(Icons.notes_outlined, 'Note', r.description),
                if (r.txHash.isNotEmpty && r.txHash != 'null')
                  _infoRow(
                      Icons.link_outlined,
                      'TX Hash',
                      '${r.txHash.substring(0, math.min(20, r.txHash.length))}…'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Text('$label:  ',
              style: const TextStyle(
                  color: AppColors.textTertiary, fontSize: 12)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  IconData _fileIcon(String ext) {
    if (['png', 'jpg', 'jpeg', 'webp', 'heic', 'gif', 'bmp'].contains(ext)) {
      return Icons.image_outlined;
    }
    if (['mp4', 'avi', 'mov', 'mkv', 'webm', '3gp'].contains(ext)) {
      return Icons.videocam_outlined;
    }
    if (['mp3', 'wav', 'm4a', 'ogg', 'aac', 'flac'].contains(ext)) {
      return Icons.mic_outlined;
    }
    if (['pdf', 'doc', 'docx', 'txt', 'csv', 'eml'].contains(ext)) {
      return Icons.description_outlined;
    }
    return Icons.attach_file_outlined;
  }
}

// ── Confidence Arc Painter ──────────────────────────────────────────────────

class _ArcPainter extends CustomPainter {
  final double progress; // 0.0 – 1.0
  final Color color;

  const _ArcPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;

    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, bgPaint);
    canvas.drawArc(
        rect, -math.pi / 2, math.pi * 2 * progress.clamp(0.0, 1.0), false, fgPaint);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress;
}
