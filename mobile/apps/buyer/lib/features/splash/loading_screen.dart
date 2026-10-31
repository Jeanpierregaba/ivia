import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Splash de chargement, affiché pendant le démarrage (spec 027).
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return IviaLoadingSplash(
      color: IviaAppBrand.buyer.accent,
      tagline: 'Tout, près de chez vous.',
    );
  }
}
