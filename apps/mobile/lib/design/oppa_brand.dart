import "dart:math" as math;

import "package:flutter/material.dart";

/// OPPA brand kit — pure-vector, zero image assets (lightweight APK).
/// The pulse orb is drawn with one CustomPainter: a glowing sphere with
/// three elliptical light trails, matching the approved OPPA Pulse mark.
class OppaBrand {
  const OppaBrand._();

  // Brand constants from the approved identity (single source of truth).
  static const wordmark = "OPPA";
  static const tagline = "PULSE";
  static const slogan = "Chat. Pay. Connect. The African Way.";
  static const welcomeLine = "Everything you need in one app.";

  // Pulse gradient stops (violet → magenta → amber), used across screens.
  static const gradientViolet = Color(0xFF7C3AED);
  static const gradientMagenta = Color(0xFFE5399E);
  static const gradientAmber = Color(0xFFF59E0B);

  static const pulseGradient = RadialGradient(
    center: Alignment(-0.25, -0.35),
    radius: 1.1,
    colors: [Color(0xFF3B82F6), Color(0xFF7C3AED), Color(0xFF9333EA)],
  );

  /// The OPPA wordmark + PULSE tagline, as in the splash/welcomes.
  static Widget wordmarkBlock({
    double orbSize = 96,
    double wordSize = 34,
    Color textColor = Colors.white,
    Color taglineColor = gradientViolet,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size.square(orbSize),
          painter: const OppaPulsePainter(),
        ),
        SizedBox(height: orbSize * 0.12),
        Text(
          wordmark,
          style: TextStyle(
            fontSize: wordSize,
            fontWeight: FontWeight.w800,
            letterSpacing: wordSize * 0.14,
            color: textColor,
          ),
        ),
        SizedBox(height: wordSize * 0.18),
        Text(
          tagline,
          style: TextStyle(
            fontSize: wordSize * 0.38,
            fontWeight: FontWeight.w600,
            letterSpacing: wordSize * 0.42,
            color: taglineColor,
          ),
        ),
      ],
    );
  }
}

/// Painter for the OPPA Pulse orb: soft glowing sphere with three
/// intersecting elliptical light trails (violet, magenta, amber).
class OppaPulsePainter extends CustomPainter {
  const OppaPulsePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.44;

    // Sphere: radial violet-blue glow with a soft edge.
    final sphere = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.3, -0.4),
        colors: [
          Color(0xFF60A5FA),
          Color(0xFF7C3AED),
          Color(0xFF2E1065),
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sphere);

    // Outer halo.
    final halo = Paint()
      ..color = const Color(0xFF7C3AED).withValues(alpha: 0.18)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.22);
    canvas.drawCircle(center, radius * 1.02, halo);

    // Three elliptical trails, each rotated differently, colors from the
    // approved mark. Painting order builds the woven-ring look.
    final trails = [
      (const _TrailSpec(Color(0xFF60A5FA), 0.15 * math.pi, 1.00, 0.62, 0.20)),
      (const _TrailSpec(Color(0xFFE5399E), 0.62 * math.pi, 0.96, 0.58, 0.22)),
      (const _TrailSpec(Color(0xFFF59E0B), 1.12 * math.pi, 0.88, 0.52, 0.26)),
    ];
    for (final t in trails) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(t.rotation);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: radius * 2 * t.widthFactor,
        height: radius * 2 * t.heightFactor,
      );
      final trail = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * t.stroke
        ..shader = SweepGradient(
          colors: [t.color.withValues(alpha: 0.1), t.color, t.color.withValues(alpha: 0.15)],
          stops: const [0.0, 0.55, 1.0],
          transform: const GradientRotation(-0.8 * math.pi),
        ).createShader(rect);
      canvas.drawOval(rect, trail);
      canvas.restore();
    }

    // Highlight sparkle top-left, as in the mark.
    final spark = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center + Offset(-radius * 0.34, -radius * 0.42), radius * 0.055, spark);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TrailSpec {
  const _TrailSpec(
    this.color,
    this.rotation,
    this.widthFactor,
    this.heightFactor,
    this.stroke,
  );
  final Color color;
  final double rotation;
  final double widthFactor;
  final double heightFactor;
  final double stroke;
}
