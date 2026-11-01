import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';

/// Une ou deux colonnes : une seule sur un écran étroit ou avec une police
/// agrandie.
int gridColumns(BuildContext context, double width) =>
    width < 340 || MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 1 : 2;

/// Produits trouvés en grille (sans défilement propre : dans une liste).
class ProductGrid extends StatelessWidget {
  const ProductGrid({super.key, required this.items});

  final List<ProductHit> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final columns = gridColumns(context, box.maxWidth);
        final rows = <List<ProductHit>>[
          for (var i = 0; i < items.length; i += columns)
            items.sublist(i, (i + columns).clamp(0, items.length)),
        ];
        return Column(
          children: [
            for (final (r, row) in rows.indexed) ...[
              if (r > 0) const SizedBox(height: IviaSpacing.md),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) const SizedBox(width: IviaSpacing.md),
                      Expanded(
                        child: c < row.length
                            ? productCard(context, row[c])
                            : const SizedBox(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Carte d'un produit trouvé ; un appui ouvre sa fiche.
Widget productCard(BuildContext context, ProductHit hit) => IviaProductCard(
  key: ValueKey(hit.id),
  imageUrl: hit.imageUrl,
  name: hit.name,
  shopName: hit.shopName,
  distance: switch (hit.distanceM) {
    final m? => formatDistance(m),
    null => null,
  },
  price: formatXof(hit.priceXof),
  soldOut: !hit.inStock,
  onTap: () => context.push(Routes.product(hit.id)),
);
