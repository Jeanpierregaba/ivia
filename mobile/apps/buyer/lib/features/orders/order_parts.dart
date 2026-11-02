import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Carte blanche de l'écran Commande et du suivi.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(IviaSpacing.lg),
    decoration: BoxDecoration(
      color: IviaColors.surface,
      borderRadius: BorderRadius.circular(IviaRadius.large),
    ),
    child: child,
  );
}

/// Ligne « libellé … montant » du récapitulatif.
class AmountRow extends StatelessWidget {
  const AmountRow({
    super.key,
    required this.label,
    required this.amount,
    this.strong = false,
  });

  final String label;
  final String amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = strong
        ? textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)
        : textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IviaSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: IviaSpacing.md),
          Text(amount, style: style?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
