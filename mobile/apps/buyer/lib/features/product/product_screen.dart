import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/buyer_area.dart';
import '../../app/catalog_data.dart';
import '../../app/cart.dart';
import '../../app/router.dart';
import '../cart/cart_actions.dart';
import '../cart/cart_button.dart' show CartButton;
import '../common/unavailable_view.dart';

/// Fiche publique d'un produit, avec sa boutique.
final publicProductProvider = FutureProvider.autoDispose
    .family<(Product, PublicShop), String>(
      (ref, id) => ref.read(apiClientProvider).publicProduct(id),
      retry: (_, _) => null,
    );

/// Disponibilité vue par l'acheteur.
String availabilityLabel(Product p) => switch (p.stockMode) {
  StockMode.untracked => 'Disponible',
  StockMode.tracked when (p.stockQuantity ?? 0) > 0 =>
    'En stock · ${p.stockQuantity} disponible${p.stockQuantity == 1 ? '' : 's'}',
  StockMode.tracked => 'Épuisé',
};

/// Fiche produit : photos, prix, disponibilité, boutique, description,
/// quantité et ajout au panier.
class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  var _quantity = 1;
  var _adding = false;

  Future<void> _add(Product product, int quantity) async {
    setState(() => _adding = true);
    var added = false;
    try {
      added = await addToCart(
        context,
        ref,
        productId: product.id,
        name: product.name,
        count: quantity,
      );
    } finally {
      if (mounted) {
        setState(() {
          _adding = false;
          if (added) _quantity = 1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(publicProductProvider(widget.productId));
    return Scaffold(
      body: switch (data) {
        AsyncData(value: (final product, final shop)) => _content(
          product,
          shop,
        ),
        AsyncError(:final error) => SafeArea(
          child: UnavailableView(
            error: error,
            gone: 'Ce produit n’est plus disponible.',
            onRetry: () =>
                ref.invalidate(publicProductProvider(widget.productId)),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: switch (data) {
        AsyncData(value: (final product, _)) => _bottomBar(product),
        _ => null,
      },
    );
  }

  Widget _content(Product product, PublicShop shop) {
    final textTheme = Theme.of(context).textTheme;
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final category = categoryName(categories, product.categoryId);
    final soldOut = !product.available;
    final inCart = ref.watch(
      cartViewProvider.select((c) => c.value?.cart.quantityOf(product.id) ?? 0),
    );
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.38,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IviaPhotoCarousel(
                    urls: [for (final image in product.images) image.url],
                  ),
                ),
                Positioned(
                  left: IviaSpacing.screen,
                  top: MediaQuery.paddingOf(context).top + IviaSpacing.sm,
                  child: IviaBackButton(onPressed: () => context.pop()),
                ),
                Positioned(
                  right: IviaSpacing.screen,
                  top: MediaQuery.paddingOf(context).top + IviaSpacing.sm,
                  child: const CartButton(),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          sliver: SliverList.list(
            children: [
              if (product.badges.isNotEmpty) ...[
                Wrap(
                  spacing: IviaSpacing.xs,
                  runSpacing: IviaSpacing.xs,
                  children: [
                    for (final b in product.badges)
                      IviaPromoBadge(label: b.label),
                  ],
                ),
                const SizedBox(height: IviaSpacing.sm),
              ],
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: IviaSpacing.md,
                children: [
                  Semantics(
                    header: true,
                    child: Text(product.name, style: textTheme.headlineSmall),
                  ),
                  Wrap(
                    spacing: IviaSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(
                        formatXof(product.effectivePriceXof),
                        style: textTheme.headlineSmall?.copyWith(
                          color: product.promoActive
                              ? IviaColors.primary
                              : null,
                        ),
                      ),
                      if (product.promoActive)
                        Text(
                          formatXof(product.priceXof),
                          semanticsLabel:
                              'au lieu de ${formatXof(product.priceXof)}',
                          style: textTheme.bodyLarge?.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: IviaColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: IviaSpacing.xs),
              Text(
                availabilityLabel(product),
                style: textTheme.titleSmall?.copyWith(
                  color: soldOut ? IviaColors.error : IviaColors.cobaltBlue,
                ),
              ),
              if (inCart > 0)
                Text(
                  'Déjà $inCart dans votre panier',
                  style: textTheme.bodyMedium,
                ),
              if (product.features.isNotEmpty) ...[
                const SizedBox(height: IviaSpacing.md),
                for (final f in product.features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: IviaSpacing.xs),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 18,
                          color: IviaColors.success,
                        ),
                        const SizedBox(width: IviaSpacing.sm),
                        Expanded(child: Text(f, style: textTheme.bodyMedium)),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: IviaSpacing.lg),
              _ShopCard(shop: shop),
              if (product.description.isNotEmpty) ...[
                const SizedBox(height: IviaSpacing.lg),
                Text(
                  product.description,
                  style: textTheme.bodyLarge?.copyWith(
                    color: IviaColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: IviaSpacing.lg),
              Wrap(
                spacing: IviaSpacing.sm,
                runSpacing: IviaSpacing.sm,
                children: [
                  if (category != null)
                    IviaStatusPill(label: category, tone: IviaPillTone.neutral),
                  IviaStatusPill(
                    label: parcelLabel(product.parcelSize),
                    tone: IviaPillTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: IviaSpacing.xxl),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(Product product) {
    final soldOut = !product.available;
    // Ce qui reste à ajouter : stock (ou 99) moins ce qui est déjà au panier.
    final inCart = ref.watch(
      cartViewProvider.select((c) => c.value?.cart.quantityOf(product.id) ?? 0),
    );
    final cap = product.stockMode == StockMode.tracked
        ? (product.stockQuantity ?? 0).clamp(0, cartMaxQuantity)
        : cartMaxQuantity;
    // Tout le stock (ou 99) déjà au panier : rien à ajouter.
    final full = !soldOut && cap - inCart <= 0;
    final max = (cap - inCart).clamp(1, cartMaxQuantity);
    final quantity = _quantity.clamp(1, max);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        IviaSpacing.screen,
        IviaSpacing.sm,
        IviaSpacing.screen,
        IviaSpacing.screen,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: IviaSpacing.md,
        runSpacing: IviaSpacing.sm,
        children: [
          if (!soldOut && !full)
            IviaQuantityStepper(
              label: 'Quantité',
              value: quantity,
              min: 1,
              max: max,
              onChanged: (v) => setState(() => _quantity = v),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: FilledButton(
              onPressed: soldOut || full || _adding
                  ? null
                  : () => _add(product, quantity),
              child: Text(switch (()) {
                _ when soldOut => 'Épuisé',
                _ when full && cap < cartMaxQuantity =>
                  'Tout le stock est au panier',
                _ when full => '$cartMaxQuantity au plus : déjà au panier',
                _ =>
                  'Ajouter · ${formatXof(product.effectivePriceXof * quantity)}',
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Boutique du produit : ouvre sa fiche.
class _ShopCard extends ConsumerWidget {
  const _ShopCard({required this.shop});

  final PublicShop shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final point = ref.watch(buyerAreaProvider).point;
    final line = [
      if (shop.neighborhoodName.isNotEmpty) shop.neighborhoodName,
      if (point != null) formatDistance(distanceMeters(point, shop.location)),
      shop.acceptingOrders ? 'Ouverte' : 'Commandes suspendues',
    ].join(' · ');
    return Semantics(
      button: true,
      label: 'Boutique ${shop.name}, $line',
      excludeSemantics: true,
      onTap: () => context.push(Routes.shop(shop.id)),
      child: Material(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
        child: InkWell(
          borderRadius: BorderRadius.circular(IviaRadius.large),
          onTap: () => context.push(Routes.shop(shop.id)),
          child: Padding(
            padding: const EdgeInsets.all(IviaSpacing.md),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 56,
                  child: IviaNetworkImage(url: shop.logoUrl),
                ),
                const SizedBox(width: IviaSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(line, style: textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: IviaColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
