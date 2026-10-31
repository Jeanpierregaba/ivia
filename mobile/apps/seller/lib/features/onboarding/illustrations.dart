import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

// Illustrations de la présentation marchand, dessinées d'après les maquettes
// du 2026-10-31 sur le plan de 324 × 421 dp d'OnboardingArtboard.
// Données fictives d'exemple ; photos : emplacements hachurés.

/// Page 1 : fiche de la boutique, ses produits, « Produit ajouté ».
class ShopIllustration extends StatelessWidget {
  const ShopIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingArtboard(
      child: IllustrationCard(
        color: IviaColors.berkeleyBlue,
        child: Stack(
          children: [
            Positioned(
              left: 18,
              top: 24,
              width: 288,
              child: Tilted(
                degrees: -2,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: IviaColors.surface,
                    borderRadius: BorderRadius.circular(IviaRadius.large),
                    boxShadow: illustrationShadow,
                  ),
                  child: const Column(
                    children: [
                      _ShopHeader(),
                      _Divider(),
                      _ProductRow(
                        name: 'Riz parfumé 5 kg',
                        detail: 'Stock 12',
                        price: '4 500 F',
                      ),
                      _Divider(),
                      _ProductRow(
                        name: 'Huile 1 L',
                        detail: 'Stock 30',
                        price: '1 500 F',
                      ),
                      _Divider(),
                      _ProductRow(
                        name: 'Sucre 1 kg',
                        detail: 'Disponible',
                        price: '800 F',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 138,
              top: 330,
              child: Tilted(
                degrees: 3,
                child: CheckPill(
                  label: 'Produit ajouté',
                  checkColor: IviaColors.berkeleyBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page 2 : commande payée à accepter, « Paiement reçu · Flooz ».
class PaidOrderIllustration extends StatelessWidget {
  const PaidOrderIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingArtboard(
      child: IllustrationCard(
        color: IviaColors.berkeleyBlue,
        child: Stack(
          children: [
            Positioned(
              left: 22,
              top: 94,
              width: 280,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: IviaColors.surface,
                  borderRadius: BorderRadius.circular(IviaRadius.large),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'COMMANDE PAYÉE',
                            style: IviaTextStyles.overline.copyWith(
                              color: IviaColors.berkeleyBlue,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: const ShapeDecoration(
                            color: IviaColors.berkeleyBlue,
                            shape: StadiumBorder(),
                          ),
                          child: Text(
                            '14:52',
                            style: IviaTextStyles.figures.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '#1042 · 3 articles',
                            style: IviaTextStyles.title3,
                          ),
                        ),
                        Text('16 500 F', style: IviaTextStyles.title3),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _FakeButton(
                            label: 'Refuser',
                            background: IviaColors.background,
                            foreground: IviaColors.text,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: _FakeButton(
                            label: 'Accepter',
                            background: IviaColors.berkeleyBlue,
                            foreground: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 22,
              top: 258,
              child: Tilted(
                degrees: -3,
                child: CheckPill(
                  label: 'Paiement reçu · Flooz',
                  checkColor: IviaColors.cobaltBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page 3 : livraison ou retrait, et saisie du code du client.
class SellerHandoverIllustration extends StatelessWidget {
  const SellerHandoverIllustration({super.key});

  static const _outer = Radius.circular(IviaRadius.large);
  static const _inner = Radius.circular(IviaRadius.tile);

  @override
  Widget build(BuildContext context) {
    return OnboardingArtboard(
      child: Column(
        children: [
          const Expanded(
            flex: 219,
            child: Row(
              children: [
                Expanded(
                  child: MosaicTile(
                    color: IviaColors.cobaltBlue,
                    radius: BorderRadius.only(
                      topLeft: _outer,
                      topRight: _inner,
                      bottomLeft: _inner,
                      bottomRight: _inner,
                    ),
                    caption: 'Livraison',
                    title: 'Un livreur ivia passe',
                    onColor: Colors.white,
                  ),
                ),
                SizedBox(width: IviaSpacing.mosaicGap),
                Expanded(
                  child: MosaicTile(
                    color: IviaColors.surface,
                    radius: BorderRadius.only(
                      topLeft: _inner,
                      topRight: _outer,
                      bottomLeft: _inner,
                      bottomRight: _inner,
                    ),
                    caption: 'Retrait',
                    title: 'Le client vient en boutique',
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
                color: IviaColors.berkeleyBlue,
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
                        'Saisir le code du client',
                        style: IviaTextStyles.bodyStrong.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          _CodeBox(digit: '4'),
                          SizedBox(width: 8),
                          _CodeBox(digit: '8'),
                          SizedBox(width: 8),
                          _CodeBox(cursor: true),
                          SizedBox(width: 8),
                          _CodeBox(),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Le code prouve que la commande a bien été remise.',
                        style: IviaTextStyles.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
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

class _ShopHeader extends StatelessWidget {
  const _ShopHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 40,
          height: 40,
          child: IviaImagePlaceholder(radius: IviaRadius.tile),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chez Afi', style: IviaTextStyles.title3),
              Text(
                'Alimentation · Tokoin',
                style: IviaTextStyles.caption.copyWith(
                  color: IviaColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: const ShapeDecoration(
            color: IviaColors.secondarySoft,
            shape: StadiumBorder(),
          ),
          child: Text(
            'Publiée',
            style: IviaTextStyles.caption.copyWith(
              color: IviaColors.cobaltBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.name,
    required this.detail,
    required this.price,
  });

  final String name;
  final String detail;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 40,
          height: 40,
          child: IviaImagePlaceholder(radius: IviaRadius.tile),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: IviaTextStyles.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                detail,
                style: IviaTextStyles.caption.copyWith(
                  color: IviaColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        Text(price, style: IviaTextStyles.figures),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 10),
    child: Divider(height: 1),
  );
}

class _FakeButton extends StatelessWidget {
  const _FakeButton({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(IviaRadius.button),
      ),
      child: Text(
        label,
        style: IviaTextStyles.bodyStrong.copyWith(color: foreground),
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({this.digit, this.cursor = false});

  final String? digit;
  final bool cursor;

  @override
  Widget build(BuildContext context) {
    final filled = digit != null || cursor;
    return Expanded(
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? IviaColors.surface
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(IviaRadius.button),
        ),
        child: digit != null
            ? Text(digit!, style: IviaTextStyles.title1)
            : cursor
            ? Container(width: 2, height: 24, color: IviaColors.berkeleyBlue)
            : null,
      ),
    );
  }
}
