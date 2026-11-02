import 'package:flutter/material.dart';

import 'brand.dart';
import 'tokens.dart';

/// Logotype blanc dans une tuile de couleur (en-têtes, écran de connexion).
class IviaLogoTile extends StatelessWidget {
  const IviaLogoTile({
    super.key,
    this.size = 40,
    this.color = IviaColors.imperialRed,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: IviaLogo(color: IviaLogoColor.white, height: size * 0.3),
    );
  }
}

/// Bouton retour rond et blanc, en haut à gauche des écrans.
class IviaBackButton extends StatelessWidget {
  const IviaBackButton({super.key, required this.onPressed});

  /// `null` : bouton désactivé (envoi en cours).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Retour',
      icon: const Icon(Icons.arrow_back),
      style: IconButton.styleFrom(
        backgroundColor: IviaColors.surface,
        foregroundColor: IviaColors.text,
        fixedSize: const Size(48, 48),
      ),
    );
  }
}

/// Bouton rond et blanc des en-têtes, avec une pastille de nombre (le
/// panier et ses articles). Pastille masquée à 0, « 99+ » au-delà.
class IviaIconBadgeButton extends StatelessWidget {
  const IviaIconBadgeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.onPressed,
    this.semanticLabel,
  });

  final IconData icon;

  /// Info-bulle et nom lu (« Panier »).
  final String label;
  final int count;
  final VoidCallback? onPressed;

  /// Lu à la place de [label] (« Panier, 3 articles »).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final brand = IviaAppBrand.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: 48,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Material(
                  color: IviaColors.surface,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onPressed,
                    child: Icon(icon, color: IviaColors.text),
                  ),
                ),
              ),
              if (count > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: IgnorePointer(
                    // La pastille garde sa taille : le nombre est lu par
                    // [semanticLabel].
                    child: MediaQuery.withNoTextScaling(
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 20),
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(
                          color: brand.action,
                          shape: const StadiumBorder(
                            side: BorderSide(
                              color: IviaColors.surface,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: IviaColors.surface,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
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

/// Libellé au-dessus d'un champ ; le lecteur d'écran les lit ensemble.
class IviaFieldLabel extends StatelessWidget {
  const IviaFieldLabel({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Le libellé est porté par un conteneur autour du champ ; fusionner le
    // champ lui-même (MergeSemantics) casse ses annonces d'erreur.
    return Semantics(
      container: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: IviaColors.textSecondary),
            ),
          ),
          const SizedBox(height: IviaSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// Encart d'information : pastille de couleur et texte.
class IviaInfoCard extends StatelessWidget {
  const IviaInfoCard({
    super.key,
    required this.text,
    this.dotColor = IviaColors.info,
  });

  final String text;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(IviaSpacing.lg),
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: ExcludeSemantics(
              child: Container(
                width: IviaSpacing.sm,
                height: IviaSpacing.sm,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: IviaSpacing.md),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: IviaColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille blanche au texte rouge (ex. « Dernière étape »).
class IviaPill extends StatelessWidget {
  const IviaPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: IviaSpacing.lg,
        vertical: IviaSpacing.sm,
      ),
      decoration: const ShapeDecoration(
        color: IviaColors.surface,
        shape: StadiumBorder(),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: IviaAppBrand.of(context).link),
      ),
    );
  }
}

/// Emplacement hachuré d'une image pas encore fournie (photo, logo).
class IviaImagePlaceholder extends StatelessWidget {
  const IviaImagePlaceholder({super.key, this.radius = IviaRadius.button});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: const CustomPaint(
        painter: _HatchPainter(),
        child: SizedBox.expand(),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = IviaColors.border);
    final stripe = Paint()
      ..color = IviaColors.backgroundAlt
      ..strokeWidth = 4;
    for (var x = -size.height; x < size.width; x += 12) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stripe,
      );
    }
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) => false;
}
