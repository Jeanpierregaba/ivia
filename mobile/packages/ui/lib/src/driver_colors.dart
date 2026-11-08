import 'package:flutter/painting.dart';

import 'pharmacy_colors.dart';
import 'tokens.dart';

/// Couleurs de l'app Ivia Driver, relevées sur les maquettes D00 à D19
/// (spec 033). Le bleu est le cobalt de la charte ; la barre du bas est
/// claire (arbitrage de la spec), les cartes sombres restent sombres.
abstract final class IviaDriverColors {
  // Bleus
  static const blue = IviaColors.cobaltBlue;

  /// Fonds pâles : icône d'une ligne, pastille « En route ».
  static const blueSoft = Color(0xFFE3EDF9);

  /// Bleu clair sur fond sombre : anneau du jour, « +1 200 F », barre du
  /// jour choisi (D08, D15, D18).
  static const blueOnDark = Color(0xFF8DB7EE);

  /// Anneau du compte à rebours, partie écoulée (D01), et slogan du
  /// splash sur fond bleu (D00).
  static const blueRing = Color(0xFFD1E1F5);
  static const onBlueMuted = blueRing;

  /// Carte de la deuxième page de présentation (D02).
  static const navy = IviaColors.berkeleyBlue;

  // Fonds et textes
  static const page = IviaColors.background;
  static const ink = IviaColors.text;
  static const label = IviaColors.textSecondary;
  static const muted = IviaColors.textMuted;

  /// Filets entre les lignes d'une carte.
  static const line = IviaPharmacyColors.line;

  /// Bord des boutons secondaires et des cases vides.
  static const outline = IviaPharmacyColors.outline;
  static const checkOff = IviaPharmacyColors.checkOff;

  /// Bouton désactivé (le texte est [muted]).
  static const disabled = IviaColors.border;

  // Cartes sombres
  /// Fond des cartes sombres : chiffres du jour, en-tête « Missions »,
  /// « Gains », code de retrait, gain de la course, bandeaux sur la carte.
  static const night = IviaColors.text;

  /// Cases et pastilles posées sur une carte sombre.
  static const nightTile = Color(0xFF223049);

  /// Bord des pastilles sur fond sombre (« 38 km »).
  static const nightOutline = Color(0xFF3A4860);

  /// Texte secondaire sur fond sombre (« AUJOURD'HUI »).
  static const nightMuted = Color(0xFF9DA9BA);

  // États
  static const red = IviaColors.imperialRed;
  static const redSoft = IviaColors.primarySoft;
  static const green = IviaPharmacyColors.green;
  static const greenSoft = IviaPharmacyColors.greenSoft;

  /// « En ligne » (point du bandeau D09).
  static const online = Color(0xFF3DD68C);
  static const warning = IviaPharmacyColors.warning;
  static const warningSoft = IviaPharmacyColors.warningSoft;

  /// Voile derrière une feuille (D16) : encre à 50 %.
  static const scrim = IviaPharmacyColors.scrim;
}
