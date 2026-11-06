import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

// Illustrations de la présentation pharmacie, dessinées d'après les maquettes
// F01 à F03 (spec 031) sur le plan de 324 × 421 dp d'OnboardingArtboard.
// Données fictives d'exemple.

const _ink = IviaPharmacyColors.ink;
const _green = IviaPharmacyColors.green;

/// Grand panneau de couleur aux coins de 28 dp.
class _Panel extends StatelessWidget {
  const _Panel({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(28),
    ),
    child: child,
  );
}

/// Pastille blanche inclinée : rond de couleur coché, puis le texte.
class _CheckBadge extends StatelessWidget {
  const _CheckBadge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    padding: const EdgeInsets.fromLTRB(10, 0, 18, 0),
    decoration: const ShapeDecoration(
      color: Colors.white,
      shape: StadiumBorder(),
      shadows: illustrationShadow,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CheckDot(color: color),
        const SizedBox(width: 12),
        Text(text, style: IviaTextStyles.title3.copyWith(fontSize: 16)),
      ],
    ),
  );
}

class _CheckDot extends StatelessWidget {
  const _CheckDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: const Icon(Icons.check, size: 16, color: Colors.white),
  );
}

/// Ligne produit : icône, nom et forme, quantité.
class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.name,
    required this.form,
    required this.quantity,
  });
  final String name, form, quantity;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: IviaPharmacyColors.greenSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.medication, size: 20, color: _green),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              style: IviaTextStyles.title3.copyWith(fontSize: 15),
            ),
            Text(
              form,
              style: IviaTextStyles.caption.copyWith(
                color: IviaPharmacyColors.muted,
              ),
            ),
          ],
        ),
      ),
      Text(quantity, style: IviaTextStyles.title3.copyWith(fontSize: 15)),
    ],
  );
}

/// F01 : une alerte qui arrive, et « Sonnerie même app fermée ».
class AlertIllustration extends StatelessWidget {
  const AlertIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingArtboard(
      child: _Panel(
        color: _green,
        child: Stack(
          children: [
            Positioned(
              left: 20,
              top: 76,
              width: 284,
              child: Tilted(
                degrees: -2,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: illustrationShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'NOUVELLE ALERTE',
                              style: IviaTextStyles.overline.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: IviaPharmacyColors.red,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: const ShapeDecoration(
                              color: IviaPharmacyColors.redSoft,
                              shape: StadiumBorder(),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.timer,
                                  size: 14,
                                  color: IviaPharmacyColors.red,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '19:42',
                                  style: IviaTextStyles.caption.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: IviaPharmacyColors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '2 produits · client à 650 m',
                        style: IviaTextStyles.title3.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 14),
                      const _ProductRow(
                        name: 'Paracétamol 1000 mg',
                        form: 'Comprimés',
                        quantity: '×1',
                      ),
                      const SizedBox(height: 12),
                      const _ProductRow(
                        name: 'Amoxicilline 500 mg',
                        form: 'Gélules',
                        quantity: '×2',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 42,
              top: 282,
              child: Tilted(
                degrees: 3,
                child: _CheckBadge(
                  text: 'Sonnerie même app fermée',
                  color: IviaPharmacyColors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// F02 : la réponse, produit par produit, et « Réponse envoyée ».
class ResponseIllustration extends StatelessWidget {
  const ResponseIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    Widget line(String name, String price) => Row(
      children: [
        const _CheckDot(color: _green),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            style: IviaTextStyles.bodyStrong.copyWith(fontSize: 14),
          ),
        ),
        const SizedBox(width: 8),
        Text(price, style: IviaTextStyles.title3.copyWith(fontSize: 14)),
      ],
    );
    return OnboardingArtboard(
      child: _Panel(
        color: IviaPharmacyColors.greenDeep,
        child: Stack(
          children: [
            Positioned(
              left: 22,
              top: 88,
              width: 280,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    line('Paracétamol 1000 mg ×1', '1 250 F'),
                    const SizedBox(height: 12),
                    line('Amoxicilline 500 mg ×2', '6 200 F'),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: IviaPharmacyColors.line),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Total indicatif',
                            style: IviaTextStyles.title3.copyWith(fontSize: 17),
                          ),
                        ),
                        Text(
                          '7 450 F',
                          style: IviaTextStyles.title3.copyWith(fontSize: 17),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 22,
              top: 270,
              child: Tilted(
                degrees: -3,
                child: _CheckBadge(text: 'Réponse envoyée', color: _green),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// F03 : retrait au comptoir ou livreur, et le code de retrait du client.
class HandoverIllustration extends StatelessWidget {
  const HandoverIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile({
      required Color color,
      required IconData icon,
      required Color iconColor,
      required String title,
      required Color titleColor,
      required BorderRadius radius,
    }) => Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(color: color, borderRadius: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: iconColor),
          const Spacer(),
          Text(
            title,
            style: IviaTextStyles.title2.copyWith(
              color: titleColor,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
    const outer = Radius.circular(24);
    const inner = Radius.circular(10);
    return OnboardingArtboard(
      child: Column(
        children: [
          SizedBox(
            height: 249,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: tile(
                    color: _green,
                    icon: Icons.storefront,
                    iconColor: Colors.white,
                    title: 'Le client\nvient au\ncomptoir',
                    titleColor: Colors.white,
                    radius: const BorderRadius.only(
                      topLeft: outer,
                      topRight: inner,
                      bottomLeft: inner,
                      bottomRight: inner,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: tile(
                    color: Colors.white,
                    icon: Icons.two_wheeler,
                    iconColor: _green,
                    title: 'Un livreur\nivia passe',
                    titleColor: _ink,
                    radius: const BorderRadius.only(
                      topLeft: inner,
                      topRight: outer,
                      bottomLeft: inner,
                      bottomRight: inner,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              decoration: const BoxDecoration(
                color: IviaPharmacyColors.greenDeep,
                borderRadius: BorderRadius.only(
                  topLeft: inner,
                  topRight: inner,
                  bottomLeft: outer,
                  bottomRight: outer,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Code de retrait du client',
                    maxLines: 1,
                    style: IviaTextStyles.bodyStrong.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final (i, d) in '3916'.split('').indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 54,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              d,
                              style: IviaTextStyles.title1.copyWith(
                                fontSize: 24,
                                color: IviaPharmacyColors.greenDeep,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Il prouve que le client a confirmé votre pharmacie.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: IviaTextStyles.body.copyWith(
                      color: IviaPharmacyColors.onGreenMuted,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
