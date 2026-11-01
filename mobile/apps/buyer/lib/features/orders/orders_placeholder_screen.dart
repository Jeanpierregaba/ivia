import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Commandes : écran provisoire, remplacé par les fonctionnalités 009 et 013.
class OrdersPlaceholderScreen extends StatelessWidget {
  const OrdersPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Commandes',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ),
          const SizedBox(height: IviaSpacing.xxl),
          const IviaInfoCard(
            text:
                'Bientôt disponible : vos commandes, leur suivi et votre code '
                'de remise apparaîtront ici.',
          ),
        ],
      ),
    );
  }
}
