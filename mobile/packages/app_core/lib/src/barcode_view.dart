import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Code-barres scannable (Code 128) d'un code de commande, avec le code
/// lisible dessous. [data] : le code sans tiret est encodé.
class IviaBarcode extends StatelessWidget {
  const IviaBarcode({
    super.key,
    required this.code,
    this.height = 64,
    this.showText = true,
  });

  final String code;
  final double height;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: 'Code-barres de la commande $code',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _BarcodePainter(code.replaceAll('-', '')),
            ),
          ),
          if (showText) ...[
            const SizedBox(height: 6),
            Text(
              code,
              style: t.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
                color: IviaColors.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    // Barres seulement ; largeur limitée pour garder des modules nets.
    final width = size.width.clamp(0, 360).toDouble();
    final dx = (size.width - width) / 2;
    final paint = Paint()..color = Colors.black;
    for (final e in Barcode.code128().make(
      data,
      width: width,
      height: size.height,
      drawText: false,
    )) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(
          Rect.fromLTWH(dx + e.left, e.top, e.width, e.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.data != data;
}
