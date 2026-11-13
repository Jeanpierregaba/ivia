import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Cadre commun des apps ivia, posé autour de tout l'écran (`builder` de
/// `MaterialApp`) :
/// - grand écran (navigateur d'ordinateur, tablette à l'horizontale) : l'app
///   reste une colonne centrée, aux proportions d'un téléphone, posée sur un
///   fond doux, au lieu d'étirer chaque écran sur toute la largeur ;
/// - téléphone et tablette à la verticale : pleine largeur ;
/// - texte agrandi par le système : suivi jusqu'à 200 %, borné au-delà.
///
/// Les écrans qui lisent la largeur (`MediaQuery.sizeOf`) voient celle de la
/// colonne : grilles et marges s'adaptent d'elles-mêmes.
class IviaResponsiveFrame extends StatelessWidget {
  const IviaResponsiveFrame({
    super.key,
    required this.child,
    this.maxWidth = 600,
  });

  final Widget child;

  /// Largeur de la colonne sur grand écran.
  final double maxWidth;

  /// En dessous, l'app occupe toute la largeur.
  static const wideFrom = 900.0;

  /// Texte agrandi par le système : suivi jusqu'à 200 % (les écrans gèrent
  /// le grand texte), borné au-delà.
  static const maxTextScale = 2.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final scaler = mq.textScaler.clamp(maxScaleFactor: maxTextScale);

    if (size.width < wideFrom) {
      return MediaQuery(
        data: mq.copyWith(textScaler: scaler),
        child: child,
      );
    }

    final width = math.min(maxWidth, size.width);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8EDF4), IviaColors.background, Color(0xFFF1E9EC)],
        ),
      ),
      child: Center(
        child: Container(
          width: width,
          height: size.height,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            color: IviaColors.background,
            boxShadow: [
              BoxShadow(
                color: Color(0x2E0E2E54),
                blurRadius: 60,
                spreadRadius: -8,
                offset: Offset(0, 24),
              ),
            ],
          ),
          child: MediaQuery(
            data: mq.copyWith(
              size: Size(width, size.height),
              textScaler: scaler,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
