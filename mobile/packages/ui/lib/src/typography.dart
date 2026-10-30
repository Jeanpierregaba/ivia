import 'package:flutter/material.dart';

import 'tokens.dart';

/// Styles de texte de la charte (docs/DESIGN.md, section Typographie).
///
/// Police unique : Parkinsans, embarquée dans ce paquet (pas de téléchargement
/// au lancement). Les interlettrages en % de la charte sont convertis en
/// pixels : `taille × pourcentage`.
abstract final class IviaTextStyles {
  static const fontFamily = 'Parkinsans';
  static const package = 'ivia_ui';

  static TextStyle _style(
    double size,
    double lineHeight,
    FontWeight weight, {
    double letterSpacingPercent = 0,
  }) => TextStyle(
    fontFamily: fontFamily,
    package: package,
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    letterSpacing: size * letterSpacingPercent / 100,
    color: IviaColors.text,
  );

  static final display = _style(
    34,
    38,
    FontWeight.w700,
    letterSpacingPercent: -2,
  );
  static final title1 = _style(
    28,
    32,
    FontWeight.w700,
    letterSpacingPercent: -2,
  );
  static final title2 = _style(
    22,
    28,
    FontWeight.w700,
    letterSpacingPercent: -1,
  );
  static final title3 = _style(17, 22, FontWeight.w700);
  static final body = _style(15, 22, FontWeight.w400);
  static final bodyStrong = _style(15, 22, FontWeight.w600);
  static final caption = _style(13, 18, FontWeight.w400);

  /// Surtitre : à écrire en majuscules dans le texte (`.toUpperCase()`).
  static final overline = _style(
    12,
    16,
    FontWeight.w600,
    letterSpacingPercent: 8,
  );
  static final button = _style(16, 20, FontWeight.w700);

  /// Chiffres (prix, durées, distances, codes) : 600.
  ///
  /// Parkinsans n'a pas de chiffres tabulaires (`tnum`) : un compte à rebours
  /// doit placer chaque chiffre dans une case de largeur fixe.
  static final figures = bodyStrong;

  /// Correspondance avec les rôles Material 3, pour que les composants
  /// standards (boutons, champs, barres, dialogues) utilisent la charte.
  static TextTheme get textTheme => TextTheme(
    displayLarge: display,
    displayMedium: display,
    displaySmall: display,
    headlineLarge: title1,
    headlineMedium: title1,
    headlineSmall: title2,
    titleLarge: title2,
    titleMedium: title3,
    titleSmall: bodyStrong,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: caption.copyWith(color: IviaColors.textMuted),
    labelLarge: button,
    labelMedium: caption.copyWith(fontWeight: FontWeight.w600),
    labelSmall: overline,
  );
}
