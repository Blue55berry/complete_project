import 'dart:math' as math;
import 'package:flutter/material.dart';

class AnimatedPhoneSignal extends StatefulWidget {
  final Color color;
  final double size;
  final bool isActive;

  const AnimatedPhoneSignal({
    super.key,
    required this.color,
    this.size = 56.0,
    this.isActive = true,
  });

  @override
  State<AnimatedPhoneSignal> createState() => _AnimatedPhoneSignalState();
}

class _AnimatedPhoneSignalState extends State<AnimatedPhoneSignal>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedPhoneSignal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The Phone Icon
          Positioned(
            left: widget.size * 0.1,
            bottom: widget.size * 0.1,
            child: Icon(
              Icons.phone_rounded,
              color: widget.color,
              size: widget.size * 0.5,
            ),
          ),

          // The Waves
          CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _SignalWavePainter(
              color: widget.color,
              animationValue: _controller,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalWavePainter extends CustomPainter {
  final Color color;
  final Animation<double> animationValue;

  _SignalWavePainter({required this.color, required this.animationValue})
    : super(repaint: animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Center of the waves (approx near the earpiece of the phone)
    final center = Offset(size.width * 0.45, size.height * 0.55);

    // Radii for the 3 waves
    final r1 = size.width * 0.25;
    final r2 = size.width * 0.38;
    final r3 = size.width * 0.51;

    final double t = animationValue.value;

    // Wave 1 (Inner)
    if (t > 0.15) {
      paint.color = color.withValues(alpha: _getOpacity(t, 0.15));
      _drawArc(canvas, center, r1, paint);
    }

    // Wave 2 (Middle)
    if (t > 0.35) {
      paint.color = color.withValues(alpha: _getOpacity(t, 0.35));
      _drawArc(canvas, center, r2, paint);
    }

    // Wave 3 (Outer)
    if (t > 0.55) {
      paint.color = color.withValues(alpha: _getOpacity(t, 0.55));
      _drawArc(canvas, center, r3, paint);
    }
  }

  // Helper to fade in nicely
  double _getOpacity(double time, double startTime) {
    // 0.0 to 1.0 transition over 0.2s
    double progress = (time - startTime) / 0.2;
    if (progress > 1.0) progress = 1.0;
    // Fade out at end logic if needed, but "continue it" implies looping build up
    // Let's make them fade out slightly at the very end of the cycle to reset smoothly
    if (time > 0.9) {
      return 1.0 - ((time - 0.9) * 10);
    }
    return progress;
  }

  void _drawArc(Canvas canvas, Offset center, double radius, Paint paint) {
    // Draw arc from -45 degrees (top rightish) slightly upwards
    const startAngle = -math.pi / 2.5;
    const sweepAngle = math.pi / 3;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SignalWavePainter oldDelegate) => true;
}
