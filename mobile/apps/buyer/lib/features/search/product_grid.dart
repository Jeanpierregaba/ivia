import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/cart.dart';
import '../../app/router.dart';
import '../cart/cart_actions.dart';

/// Une ou deux colonnes : une seule sur un écran étroit ou avec une police
/// agrandie.
int gridColumns(BuildContext context, double width) =>
    width < 340 || MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 1 : 2;

/// Produits trouvés en grille (sans défilement propre : dans une liste
/// courte, comme les nouveautés de l'accueil).
class ProductGrid extends StatelessWidget {
  const ProductGrid({super.key, required this.items});

  final List<ProductHit> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final columns = gridColumns(context, box.maxWidth);
        final rows = (items.length / columns).ceil();
        return Column(
          children: [
            for (var r = 0; r < rows; r++) ...[
              if (r > 0) const SizedBox(height: IviaSpacing.md),
              _gridRow(context, items, r, columns),
            ],
          ],
        );
      },
    );
  }
}

/// Grille paresseuse pour une longue liste de résultats : seules les
/// rangées visibles sont construites (pages successives de la recherche).
class ProductGridSliver extends StatelessWidget {
  const ProductGridSliver({super.key, required this.items});

  final List<ProductHit> items;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = gridColumns(
          context,
          constraints.crossAxisExtent - 2 * IviaSpacing.screen,
        );
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
          sliver: SliverList.separated(
            itemCount: (items.length / columns).ceil(),
            separatorBuilder: (_, _) => const SizedBox(height: IviaSpacing.md),
            itemBuilder: (context, r) => _gridRow(context, items, r, columns),
          ),
        );
      },
    );
  }
}

/// Rangée [row] de la grille : cartes de même hauteur.
Widget _gridRow(
  BuildContext context,
  List<ProductHit> items,
  int row,
  int columns,
) {
  final start = row * columns;
  return IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var c = 0; c < columns; c++) ...[
          if (c > 0) const SizedBox(width: IviaSpacing.md),
          Expanded(
            child: start + c < items.length
                ? ProductHitCard(
                    key: ValueKey(items[start + c].id),
                    hit: items[start + c],
                  )
                : const SizedBox(),
          ),
        ],
      ],
    ),
  );
}

/// Carte d'un produit trouvé : un appui ouvre sa fiche, « + » en ajoute un
/// exemplaire au panier (pas de « + » sur un produit épuisé).
class ProductHitCard extends ConsumerWidget {
  const ProductHitCard({super.key, required this.hit});

  final ProductHit hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adding = ref.watch(
      cartViewProvider.select((c) => c.value?.isSending(hit.id) ?? false),
    );
    return IviaProductCard(
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
      onAdd: hit.inStock
          ? () => addToCart(context, ref, productId: hit.id, name: hit.name)
          : null,
      adding: adding,
    );
  }
}
