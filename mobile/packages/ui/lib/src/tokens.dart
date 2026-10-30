import 'package:flutter/painting.dart';

/// Couleurs de la charte (docs/DESIGN.md, section Tokens).
///
/// Les écrans n'utilisent jamais ces valeurs directement quand un rôle du
/// thème existe (`Theme.of(context).colorScheme.primary`…).
abstract final class IviaColors {
  // Marque
  static const imperialRed = Color(0xFFED1C2F);
  static const cornellRed = Color(0xFFAA0E1B);
  static const cobaltBlue = Color(0xFF004DA8);
  static const berkeleyBlue = Color(0xFF0E2E54);

  // Rôles
  static const primary = imperialRed;
  static const primaryStrong = cornellRed;
  static const secondary = cobaltBlue;
  static const tertiary = berkeleyBlue;

  // Teintes pâles : fonds d'éléments sélectionnés (puces, indicateur de navigation)
  static const primarySoft = Color(0xFFFDE8EA);
  static const secondarySoft = Color(0xFFE5EEF8);

  // Neutres
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF3F4F6);
  static const backgroundAlt = Color(0xFFF6F7F9);
  static const border = Color(0xFFE3E6EB);
  static const borderInput = Color(0xFF7F8C9E);
  static const text = Color(0xFF0A1A30);
  static const textSecondary = Color(0xFF3A4A60);
  static const textMuted = Color(0xFF5A6A80);

  // États
  static const success = Color(0xFF1E7A4C);
  static const warning = Color(0xFFB45309);
  static const error = cornellRed;
  static const info = cobaltBlue;
}

/// Couleur de chaque famille de services (tuiles, pictogrammes, en-têtes).
abstract final class IviaServiceColors {
  static const shopping = IviaColors.imperialRed;
  static const delivery = IviaColors.cornellRed;
  static const mobility = IviaColors.cobaltBlue;
  static const health = IviaColors.berkeleyBlue;
}

/// Espacements sur une grille de 4 px.
abstract final class IviaSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 40.0;

  /// Marges latérales des écrans.
  static const screen = lg;

  /// Espace entre les tuiles de la mosaïque.
  static const mosaicGap = sm;
}

/// Rayons des coins.
abstract final class IviaRadius {
  /// Tuiles intérieures de la mosaïque.
  static const tile = 6.0;

  /// Boutons et petites cartes.
  static const button = 14.0;

  /// Champs, grandes cartes, barre de navigation, coin extérieur de la mosaïque.
  static const large = 18.0;

  /// Pastilles et puces de filtre.
  static const pill = 999.0;
}

/// Ombres : les cartes n'en ont pas, seules les feuilles modales en portent une.
abstract final class IviaShadows {
  static const sheet = [
    BoxShadow(
      color: Color(0x1F0E2E54), // Berkeley Blue à 12 %
      offset: Offset(0, -8),
      blurRadius: 24,
    ),
  ];
}
