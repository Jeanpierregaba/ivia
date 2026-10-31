import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

// Illustrations de la présentation acheteur, dessinées d'après les maquettes
// du 2026-10-31 sur le plan de 324 × 421 dp d'OnboardingArtboard.
// Données fictives d'exemple ; photos et logos d'opérateurs : emplacements
// hachurés en attendant les visuels.

const _cardShadow = [
  BoxShadow(color: Color(0x290E2E54), blurRadius: 24, offset: Offset(0, 10)),
];

/// Page 1 : deux fiches produit et la pastille « Autour de moi ».
class NearbyIllustration extends StatelessWidget {
  const NearbyIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingArtboard(
      child: _Card(
        color: IviaColors.imperialRed,
        child: Stack(
          children: [
            const Positioned(
              left: 11,
              top: 10,
              width: 194,
              child: _Tilted(
                degrees: -4,
                child: _ProductCard(
                  name: 'Riz parfumé 5 kg',
                  price: '4 500 FCFA',
                  distance: '350 m',
                ),
              ),
            ),
            const Positioned(
              left: 132,
              top: 184,
              width: 180,
              child: _Tilted(
                degrees: 3,
                child: _ProductCard(
                  name: 'Pagne wax 6 yards',
                  price: '12 000 FCFA',
                  distance: '1,2 km',
                ),
              ),
            ),
            Positioned(
              left: 16,
              top: 361,
              height: 44,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 0, 18, 0),
                decoration: const ShapeDecoration(
                  color: IviaColors.berkeleyBlue,
                  shape: StadiumBorder(),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: IviaColors.imperialRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Autour de moi · Tokoin',
                      style: IviaTextStyles.bodyStrong.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page 2 : total à payer, choix Flooz / T-Money, « Paiement reçu ».
class PaymentIllustration extends StatelessWidget {
  const PaymentIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingArtboard(
      child: _Card(
        color: IviaColors.berkeleyBlue,
        child: Stack(
          children: [
            Positioned(
              left: 22,
              top: 59,
              width: 280,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: IviaColors.surface,
                  borderRadius: BorderRadius.circular(IviaRadius.large),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Total à payer',
                            style: IviaTextStyles.caption.copyWith(
                              color: IviaColors.textMuted,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            '16 500 FCFA',
                            style: IviaTextStyles.title2,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _Operator(name: 'Flooz', selected: true),
                    const SizedBox(height: 14),
                    const _Operator(name: 'T-Money', selected: false),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 136,
              top: 293,
              child: _Tilted(
                degrees: -3,
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.fromLTRB(10, 0, 18, 0),
                  decoration: const ShapeDecoration(
                    color: IviaColors.surface,
                    shape: StadiumBorder(),
                    shadows: _cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: IviaColors.cobaltBlue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('Paiement reçu', style: IviaTextStyles.bodyStrong),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page 3 : mosaïque livraison / retrait et code de remise.
class HandoverIllustration extends StatelessWidget {
  const HandoverIllustration({super.key});

  static const _outer = Radius.circular(IviaRadius.large);
  static const _inner = Radius.circular(IviaRadius.tile);

  @override
  Widget build(BuildContext context) {
    return OnboardingArtboard(
      child: Column(
        children: [
          Expanded(
            flex: 241,
            child: Row(
              children: [
                Expanded(
                  child: _Tile(
                    color: IviaColors.cobaltBlue,
                    radius: const BorderRadius.only(
                      topLeft: _outer,
                      topRight: _inner,
                      bottomLeft: _inner,
                      bottomRight: _inner,
                    ),
                    caption: 'Livreur ivia',
                    title: 'Livraison moto ou voiture',
                    onColor: Colors.white,
                  ),
                ),
                const SizedBox(width: IviaSpacing.mosaicGap),
                const Expanded(
                  child: _Tile(
                    color: IviaColors.surface,
                    radius: BorderRadius.only(
                      topLeft: _inner,
                      topRight: _outer,
                      bottomLeft: _inner,
                      bottomRight: _inner,
                    ),
                    caption: 'Sans frais',
                    title: 'Retrait en boutique',
                    onColor: IviaColors.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: IviaSpacing.mosaicGap),
          Expanded(
            flex: 172,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: IviaColors.imperialRed,
                borderRadius: BorderRadius.only(
                  topLeft: _inner,
                  topRight: _inner,
                  bottomLeft: _outer,
                  bottomRight: _outer,
                ),
              ),
              // Réduit au besoin (police plus large) plutôt que de déborder.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: OnboardingArtboard.size.width - 36,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Votre code de remise',
                        style: IviaTextStyles.bodyStrong.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final (i, digit)
                              in '4827'.split('').indexed) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 58,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: IviaColors.surface,
                                  borderRadius: BorderRadius.circular(
                                    IviaRadius.button,
                                  ),
                                ),
                                child: Text(
                                  digit,
                                  style: IviaTextStyles.title1.copyWith(
                                    color: IviaColors.imperialRed,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'À donner au livreur ou en boutique, à la remise.',
                        style: IviaTextStyles.caption.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.color, required this.child});

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

class _Tilted extends StatelessWidget {
  const _Tilted({required this.degrees, required this.child});

  final double degrees;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Transform.rotate(angle: degrees * math.pi / 180, child: child);
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.name,
    required this.price,
    required this.distance,
  });

  final String name;
  final String price;
  final String distance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 92, child: IviaImagePlaceholder()),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(name, style: IviaTextStyles.title3),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    price,
                    style: IviaTextStyles.figures,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ),
                Text(
                  distance,
                  style: IviaTextStyles.caption.copyWith(
                    color: IviaColors.cobaltBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Operator extends StatelessWidget {
  const _Operator({required this.name, required this.selected});

  final String name;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(IviaRadius.button),
        border: Border.all(
          color: selected ? IviaColors.imperialRed : IviaColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: IviaImagePlaceholder(radius: IviaRadius.tile),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: IviaTextStyles.bodyStrong)),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? IviaColors.imperialRed : null,
              border: selected
                  ? null
                  : Border.all(color: IviaColors.borderInput, width: 1.5),
            ),
            child: selected
                ? Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
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
