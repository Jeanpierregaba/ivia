import 'dart:async';

import 'package:flutter/material.dart';

import 'pharmacy_colors.dart';
import 'tokens.dart';

/// Couleur du logotype (docs/DESIGN.md, section Logo).
enum IviaLogoColor {
  white('logo_white.png'),
  imperial('logo_imperial.png'),
  berkeley('logo_berkeley.png'),
  cobalt('logo_cobalt.png');

  const IviaLogoColor(this._file);

  final String _file;

  String get asset => 'assets/brand/$_file';
}

/// Logotype `ivia`, jamais redessiné : image tirée des fichiers de la charte.
class IviaLogo extends StatelessWidget {
  const IviaLogo({super.key, required this.color, this.height = 32, this.tint});

  final IviaLogoColor color;

  /// Teinte du logotype blanc (couleur sans fichier dédié, comme le vert de
  /// la pharmacie) ; remplace [color].
  final Color? tint;

  /// Hauteur du logotype, points des « i » compris.
  final double height;

  /// Largeur / hauteur des images de `assets/brand/`.
  static const aspectRatio = 678 / 336;

  /// Décode le logotype à l'avance, pour qu'il s'affiche dès la première
  /// image (sinon, l'écran apparaît d'abord sans lui). À appeler avant
  /// `runApp()` : le splash natif reste affiché pendant ce temps.
  static Future<void> precache(IviaLogoColor color) {
    final done = Completer<void>();
    final stream = AssetImage(
      color.asset,
      package: 'ivia_ui',
    ).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        if (!done.isCompleted) done.complete();
        stream.removeListener(listener);
      },
      onError: (_, _) {
        // Sans l'image en cache, elle se chargera simplement plus tard.
        if (!done.isCompleted) done.complete();
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return done.future;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ivia',
      image: true,
      child: ExcludeSemantics(
        child: Image.asset(
          tint == null ? color.asset : IviaLogoColor.white.asset,
          package: 'ivia_ui',
          height: height,
          width: height * aspectRatio,
          color: tint,
          colorBlendMode: tint == null ? null : BlendMode.srcIn,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// Identité de chaque app : couleur (celle du splash, reprise dans
/// `flutter_native_splash.yaml`), couleurs d'action et logotype sur fond
/// clair (docs/DESIGN.md, « Couleur de chaque app »).
final class IviaAppBrand {
  const IviaAppBrand._({
    required this.accent,
    required this.accentSoft,
    required this.logoOnLight,
    required this.action,
    required this.link,
    required this.highlight,
    required this.heroDeep,
    required this.heroLight,
  });

  /// Marque de l'app en cours, portée par le thème (`IviaTheme.light`).
  static IviaAppBrand of(BuildContext context) =>
      Theme.of(context).extension<IviaBrandTheme>()?.brand ?? buyer;

  /// Fond du splash, pictogrammes, indicateurs, en-têtes de section.
  final Color accent;

  /// Fond pâle derrière un pictogramme ou un élément sélectionné.
  final Color accentSoft;

  final IviaLogoColor logoOnLight;

  /// Action principale : boutons pleins, champ actif, case cochée.
  final Color action;

  /// Texte cliquable (boutons texte, liens) : contraste de texte courant.
  final Color link;

  /// Partie colorée des titres (24 px et plus).
  final Color highlight;

  /// Dégradé des grands panneaux : du plus sombre au plus clair, autour de [accent].
  final Color heroDeep;
  final Color heroLight;

  static const buyer = IviaAppBrand._(
    accent: IviaColors.imperialRed,
    accentSoft: IviaColors.primarySoft,
    logoOnLight: IviaLogoColor.imperial,
    action: IviaColors.imperialRed,
    link: IviaColors.cornellRed,
    highlight: IviaColors.imperialRed,
    heroDeep: Color(0xFFCF0F2B),
    heroLight: Color(0xFFFF5364),
  );

  static const seller = IviaAppBrand._(
    accent: IviaColors.berkeleyBlue,
    accentSoft: IviaColors.secondarySoft,
    logoOnLight: IviaLogoColor.berkeley,
    action: IviaColors.berkeleyBlue,
    link: IviaColors.berkeleyBlue,
    highlight: IviaColors.cobaltBlue,
    heroDeep: Color(0xFF071C40),
    heroLight: Color(0xFF28568F),
  );

  static const driver = IviaAppBrand._(
    accent: IviaColors.cobaltBlue,
    accentSoft: IviaColors.secondarySoft,
    logoOnLight: IviaLogoColor.cobalt,
    action: IviaColors.cobaltBlue,
    link: IviaColors.cobaltBlue,
    highlight: IviaColors.cobaltBlue,
    heroDeep: Color(0xFF0A45C4),
    heroLight: Color(0xFF1C86FF),
  );

  /// App pharmacie : vert des maquettes F00 à F23 (spec 031), logotype
  /// Berkeley.
  static const pharmacy = IviaAppBrand._(
    accent: IviaPharmacyColors.green,
    accentSoft: IviaPharmacyColors.greenSoft,
    logoOnLight: IviaLogoColor.berkeley,
    action: IviaPharmacyColors.green,
    link: IviaPharmacyColors.green,
    highlight: IviaPharmacyColors.green,
    heroDeep: IviaPharmacyColors.greenDeep,
    heroLight: IviaPharmacyColors.switchOn,
  );
}

/// Porte la marque de l'app dans le thème.
class IviaBrandTheme extends ThemeExtension<IviaBrandTheme> {
  const IviaBrandTheme(this.brand);

  final IviaAppBrand brand;

  @override
  IviaBrandTheme copyWith({IviaAppBrand? brand}) =>
      IviaBrandTheme(brand ?? this.brand);

  @override
  IviaBrandTheme lerp(IviaBrandTheme? other, double t) => this;
}
