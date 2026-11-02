import 'package:flutter/material.dart';

/// The Vaulton shield mark, matching the artwork in the main Vaulton project.
class VaultonLogo extends StatelessWidget {
  const VaultonLogo({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _VaultonLogoPainter()),
  );
}

class _VaultonLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 256);

    final shield = Path()
      ..moveTo(128, 12)
      ..lineTo(226, 52)
      ..lineTo(226, 122)
      ..cubicTo(226, 183, 187, 221, 128, 244)
      ..cubicTo(69, 221, 30, 183, 30, 122)
      ..lineTo(30, 52)
      ..close();

    canvas.drawPath(shield, Paint()..color = const Color(0xFF071A35));
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeJoin = StrokeJoin.round
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF54D6FF), Color(0xFF0874E8)],
        ).createShader(const Rect.fromLTWH(0, 0, 256, 256)),
    );

    final v = Path()
      ..moveTo(75, 78)
      ..lineTo(128, 182)
      ..lineTo(181, 78)
      ..lineTo(150, 78)
      ..lineTo(128, 125)
      ..lineTo(106, 78)
      ..close();
    canvas.drawPath(v, Paint()..color = const Color(0xFFF4FBFF));

    final highlight = Path()
      ..moveTo(128, 23)
      ..lineTo(215, 59)
      ..lineTo(215, 122)
      ..cubicTo(215, 174, 184, 206, 128, 229);
    canvas.drawPath(
      highlight,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white.withValues(alpha: 0.18),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VaultonLogoPainter oldDelegate) => false;
}
