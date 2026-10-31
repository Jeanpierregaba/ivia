import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'tokens.dart';

/// Splash de chargement, dessiné par Flutter juste après le splash natif :
/// même fond et même visuel au même endroit (aucun saut), plus un titre
/// éventuel, un slogan et trois points animés.
///
/// Deux variantes, comme les splashs natifs (`flutter_native_splash.yaml`) :
/// logotype blanc de 174 dp (acheteur), ou tuile blanche de 172 dp portant le
/// logotype de la couleur de l'app ([tile], marchand).
class IviaLoadingSplash extends StatefulWidget {
  const IviaLoadingSplash({
    super.key,
    required this.brand,
    required this.tagline,
    this.title,
    this.tile = false,
  });

  final IviaAppBrand brand;
  final String tagline;

  /// Nom de l'app sous le visuel (« Marchand »).
  final String? title;
  final bool tile;

  /// Tailles des splashs natifs.
  static const logoWidth = 174.0;
  static const tileSize = 172.0;

  @override
  State<IviaLoadingSplash> createState() => _IviaLoadingSplashState();
}

class _IviaLoadingSplashState extends State<IviaLoadingSplash>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Animations réduites (accessibilité) : points immobiles.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final visualHeight = widget.tile
        ? IviaLoadingSplash.tileSize
        : IviaLoadingSplash.logoWidth / IviaLogo.aspectRatio;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: widget.brand.accent,
        child: Stack(
          children: [
            Center(child: widget.tile ? _tile() : _wordmark()),
            // Textes sous le visuel, sans décaler celui-ci (40 dp sous le
            // logotype, maquette acheteur ; 24 dp sous la tuile, marchand).
            Positioned(
              left: IviaSpacing.screen,
              right: IviaSpacing.screen,
              top:
                  MediaQuery.sizeOf(context).height / 2 +
                  visualHeight / 2 +
                  (widget.tile ? IviaSpacing.xxl : IviaSpacing.huge),
              child: Column(
                children: [
                  if (widget.title case final title?) ...[
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: IviaSpacing.lg),
                  ],
                  Text(
                    widget.tagline,
                    textAlign: TextAlign.center,
                    // Acheteur : titre en 700, seul usage permis du blanc sur
                    // Imperial (docs/DESIGN.md, Contrastes). Sur Berkeley, le
                    // texte courant est libre.
                    style: widget.tile
                        ? textTheme.bodyLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                          )
                        : textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: IviaSpacing.huge + MediaQuery.paddingOf(context).bottom,
              child: Semantics(
                label: 'Chargement',
                child: ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [for (var i = 0; i < 3; i++) _dot(i)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wordmark() => const IviaLogo(
    color: IviaLogoColor.white,
    height: IviaLoadingSplash.logoWidth / IviaLogo.aspectRatio,
  );

  /// Mêmes proportions que l'image du splash natif (rayon 21,3 %, logotype
  /// aux 354/516 de la tuile).
  Widget _tile() => Container(
    width: IviaLoadingSplash.tileSize,
    height: IviaLoadingSplash.tileSize,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(IviaLoadingSplash.tileSize * 0.213),
    ),
    child: IviaLogo(
      color: widget.brand.logoOnLight,
      height: IviaLoadingSplash.tileSize * 354 / 516 / IviaLogo.aspectRatio,
    ),
  );

  /// Le point actif est blanc, les autres plus transparents ; il avance
  /// d'un cran par tiers de cycle.
  Widget _dot(int i) {
    final active = (_controller.value * 3).floor() % 3;
    final opacity = switch ((i - active) % 3) {
      0 => 1.0,
      1 => 0.6,
      _ => 0.35,
    };
    return Container(
      width: IviaSpacing.sm,
      height: IviaSpacing.sm,
      margin: const EdgeInsets.symmetric(horizontal: IviaSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}
