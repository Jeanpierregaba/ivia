import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'components.dart';
import 'tokens.dart';

/// Illustration de l'écran d'autorisation de la localisation : cercles
/// concentriques, pastille centrale et quatre pastilles autour, icônes dans
/// la couleur de l'app (maquettes de la spec 030).
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
    Offset(-0.76, -0.59),
    Offset(0.74, -0.73),
    Offset(-0.69, 0.81),
    Offset(0.65, 0.67),
  ];

  @override
  Widget build(BuildContext context) {
    final k = size / 320;
    final r = size / 2;
    Widget disc(double diameter, Color fill, {Color? border}) => Container(
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
            color: Color(0x33000000),
            offset: Offset(0, 8),
            blurRadius: 20,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: iconSize * k),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            disc(320, Colors.transparent, border: const Color(0x40FFFFFF)),
            disc(210, const Color(0x14FFFFFF), border: const Color(0x59FFFFFF)),
            disc(110, const Color(0x24FFFFFF)),
            badge(center, 68, 30),
            for (final (i, spot) in _spots.indexed)
              Positioned(
                left: r + spot.dx * r - 22 * k,
                top: r + spot.dy * r - 22 * k,
                child: badge(satellites[i], 44, 20),
              ),
          ],
        ),
      ),
    );
  }
}

/// Écran d'autorisation de la localisation (spec 030) : panneau de la
/// couleur de l'app (logo, nom de l'espace, illustration), titre en deux
/// tons, texte, « Autoriser la localisation » et « Refuser ».
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
  });

  final IviaAppBrand brand;

  /// Nom de l'espace à côté du logo (« Business », « Livreur ») ; aucun pour
  /// l'acheteur.
  final String? space;

  /// Icônes de l'illustration (la couleur vient de [brand]).
  final ({IconData center, List<IconData> satellites}) radar;

  /// Début du titre (encre), puis partie colorée.
  final String title;
  final String titleAccent;
  final String body;

  final VoidCallback onAllow;
  final VoidCallback onRefuse;

  /// Demande en cours : boutons désactivés, indicateur dans le bouton.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: IviaColors.surface,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: brand.accent,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(48),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      IviaSpacing.xxl,
                      IviaSpacing.md,
                      IviaSpacing.xxl,
                      IviaSpacing.xxxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IviaLogoTile(
                              size: 34,
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
                        const SizedBox(height: IviaSpacing.xxl),
                        Center(
                          child: IviaLocationRadar(
                            center: radar.center,
                            satellites: radar.satellites,
                            color: brand.accent,
                            size: (width - 2 * IviaSpacing.xxl).clamp(200, 320),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    IviaSpacing.xxl,
                    IviaSpacing.xxl,
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
                          style: text.headlineLarge,
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.sm),
                      Text(
                        body,
                        style: text.bodyLarge?.copyWith(
                          color: IviaColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.xxl),
                      FilledButton.icon(
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
                      const SizedBox(height: IviaSpacing.sm),
                      TextButton(
                        onPressed: busy ? null : onRefuse,
                        style: TextButton.styleFrom(
                          foregroundColor: IviaColors.textSecondary,
                        ),
                        child: const Text('Refuser'),
                      ),
                    ],
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
