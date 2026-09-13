import 'package:flutter/material.dart';
import 'app_theme.dart';

/// The Madhura Agro Traders mark: a rising sun behind a paddy plant with
/// ripe, drooping grain heads.
///
/// Drawn in code rather than shipped as an image file — it stays sharp at
/// any size (app icon through splash screen), adds nothing to the APK,
/// and needs no asset loading, so it renders instantly even offline.
class AppLogo extends StatelessWidget {
  final double size;

  /// When true, draws on a filled brand-colored circle (for dark-on-light
  /// placements like the dashboard header). When false, the mark is drawn
  /// in white for use on an already-colored background.
  final bool withBackground;

  const AppLogo({super.key, this.size = 64, this.withBackground = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LogoPainter(withBackground: withBackground),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final bool withBackground;
  _LogoPainter({required this.withBackground});

  @override
  void paint(Canvas canvas, Size size) {
    // Designed on a 100x100 grid, then scaled to whatever size is asked
    // for — keeps the proportions identical at every size.
    final s = size.width / 100;
    final paint = Paint()..isAntiAlias = true;

    final stalkColor = withBackground ? Colors.white : Colors.white;
    final leafLight = withBackground ? const Color(0xFFC9E8DC) : const Color(0xFFC9E8DC);

    if (withBackground) {
      paint.color = AppTheme.primary;
      canvas.drawCircle(Offset(50 * s, 50 * s), 50 * s, paint);
    }

    // Rising sun
    paint.color = const Color(0xFFFFD166);
    canvas.drawCircle(Offset(50 * s, 36 * s), 17 * s, paint);

    // Central stalk
    paint.color = stalkColor;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 3.2 * s;
    paint.strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(50 * s, 86 * s), Offset(50 * s, 48 * s), paint);
    paint.style = PaintingStyle.fill;

    // Grain heads — upper pair, drooping outward the way ripe paddy does
    paint.color = stalkColor;
    canvas.drawPath(_grainHead(s, 50, 54, left: true), paint);
    paint.color = leafLight;
    canvas.drawPath(_grainHead(s, 50, 54, left: false), paint);

    // Grain heads — lower pair, slightly wider drop
    paint.color = leafLight;
    canvas.drawPath(_grainHead(s, 50, 68, left: true, spread: 1.15), paint);
    paint.color = stalkColor;
    canvas.drawPath(_grainHead(s, 50, 68, left: false, spread: 1.15), paint);

    // Ground line
    paint.color = const Color(0xFF8FD4BC);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 3.6 * s;
    paint.strokeCap = StrokeCap.round;
    final ground = Path()
      ..moveTo(28 * s, 90 * s)
      ..quadraticBezierTo(50 * s, 84 * s, 72 * s, 90 * s);
    canvas.drawPath(ground, paint);
  }

  /// One drooping grain head curving away from the stalk.
  Path _grainHead(double s, double cx, double cy, {required bool left, double spread = 1.0}) {
    final dir = left ? -1.0 : 1.0;
    final w = 20 * spread;
    return Path()
      ..moveTo(cx * s, cy * s)
      ..cubicTo(
        (cx + dir * w * 0.5) * s,
        (cy - 2) * s,
        (cx + dir * w) * s,
        (cy + 4) * s,
        (cx + dir * w) * s,
        (cy + 10) * s,
      )
      ..cubicTo(
        (cx + dir * w * 0.5) * s,
        (cy + 11) * s,
        (cx + dir * w * 0.15) * s,
        (cy + 6) * s,
        cx * s,
        cy * s,
      )
      ..close();
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) =>
      oldDelegate.withBackground != withBackground;
}
