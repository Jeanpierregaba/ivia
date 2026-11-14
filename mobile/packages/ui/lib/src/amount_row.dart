import 'package:flutter/material.dart';

import 'tokens.dart';

/// Ligne « libellé … montant » d'un récapitulatif. Le montant reste à
/// droite tant que le libellé garde au moins 40 % de la largeur (il passe
/// alors à la ligne) ; sinon (police agrandie, gros montant, écran étroit),
/// le montant passe sous le libellé : rien ne déborde.
class IviaAmountRow extends StatelessWidget {
  const IviaAmountRow({
    super.key,
    required this.label,
    required this.amount,
    this.strong = false,
  });

  final String label;
  final String amount;
  final bool strong;

  /// Part minimale de la largeur laissée au libellé à côté du montant.
  static const minLabelShare = 0.4;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = strong
        ? textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)
        : textTheme.bodyLarge;
    final amountStyle = style?.copyWith(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IviaSpacing.xs),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: amount, style: amountStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final amountWidth = painter.width;
          painter.dispose();
          final left = constraints.maxWidth - amountWidth - IviaSpacing.md;
          final amountText = Text(amount, style: amountStyle);
          if (left < constraints.maxWidth * minLabelShare) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: style),
                amountText,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: style)),
              const SizedBox(width: IviaSpacing.md),
              amountText,
            ],
          );
        },
      ),
    );
  }
}
