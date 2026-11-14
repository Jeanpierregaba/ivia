import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Splash de chargement (maquette D00, spec 033) : le splash natif est bleu
/// uni, puis ce groupe (tuile, nom, slogan) apparaît, centré.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const IviaLoadingSplash(
      brand: IviaAppBrand.driver,
      tile: true,
      title: 'Driver',
      tagline: 'Livrez près de chez vous.',
      // Maquette D00 : tuile de 132 dp, logotype cobalt.
      tileStyle: IviaSplashTile(
        size: 132,
        radiusRatio: 0.242,
        logoRatio: 0.595,
      ),
      titleStyle: TextStyle(fontSize: 24),
      taglineStyle: TextStyle(
        fontSize: 16,
        color: IviaDriverColors.onBlueMuted,
      ),
      centerGroup: true,
    );
  }
}
