import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'components.dart';
import 'tokens.dart';

/// Apparition unique et discrète : rien ne tourne en boucle sur cet écran.
const _appearDuration = Duration(milliseconds: 900);

Duration _appear(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false
    ? Duration.zero
    : _appearDuration;

/// Illustration de l'écran d'autorisation de la localisation : cercles
/// concentriques, pastille centrale et quatre pastilles autour, icônes dans
/// la couleur de l'app.
class IviaLocationRadar extends StatelessWidget {
  const IviaLocationRadar({
    super.key,
    required this.center,
    required this.satellites,
    required this.color,
    this.size = 320,
  }) : assert(satellites.length == 4);

  final IconData center;

  /// En haut à gauche, en haut à droite, en bas à gauche, en bas à droite.
  final List<IconData> satellites;
  final Color color;

  /// Diamètre du grand cercle ; tout le reste en découle (maquette : 320).
  final double size;

  /// Centre de chaque pastille, en fraction du rayon du grand cercle.
  static const _spots = [
    Offset(-0.75, -0.53),
    Offset(0.73, -0.72),
    Offset(-0.68, 0.79),
    Offset(0.68, 0.69),
  ];

  @override
  Widget build(BuildContext context) {
    final k = size / 320;
    final r = size / 2;
    Widget disc(double diameter, {Color? fill, Color? border}) => Container(
      width: diameter * k,
      height: diameter * k,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: border == null ? null : Border.all(color: border),
      ),
    );
    Widget badge(IconData icon, double diameter, double iconSize) => Container(
      width: diameter * k,
      height: diameter * k,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: IviaColors.surface,
        boxShadow: [
          BoxShadow(
            color: Color(0x2E000000),
            offset: Offset(0, 8),
            blurRadius: 22,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: iconSize * k),
    );
    // Du centre vers l'extérieur : chaque élément grandit doucement à son tour.
    Widget reveal(double t, double from, double start, Widget child) {
      final v = Curves.easeOutCubic.transform(
        ((t - start) / (1 - start)).clamp(0.0, 1.0),
      );
      return Opacity(
        opacity: v,
        child: Transform.scale(scale: from + (1 - from) * v, child: child),
      );
    }

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: _appear(context),
          builder: (context, t, _) => Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              reveal(
                t,
                0.92,
                0.2,
                disc(320, border: const Color(0x38FFFFFF)),
              ),
              reveal(
                t,
                0.92,
                0.1,
                disc(
                  214,
                  fill: const Color(0x0DFFFFFF),
                  border: const Color(0x38FFFFFF),
                ),
              ),
              reveal(t, 0.92, 0, disc(138, fill: const Color(0x24FFFFFF))),
              reveal(t, 0.8, 0, badge(center, 90, 44)),
              for (final (i, spot) in _spots.indexed)
                Positioned(
                  left: r + spot.dx * r - 24 * k,
                  top: r + spot.dy * r - 24 * k,
                  child: reveal(
                    t,
                    0.7,
                    0.25 + i * 0.08,
                    badge(satellites[i], 48, 24),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fond du panneau : dégradé de la couleur de l'app, bas en vague, vague plus
/// claire à droite et halo léger qui se fond dans le blanc de l'écran.
class _HeroWavePainter extends CustomPainter {
  const _HeroWavePainter(this.brand);

  final IviaAppBrand brand;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    final wave = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.86)
      ..cubicTo(w * 0.78, h * 0.93, w * 0.62, h, w * 0.42, h)
      ..cubicTo(w * 0.26, h, w * 0.1, h * 0.97, 0, h * 0.925)
      ..close();

    canvas.drawPath(
      wave.shift(const Offset(0, 8)),
      Paint()
        ..color = brand.heroLight.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawPath(
      wave,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: const Alignment(1, 0.4),
          colors: [brand.heroDeep, brand.accent, brand.heroLight],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipPath(wave);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.75, -0.7),
          radius: 0.9,
          colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    final swoosh = Path()
      ..moveTo(w, h * 0.6)
      ..cubicTo(w * 0.86, h * 0.78, w * 0.68, h * 0.84, w * 0.46, h * 1.02)
      ..lineTo(w, h * 1.02)
      ..close();
    canvas.drawPath(
      swoosh,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0x3DFFFFFF), Color(0x08FFFFFF)],
        ).createShader(swoosh.getBounds()),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeroWavePainter old) => old.brand != brand;
}

/// Écran d'autorisation de la localisation, le même pour toutes les apps :
/// panneau de la couleur de l'app (logo, nom de l'espace, illustration), titre
/// en deux tons, texte, « Autoriser la localisation » et action secondaire.
class IviaLocationPrompt extends StatelessWidget {
  const IviaLocationPrompt({
    super.key,
    required this.brand,
    required this.radar,
    required this.title,
    required this.titleAccent,
    required this.body,
    required this.onAllow,
    required this.onRefuse,
    this.space,
    this.busy = false,
    this.laterLabel = 'Plus tard',
  });

  final IviaAppBrand brand;

  /// Nom de l'espace à côté du logo (« Business », « Livreur ») ; aucun pour
  /// l'app ivia.
  final String? space;

  /// Icônes de l'illustration (la couleur vient de [brand]).
  final ({IconData center, List<IconData> satellites}) radar;

  /// Début du titre (encre), puis partie colorée.
  final String title;
  final String titleAccent;
  final String body;

  final VoidCallback onAllow;
  final VoidCallback onRefuse;

  /// Libellé de l'action secondaire, qui continue sans la position.
  final String laterLabel;

  /// Demande en cours : « Autoriser » occupé ; l'action secondaire reste active.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final screen = MediaQuery.sizeOf(context);
    final radarSize = max(
      200.0,
      min(min(screen.width * 0.84, screen.height * 0.42), 360.0),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Icônes claires sur le panneau ; barre de navigation Android blanche,
      // comme le bas de l'écran.
      value: SystemUiOverlayStyle.light.copyWith(
        systemNavigationBarColor: IviaColors.surface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: IviaColors.surface,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _HeroWavePainter(brand)),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        IviaSpacing.xxl,
                        IviaSpacing.md,
                        IviaSpacing.xxl,
                        radarSize * 0.15,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              IviaLogoTile(
                                size: 42,
                                color: IviaColors.surface,
                                logoTint: brand.accent,
                              ),
                              if (space case final space?) ...[
                                const SizedBox(width: IviaSpacing.md),
                                Flexible(
                                  child: Text(
                                    space,
                                    style: text.titleMedium?.copyWith(
                                      color: IviaColors.surface,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: IviaSpacing.md),
                          Center(
                            child: IviaLocationRadar(
                              center: radar.center,
                              satellites: radar.satellites,
                              color: brand.accent,
                              size: radarSize,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SafeArea(
                top: false,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: _appear(context),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, child) => Opacity(
                    opacity: v,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - v)),
                      child: child,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      IviaSpacing.xxl,
                      IviaSpacing.lg,
                      IviaSpacing.xxl,
                      IviaSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '$title '),
                                TextSpan(
                                  text: titleAccent,
                                  style: TextStyle(color: brand.highlight),
                                ),
                              ],
                            ),
                            style: text.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              height: 1.15,
                            ),
                          ),
                        ),
                        const SizedBox(height: IviaSpacing.md),
                        Text(
                          body,
                          style: text.bodyLarge?.copyWith(
                            color: IviaColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: IviaSpacing.xxl),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              colors: [brand.heroDeep, brand.action],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: brand.action.withValues(alpha: 0.28),
                                offset: const Offset(0, 10),
                                blurRadius: 24,
                              ),
                            ],
                          ),
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              disabledBackgroundColor: Colors.transparent,
                              foregroundColor: IviaColors.surface,
                              disabledForegroundColor: IviaColors.surface,
                              shadowColor: Colors.transparent,
                            ),
                            onPressed: busy ? null : onAllow,
                            icon: busy
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: IviaColors.surface,
                                    ),
                                  )
                                : const Icon(Icons.location_on),
                            label: const Text('Autoriser la localisation'),
                          ),
                        ),
                        const SizedBox(height: IviaSpacing.sm),
                        // Actif pendant la demande : une fenêtre du système
                        // sans réponse ne bloque jamais l'écran.
                        TextButton(
                          onPressed: onRefuse,
                          style: TextButton.styleFrom(
                            foregroundColor: IviaColors.textSecondary,
                          ),
                          child: Text(laterLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
