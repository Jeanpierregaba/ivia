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
