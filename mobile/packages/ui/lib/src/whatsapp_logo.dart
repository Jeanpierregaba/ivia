import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pictogramme WhatsApp (bulle verte, combiné blanc) pour les boutons « WhatsApp ».
class IviaWhatsAppLogo extends StatelessWidget {
  const IviaWhatsAppLogo({super.key, this.size = 24});

  final double size;

  /// Vert de la marque WhatsApp.
  static const green = Color(0xFF25D366);

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _BubblePainter(),
      child: Center(
        child: Transform.translate(
          offset: Offset(size * 0.01, -size * 0.02),
          child: Icon(
            Icons.call_rounded,
            size: size * 0.46,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );
}

class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    // Pastille verte.
    canvas.drawCircle(c, s / 2, Paint()..color = IviaWhatsAppLogo.green);
    // Bulle blanche (cercle et queue en bas à gauche).
    final r = s * 0.31;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.07
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    const gapStart = math.pi * 0.62;
    const gap = math.pi * 0.2;
    final bubble = Path()
      ..addArc(
        Rect.fromCircle(center: c, radius: r),
        gapStart + gap,
        math.pi * 2 - gap,
      );
    final a = Offset(
      c.dx + r * math.cos(gapStart),
      c.dy + r * math.sin(gapStart),
    );
    final b = Offset(
      c.dx + r * math.cos(gapStart + gap),
      c.dy + r * math.sin(gapStart + gap),
    );
    final tip = Offset(c.dx - r * 1.12, c.dy + r * 1.12);
    bubble
      ..moveTo(a.dx, a.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(b.dx, b.dy);
    canvas.drawPath(bubble, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
