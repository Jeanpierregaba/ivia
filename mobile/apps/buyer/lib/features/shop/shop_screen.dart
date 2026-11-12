import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/buyer_area.dart';
import '../../app/cart.dart';
import '../../app/router.dart';
import '../cart/cart_actions.dart';
import '../common/unavailable_view.dart';
import '../promo/promo_widgets.dart';
import '../cart/cart_button.dart';
import '../search/search_results.dart';
import '../search/search_screen.dart' show searchDelay;

/// Fiche publique d'une boutique.
final publicShopProvider = FutureProvider.autoDispose
    .family<PublicShop, String>(
      (ref, id) => ref.read(apiClientProvider).publicShop(id),
      retry: (_, _) => null,
    );

/// Fiche boutique : en-tête, recherche dans la boutique, produits en vente.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key, required this.shopId});

  final String shopId;

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  var _text = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onText(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      text.trim().isEmpty ? Duration.zero : searchDelay,
      () => setState(() => _text = text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(publicShopProvider(widget.shopId));
    final query = SearchQuery(shopId: widget.shopId, text: _text);
    return Scaffold(
      body: SafeArea(
        child: switch (shop) {
          AsyncData(:final value) => NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.depth == 0 && n.metrics.extentAfter < 400) {
                ref.read(productResultsProvider(query).notifier).loadMore();
              }
              return false;
            },
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(IviaSpacing.screen),
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          IviaBackButton(onPressed: () => context.pop()),
                          const Spacer(),
                          const CartButton(),
                        ],
                      ),
                      const SizedBox(height: IviaSpacing.lg),
                      _ShopHeader(shop: value),
                      const SizedBox(height: IviaSpacing.xl),
                      IviaSearchField(
                        controller: _search,
                        hint: 'Chercher dans la boutique',
                        maxLength: 100,
                        onChanged: _onText,
                      ),
                      const SizedBox(height: IviaSpacing.lg),
                    ],
                  ),
                ),
                const SliverToBoxAdapter(
                  child: PromoInlineBanner(
                    placement: PromoPlacement.catalogFeed,
                  ),
                ),
                ..._products(ref.watch(productResultsProvider(query)), query),
                const SliverToBoxAdapter(
                  child: SizedBox(height: IviaSpacing.xxxl),
                ),
              ],
            ),
          ),
          AsyncError(:final error) => UnavailableView(
            error: error,
            gone: 'Cette boutique n’est plus disponible.',
            onRetry: () => ref.invalidate(publicShopProvider(widget.shopId)),
          ),
          _ => const IviaPageSkeleton(),
        },
      ),
      bottomNavigationBar: shop.hasValue
          ? CartBar(shopId: widget.shopId)
          : null,
    );
  }

  List<Widget> _products(
    AsyncValue<Results<ProductHit>> results,
    SearchQuery query,
  ) {
    final page = results.value;
    Widget message(String text, {Widget? action}) => SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(IviaSpacing.xxl),
        child: Column(
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: IviaColors.textSecondary),
            ),
            ?action,
          ],
        ),
      ),
    );
    if (results.hasError && page == null) {
      final error = results.error;
      return [
        message(
          error is ApiException && !error.isNetwork
              ? error.message
              : 'Impossible de charger les produits. Vérifiez votre '
                    'connexion.',
          action: TextButton(
            onPressed: () => ref.invalidate(productResultsProvider(query)),
            child: const Text('Réessayer'),
          ),
        ),
      ];
    }
    if (page == null) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(IviaSpacing.screen),
            child: IviaGridSkeleton(),
          ),
        ),
      ];
    }
    if (page.items.isEmpty) {
      return [
        message(
          query.text.isEmpty
              ? 'Aucun produit en vente pour l’instant.'
              : 'Aucun produit ne correspond à « ${query.text} ».',
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        sliver: SliverList.builder(
          itemCount: page.items.length,
          itemBuilder: (context, i) => _ProductRow(
            hit: page.items[i],
            first: i == 0,
            last: i == page.items.length - 1,
          ),
        ),
      ),
      if (page.loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(IviaSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (page.loadMoreFailed)
        SliverToBoxAdapter(
          child: Center(
            child: TextButton(
              onPressed: () =>
                  ref.read(productResultsProvider(query).notifier).loadMore(),
              child: const Text('Afficher la suite'),
            ),
          ),
        ),
    ];
  }
}

class _ShopHeader extends ConsumerWidget {
  const _ShopHeader({required this.shop});

  final PublicShop shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final point = ref.watch(buyerAreaProvider).point;
    final address = [
      shop.addressText,
      shop.neighborhoodName,
    ].where((s) => s.isNotEmpty).join(', ');
    return Container(
      padding: const EdgeInsets.all(IviaSpacing.lg),
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 64,
                child: IviaNetworkImage(url: shop.logoUrl),
              ),
              const SizedBox(width: IviaSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(shop.name, style: textTheme.headlineSmall),
                    ),
                    if (address.isNotEmpty)
                      Text(address, style: textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: IviaSpacing.md),
          Wrap(
            spacing: IviaSpacing.sm,
            runSpacing: IviaSpacing.sm,
            children: [
              IviaStatusPill(
                label: shop.acceptingOrders
                    ? 'Ouverte'
                    : 'Commandes suspendues',
                tone: shop.acceptingOrders
                    ? IviaPillTone.info
                    : IviaPillTone.neutral,
              ),
              if (point != null)
                IviaStatusPill(
                  label: formatDistance(distanceMeters(point, shop.location)),
                  tone: IviaPillTone.neutral,
                ),
            ],
          ),
          if (shop.description.isNotEmpty) ...[
            const SizedBox(height: IviaSpacing.md),
            Text(shop.description, style: textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Produit de la boutique : un appui ouvre sa fiche, « + » en ajoute un
/// exemplaire au panier (chevron sur un produit épuisé).
class _ProductRow extends ConsumerWidget {
  const _ProductRow({
    required this.hit,
    required this.first,
    required this.last,
  });

  final ProductHit hit;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    const corner = Radius.circular(IviaRadius.large);
    final radius = BorderRadius.vertical(
      top: first ? corner : Radius.zero,
      bottom: last ? corner : Radius.zero,
    );
    final price = formatXof(hit.priceXof);
    final adding = ref.watch(
      cartViewProvider.select((c) => c.value?.isSending(hit.id) ?? false),
    );
    return Material(
      color: IviaColors.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: IviaColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label:
                    '${hit.name}, $price, ${hit.inStock ? 'en stock' : 'épuisé'}',
                excludeSemantics: true,
                onTap: () => context.push(Routes.product(hit.id)),
                child: InkWell(
                  onTap: () => context.push(Routes.product(hit.id)),
                  child: Padding(
                    padding: const EdgeInsets.all(IviaSpacing.md),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 64,
                          child: IviaNetworkImage(url: hit.imageUrl),
                        ),
                        const SizedBox(width: IviaSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hit.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                hit.inStock ? 'En stock' : 'Épuisé',
                                style: textTheme.bodySmall?.copyWith(
                                  color: hit.inStock
                                      ? IviaColors.cobaltBlue
                                      : IviaColors.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                price,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: IviaSpacing.sm),
              child: hit.inStock
                  ? IviaAddButton(
                      label: 'Ajouter ${hit.name} au panier',
                      busy: adding,
                      onPressed: () => addToCart(
                        context,
                        ref,
                        productId: hit.id,
                        name: hit.name,
                      ),
                    )
                  : const ExcludeSemantics(
                      child: Icon(
                        Icons.chevron_right,
                        color: IviaColors.textSecondary,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
