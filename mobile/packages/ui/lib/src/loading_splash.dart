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
/// Tuile du splash : taille, coins et logotype. Par défaut, celle du splash
/// natif du marchand.
class IviaSplashTile {
  const IviaSplashTile({
    this.size = IviaLoadingSplash.tileSize,
    this.radiusRatio = 0.213,
    this.logoRatio = 354 / 516,
    this.logoTint,
  });

  final double size;

  /// Rayon des coins et largeur du logotype, en part de [size].
  final double radiusRatio;
  final double logoRatio;

  /// Logotype blanc teinté (vert de la pharmacie) à la place de celui de la
  /// marque.
  final Color? logoTint;
}

class IviaLoadingSplash extends StatefulWidget {
  const IviaLoadingSplash({
    super.key,
    required this.brand,
    required this.tagline,
    this.title,
    this.tile = false,
    this.tileStyle = const IviaSplashTile(),
    this.titleStyle,
    this.taglineStyle,
    this.centerGroup = false,
  });

  final IviaAppBrand brand;
  final String tagline;

  /// Nom de l'app sous le visuel (« Marchand »).
  final String? title;
  final bool tile;
  final IviaSplashTile tileStyle;

  /// Retouches du titre et du slogan, fusionnées avec leurs styles.
  final TextStyle? titleStyle;
  final TextStyle? taglineStyle;

  /// Centre l'ensemble visuel, titre et slogan (pharmacie, sans visuel au
  /// splash natif) plutôt que le visuel seul.
  final bool centerGroup;

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
        ? widget.tileStyle.size
        : IviaLoadingSplash.logoWidth / IviaLogo.aspectRatio;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: widget.brand.accent,
        child: Stack(
          children: [
            if (widget.centerGroup)
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(IviaSpacing.screen),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      widget.tile ? _tile() : _wordmark(),
                      SizedBox(
                        height: widget.tile
                            ? IviaSpacing.xxl
                            : IviaSpacing.huge,
                      ),
                      _texts(textTheme),
                    ],
                  ),
                ),
              )
            else ...[
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
                child: _texts(textTheme),
              ),
            ],
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

  Widget _texts(TextTheme textTheme) => Column(
    children: [
      if (widget.title case final title?) ...[
        Text(
          title,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall
              ?.copyWith(color: Colors.white)
              .merge(widget.titleStyle),
        ),
        const SizedBox(height: IviaSpacing.lg),
      ],
      Text(
        widget.tagline,
        textAlign: TextAlign.center,
        // Acheteur : titre en 700, seul usage permis du blanc sur
        // Imperial (docs/DESIGN.md, Contrastes). Sur Berkeley, le
        // texte courant est libre.
        style:
            (widget.tile
                    ? textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      )
                    : textTheme.titleMedium?.copyWith(color: Colors.white))
                ?.merge(widget.taglineStyle),
      ),
    ],
  );

  Widget _wordmark() => const IviaLogo(
    color: IviaLogoColor.white,
    height: IviaLoadingSplash.logoWidth / IviaLogo.aspectRatio,
  );

  /// Mêmes proportions que l'image du splash natif (rayon 21,3 %, logotype
  /// aux 354/516 de la tuile).
  Widget _tile() {
    final style = widget.tileStyle;
    return Container(
      width: style.size,
      height: style.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(style.size * style.radiusRatio),
      ),
      child: IviaLogo(
        color: style.logoTint == null
            ? widget.brand.logoOnLight
            : IviaLogoColor.white,
        tint: style.logoTint,
        height: style.size * style.logoRatio / IviaLogo.aspectRatio,
      ),
    );
  }

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
