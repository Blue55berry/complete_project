import sys

with open('frontend/lib/screens/intelligence/threat_intelligence_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# We want to keep lines up to exactly where 'class _HotspotLayer' starts, which is around line 1069.
# The comment block for it starts at line 1065. Let's find the exact index.

cutoff_idx = -1
for i, line in enumerate(lines):
    if line.startswith('// ══════════════════════════════════════════════════════════════════════════════') and 'HOTSPOT LAYER' in "".join(lines[i:i+3]):
        cutoff_idx = i
        break

if cutoff_idx == -1:
    print("Could not find start of Hotspot Layer")
    sys.exit(1)

new_code = """// ── Legend dot ─────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4)],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.85),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

// ── Pulse Marker  — triple concentric rings that expand outward ──────────
/// [t] is the normalised animation clock (0.0 – 1.0), driven by parent
/// AnimatedBuilder so all markers sync to the same beat.
class _PulseMarker extends StatelessWidget {
  const _PulseMarker({
    required this.color,
    required this.intensity,
    required this.t,
  });

  final Color color;
  final double intensity;
  final double t; // 0..1 animation progress

  @override
  Widget build(BuildContext context) {
    // Three rings staggered 1/3 cycle apart
    final t1 = t;
    final t2 = (t + 0.33) % 1.0;
    final t3 = (t + 0.66) % 1.0;

    final maxR = 14.0 + intensity * 10.0; // max ring radius px
    const dotR = 5.0;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Ring 3 (outermost)
        _Ring(color: color, t: t3, maxR: maxR),
        // Ring 2
        _Ring(color: color, t: t2, maxR: maxR * 0.75),
        // Ring 1 (innermost)
        _Ring(color: color, t: t1, maxR: maxR * 0.50),

        // Solid core dot
        Container(
          width: dotR * 2,
          height: dotR * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.85),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.color, required this.t, required this.maxR});
  final Color color;
  final double t;    // 0..1 — how far expanded this ring is
  final double maxR; // maximum radius in px

  @override
  Widget build(BuildContext context) {
    // Ease-out: ring expands quickly then slows
    final eased = Curves.easeOut.transform(t);
    final size  = maxR * 2 * eased;

    // Opacity: full at start, fades to 0 at end
    final alpha = (1.0 - eased).clamp(0.0, 1.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: alpha * 0.85),
          width: 1.5,
        ),
      ),
    );
  }
}

// ── HUD CORNER BRACKETS ──────────────────────────────────────────────

class _HUDCornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF26D9FF).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const arm = 20.0;
    const pad = 6.0;

    // Top-left
    canvas.drawPath(Path()..moveTo(pad, pad + arm)..lineTo(pad, pad)..lineTo(pad + arm, pad), paint);
    // Top-right
    canvas.drawPath(Path()..moveTo(size.width - pad - arm, pad)..lineTo(size.width - pad, pad)..lineTo(size.width - pad, pad + arm), paint);
    // Bottom-left
    canvas.drawPath(Path()..moveTo(pad, size.height - pad - arm)..lineTo(pad, size.height - pad)..lineTo(pad + arm, size.height - pad), paint);
    // Bottom-right
    canvas.drawPath(Path()..moveTo(size.width - pad - arm, size.height - pad)..lineTo(size.width - pad, size.height - pad)..lineTo(size.width - pad, size.height - pad - arm), paint);

    // Small coordinate labels
    final labelPaint = TextPainter(
      text: TextSpan(
        text: 'N90°',
        style: TextStyle(color: const Color(0xFF26D9FF).withValues(alpha: 0.3), fontSize: 7, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPaint.paint(canvas, const Offset(pad + 4, pad + arm + 2));

    final labelPaint2 = TextPainter(
      text: TextSpan(
        text: 'E180°',
        style: TextStyle(color: const Color(0xFF26D9FF).withValues(alpha: 0.3), fontSize: 7, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPaint2.paint(canvas, Offset(size.width - pad - arm - 4, size.height - pad - arm - 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
"""

with open('frontend/lib/screens/intelligence/threat_intelligence_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines[:cutoff_idx])
    f.write(new_code)
print("Replaced lines successfully")
