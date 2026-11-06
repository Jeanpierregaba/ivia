import 'package:flutter/painting.dart';

import 'tokens.dart';

/// Couleurs de l'app pharmacie, relevées sur les maquettes F00 à F23
/// (spec 031). Les neutres et les rouges sont ceux de la charte commune.
abstract final class IviaPharmacyColors {
  // Verts
  static const green = Color(0xFF0B7A55);
  static const greenDeep = Color(0xFF075C40);
  static const greenSoft = Color(0xFFE3F2EC);

  /// Interrupteur allumé, sur fond vert.
  static const switchOn = Color(0xFF2FBF85);

  /// Texte secondaire sur fond vert (« Vous recevez les alertes »).
  static const onGreenMuted = Color(0xFFCDEBDD);

  /// Cercles de la cloche de l'alerte entrante (F10).
  static const ringOuter = Color(0xFF1A694F);
  static const ringInner = Color(0xFF367B64);

  // Fonds et textes
  static const page = IviaColors.background;
  static const ink = IviaColors.text;
  static const label = IviaColors.textSecondary;
  static const muted = IviaColors.textMuted;

  /// Filets entre les lignes d'une carte.
  static const line = Color(0xFFEEF0F3);

  /// Bord des boutons secondaires.
  static const outline = Color(0xFFD5DAE2);

  /// Bord d'une case à cocher vide.
  static const checkOff = Color(0xFFC9CFD8);

  /// Bouton désactivé (le texte est [muted]).
  static const disabled = IviaColors.border;

  // Urgence et erreurs
  static const red = IviaColors.imperialRed;
  static const redSoft = IviaColors.primarySoft;
  static const danger = IviaColors.cornellRed;

  // Information et avertissement
  static const blue = IviaColors.cobaltBlue;
  static const blueSoft = Color(0xFFE3EDF9);
  static const warning = Color(0xFF8A5A00);
  static const warningSoft = Color(0xFFFFF1D6);

  /// Ordonnance en grand (F12).
  static const night = IviaColors.text;
  static const nightPanel = Color(0xFF15253A);

  /// Voile derrière une feuille (F18) : encre à 50 %.
  static const scrim = Color(0x800A1A30);
}
