import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:risk_guard/core/theme/app_colors.dart';
import 'package:risk_guard/core/theme/app_text_styles.dart';
import 'package:risk_guard/core/services/scan_history_provider.dart';
import 'package:risk_guard/core/services/realtime_protection_provider.dart';
import 'package:risk_guard/widgets/stat_item.dart';

/// Security status card showing system health percentage and stats
/// Now wired to real data from ScanHistoryProvider and RealtimeProtectionProvider
class SecurityStatusCard extends StatefulWidget {
  const SecurityStatusCard({super.key});

  @override
  State<SecurityStatusCard> createState() => _SecurityStatusCardState();
}

class _SecurityStatusCardState extends State<SecurityStatusCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<ScanHistoryProvider>();
    final protection = context.watch<RealtimeProtectionProvider>();

    // Dynamic percentage: start at 100, reduce by 15 per HIGH threat, 5 per MEDIUM
    final int percentage =
        (100 - (history.threatsBlocked * 15) - (history.moderateThreats * 5))
            .clamp(10, 100);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGold.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background Waves
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: _WavePainter(
                    color: AppColors.textOnGold.withValues(alpha: 0.1),
                    animationValue: _controller.value,
                  ),
                );
              },
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      Icons.shield_rounded,
                      color: AppColors.textOnGold,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Digital Security',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.textOnGold.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          percentage >= 80
                              ? 'Secure'
                              : (percentage >= 50 ? 'At Risk' : 'Critical'),
                          style: AppTextStyles.h4.copyWith(
                            color: AppColors.textOnGold,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Large percentage
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '$percentage%',
                          style: AppTextStyles.display.copyWith(
                            color: AppColors.textOnGold,
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Stats Row — real data
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatItem(
                      value: history.threatsBlocked.toString(),
                      label: 'Threats',
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: AppColors.textOnGold.withValues(alpha: 0.2),
                    ),
                    StatItem(
                      value: history.totalScans.toString(),
                      label: 'Scanned',
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: AppColors.textOnGold.withValues(alpha: 0.2),
                    ),
                    StatItem(
                      value: protection.isActive ? 'Active' : 'Off',
                      label: 'Firewall',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color color;
  final double animationValue;

  _WavePainter({required this.color, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    _drawWave(canvas, size, paint, 1.0, 0.0);
    _drawWave(
      canvas,
      size,
      paint..color = color.withValues(alpha: 0.05),
      1.5,
      math.pi,
    );
  }

  void _drawWave(
    Canvas canvas,
    Size size,
    Paint paint,
    double speed,
    double offset,
  ) {
    final path = Path();
    final waveHeight = size.height * 0.15;
    final waveLength = size.width;
    final yBase = size.height * 0.65;

    path.moveTo(0, size.height);
    path.lineTo(0, yBase);

    for (double i = 0; i <= size.width; i++) {
      double dx = i / waveLength * 2 * math.pi;
      double shift = (animationValue * 2 * math.pi * speed) + offset;
      double dy = math.sin(dx + shift) * waveHeight;
      path.lineTo(i, yBase + dy);
    }

    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.color != color;
  }
}
