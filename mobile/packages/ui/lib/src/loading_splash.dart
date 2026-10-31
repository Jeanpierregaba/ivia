import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'tokens.dart';

/// Splash de chargement, dessiné par Flutter juste après le splash natif :
/// même fond et logotype au même endroit (aucun saut), plus un slogan et
/// trois points animés.
class IviaLoadingSplash extends StatefulWidget {
  const IviaLoadingSplash({
    super.key,
    required this.color,
    required this.tagline,
    this.logoWidth = 174,
  });

  final Color color;
  final String tagline;

  /// Largeur du logotype du splash natif (`flutter_native_splash.yaml`).
  final double logoWidth;

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
    final logoHeight = widget.logoWidth / IviaLogo.aspectRatio;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: widget.color,
        child: Stack(
          children: [
            Center(
              child: IviaLogo(color: IviaLogoColor.white, height: logoHeight),
            ),
            // Slogan sous le logo, sans décaler celui-ci.
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: logoHeight + 2 * IviaSpacing.xxl,
                  ),
                  child: Text(
                    widget.tagline,
                    textAlign: TextAlign.center,
                    // Titre en 700 : blanc sur Imperial n'est permis que pour
                    // les titres et boutons (docs/DESIGN.md, Contrastes).
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
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
