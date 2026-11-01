import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Commandes : écran provisoire, remplacé par la fonctionnalité 011.
class OrdersPlaceholderScreen extends StatelessWidget {
  const OrdersPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          Semantics(
            header: true,
            child: Text('Commandes', style: textTheme.headlineLarge),
          ),
          const SizedBox(height: IviaSpacing.xxl),
          const IviaInfoCard(
            text:
                'Bientôt disponible : les commandes payées par vos clients '
                'arriveront ici, et vous aurez 15 minutes pour les accepter.',
          ),
        ],
      ),
    );
  }
}
