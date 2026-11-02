import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';


/// Logo de la boutique (facultatif) : carré pointillé, ou aperçu de la photo
/// choisie avec « Retirer ».
class ShopLogoField extends ConsumerStatefulWidget {
  const ShopLogoField({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.enabled = true,
  });

  /// JPEG prêt à l'envoi ; `null` : pas de logo.
  final Uint8List? value;
  final ValueChanged<Uint8List?> onChanged;
  final String? errorText;
  final bool enabled;

  @override
  ConsumerState<ShopLogoField> createState() => _ShopLogoFieldState();
}

class _ShopLogoFieldState extends ConsumerState<ShopLogoField> {
  String? _pickError;

  Future<void> _pick() async {
    try {
      final bytes = await ref.read(photoPickerProvider).pick();
      if (bytes == null || !mounted) return;
      if (bytes.length > maxUploadBytes) {
        setState(() => _pickError = 'Photo trop lourde (5 Mo au plus).');
        return;
      }
      setState(() => _pickError = null);
      widget.onChanged(bytes);
    } on Exception {
      if (mounted) {
        setState(() => _pickError = 'Cette photo ne peut pas être utilisée.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final error = widget.errorText ?? _pickError;
    final logo = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              button: true,
              label: logo == null
                  ? 'Choisir le logo de la boutique'
                  : 'Changer le logo de la boutique',
              child: InkWell(
                onTap: widget.enabled ? _pick : null,
                borderRadius: BorderRadius.circular(IviaRadius.large),
                child: SizedBox.square(
                  dimension: 64,
                  child: logo == null
                      ? const CustomPaint(
                          painter: _DashedBorderPainter(),
                          child: Center(
                            child: Icon(
                              Icons.add,
                              color: IviaColors.textSecondary,
                            ),
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(IviaRadius.large),
                          child: Image.memory(logo, fit: BoxFit.cover),
                        ),
                ),
              ),
            ),
            const SizedBox(width: IviaSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Logo de la boutique', style: textTheme.titleSmall),
                  Text('Photo carrée, facultatif', style: textTheme.bodySmall),
                  if (logo != null)
                    TextButton(
                      onPressed: widget.enabled
                          ? () => widget.onChanged(null)
                          : null,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text('Retirer le logo'),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: IviaSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: textTheme.bodySmall?.copyWith(color: IviaColors.error),
            ),
          ),
        ],
      ],
    );
  }
}

/// Contour pointillé du carré « + » (maquette).
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = IviaColors.borderInput
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(IviaRadius.large),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}
