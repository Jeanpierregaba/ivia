import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Splash de chargement, affiché pendant le démarrage (spec 004).
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const IviaLoadingSplash(
      brand: IviaAppBrand.seller,
      tile: true,
      title: 'Business',
      tagline: 'Votre activité, pilotée d\'ici.',
    );
  }
}
