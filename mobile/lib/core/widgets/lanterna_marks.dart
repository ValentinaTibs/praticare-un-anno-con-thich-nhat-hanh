import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/lanterna_theme.dart';

/// The app's symbol: a thin amber lantern with a lit dot in the middle.
class Lantern extends StatelessWidget {
  final double height;
  const Lantern({super.key, this.height = 34});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(size: Size(height * 0.7, height), painter: _LanternPainter()),
      );
}

class _LanternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = LanternaColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Handle, cap, glass, base.
    canvas.drawArc(Rect.fromCenter(center: Offset(w / 2, h * 0.12), width: w * 0.34, height: h * 0.18), math.pi, math.pi, false, stroke);
    canvas.drawLine(Offset(w * 0.18, h * 0.21), Offset(w * 0.82, h * 0.21), stroke);
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.12, h * 0.27, w * 0.88, h * 0.86, Radius.circular(w * 0.2)),
      stroke,
    );
    canvas.drawLine(Offset(w * 0.26, h * 0.95), Offset(w * 0.74, h * 0.95), stroke);
    canvas.drawCircle(Offset(w / 2, h * 0.565), w * 0.11, Paint()..color = LanternaColors.accent);
  }

  @override
  bool shouldRepaint(_LanternPainter oldDelegate) => false;
}

/// The day ring: a thin track with an amber arc for the share of the journey
/// done, and the day number in the middle.
class DayRing extends StatelessWidget {
  final int day;
  final int duration;
  final double size;

  const DayRing({super.key, required this.day, required this.duration, this.size = 56});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(duration > 0 ? (day / duration).clamp(0.0, 1.0) : 0),
          child: Center(
            child: Text(
              '$day',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: LanternaColors.text),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const width = 4.0;
    final rect = (Offset.zero & size).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = LanternaColors.line;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint);
    if (progress > 0) {
      paint
        ..color = LanternaColors.accent
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.progress != progress;
}

/// A ring of dots, the circle's sign: the first [filled] dots in [filledColor]
/// (one per person in the circle), the others in [emptyColor].
class CircleDots extends StatelessWidget {
  final double size;
  final int filled;
  final Color filledColor;
  final Color emptyColor;
  static const dots = 10;

  const CircleDots({
    super.key,
    this.size = 44,
    this.filled = dots,
    this.filledColor = LanternaColors.accent,
    this.emptyColor = LanternaColors.line,
  });

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(size: Size.square(size), painter: _DotsPainter(filled.clamp(0, dots), filledColor, emptyColor)),
      );
}

class _DotsPainter extends CustomPainter {
  final int filled;
  final Color filledColor;
  final Color emptyColor;
  _DotsPainter(this.filled, this.filledColor, this.emptyColor);

  @override
  void paint(Canvas canvas, Size size) {
    final dot = size.width * 0.085;
    final radius = size.width / 2 - dot;
    final center = size.center(Offset.zero);
    for (var i = 0; i < CircleDots.dots; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / CircleDots.dots;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        dot,
        Paint()..color = i < filled ? filledColor : emptyColor,
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) =>
      oldDelegate.filled != filled || oldDelegate.filledColor != filledColor || oldDelegate.emptyColor != emptyColor;
}
