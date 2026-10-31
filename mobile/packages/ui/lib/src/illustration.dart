import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

// Briques des illustrations de présentation (OnboardingArtboard), communes
// aux apps : cartes, éléments inclinés, tuiles de mosaïque, pastilles.

/// Ombre des éléments posés sur une carte d'illustration (seul usage des
/// ombres sur des cartes, docs/DESIGN.md).
const illustrationShadow = [
  BoxShadow(color: Color(0x290E2E54), blurRadius: 24, offset: Offset(0, 10)),
];

/// Grande carte de couleur qui porte une illustration.
class IllustrationCard extends StatelessWidget {
  const IllustrationCard({super.key, required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(IviaRadius.large),
      ),
      child: child,
    );
  }
}

/// Élément légèrement incliné (fiches, pastilles).
class Tilted extends StatelessWidget {
  const Tilted({super.key, required this.degrees, required this.child});

  final double degrees;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Transform.rotate(angle: degrees * math.pi / 180, child: child);
}

/// Tuile de mosaïque : légende en haut, titre en bas.
class MosaicTile extends StatelessWidget {
  const MosaicTile({
    super.key,
    required this.color,
    required this.radius,
    required this.caption,
    required this.title,
    required this.onColor,
  });

  final Color color;
  final BorderRadius radius;
  final String caption;
  final String title;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color, borderRadius: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            style: IviaTextStyles.caption.copyWith(
              color: onColor.withValues(alpha: 0.8),
            ),
          ),
          const Spacer(),
          Text(
            title,
            style: IviaTextStyles.title2.copyWith(color: onColor),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Pastille blanche avec une coche (« Paiement reçu », « Produit ajouté »).
class CheckPill extends StatelessWidget {
  const CheckPill({super.key, required this.label, required this.checkColor});

  final String label;
  final Color checkColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.fromLTRB(10, 0, 18, 0),
      decoration: const ShapeDecoration(
        color: IviaColors.surface,
        shape: StadiumBorder(),
        shadows: illustrationShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: checkColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(label, style: IviaTextStyles.bodyStrong),
        ],
      ),
    );
  }
}
