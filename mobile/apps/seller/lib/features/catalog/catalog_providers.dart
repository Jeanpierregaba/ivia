import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/seller_shop.dart';

/// Taille d'une page du catalogue.
const catalogPageSize = 20;

/// Onglet ouvert du catalogue (En vente, Brouillons, Retirés).
final catalogTabProvider = NotifierProvider<CatalogTab, ProductStatus>(
  CatalogTab.new,
);

class CatalogTab extends Notifier<ProductStatus> {
  @override
  ProductStatus build() => ProductStatus.active;

  void select(ProductStatus status) => state = status;
}

/// Texte cherché, appliqué après le délai de frappe.
final catalogQueryProvider = NotifierProvider<CatalogQuery, String>(
  CatalogQuery.new,
);

class CatalogQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query.trim();
}

/// Produits chargés d'un onglet et d'une recherche.
class CatalogPage {
  const CatalogPage({
    required this.items,
    required this.nextOffset,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<Product> items;

  /// Décalage de la page suivante ; `null` : tout est chargé.
  final int? nextOffset;
  final bool loadingMore;
  final bool loadMoreFailed;

  CatalogPage copyWith({
    List<Product>? items,
    int? Function()? nextOffset,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) => CatalogPage(
    items: items ?? this.items,
    nextOffset: nextOffset == null ? this.nextOffset : nextOffset(),
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );
}

/// Identifiant de la boutique du marchand ; `null` : pas encore connue.
String? _shopId(Ref ref) =>
    ref.watch(sellerShopProvider.select((s) => s.value?.id));

/// Liste d'un onglet et d'une recherche, filtrée par le serveur, chargée
/// page par page.
final catalogListProvider = AsyncNotifierProvider.autoDispose
    .family<CatalogList, CatalogPage, (ProductStatus, String)>(
      CatalogList.new,
      // Pas de nouvel essai automatique : l'écran propose « Réessayer ».
      retry: (_, _) => null,
    );

class CatalogList extends AsyncNotifier<CatalogPage> {
  CatalogList(this.filter);

  final (ProductStatus, String) filter;

  @override
  Future<CatalogPage> build() async {
    final shopId = _shopId(ref);
    if (shopId == null) return const CatalogPage(items: [], nextOffset: null);
    final page = await ref
        .read(apiClientProvider)
        .sellerProducts(
          shopId,
          status: filter.$1,
          query: filter.$2,
          limit: catalogPageSize,
        );
    return CatalogPage(items: page.items, nextOffset: page.nextOffset);
  }

  /// Charge la page suivante (défilement en bas de liste).
  Future<void> loadMore() async {
    final current = state.value;
    final offset = current?.nextOffset;
    final shopId = ref.read(sellerShopProvider).value?.id;
    if (current == null ||
        offset == null ||
        current.loadingMore ||
        shopId == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(loadingMore: true, loadMoreFailed: false),
    );
    try {
      final page = await ref
          .read(apiClientProvider)
          .sellerProducts(
            shopId,
            status: filter.$1,
            query: filter.$2,
            offset: offset,
            limit: catalogPageSize,
          );
      if (!ref.mounted) return;
      state = AsyncData(
        CatalogPage(
          items: [...current.items, ...page.items],
          nextOffset: page.nextOffset,
        ),
      );
    } on Exception {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreFailed: true),
      );
    }
  }
}

/// Nombre de produits par état ; `null` : boutique pas encore connue.
final catalogCountsProvider = FutureProvider.autoDispose<ProductCounts?>((
  ref,
) async {
  final shopId = _shopId(ref);
  if (shopId == null) return null;
  return ref.read(apiClientProvider).productCounts(shopId);
}, retry: (_, _) => null);

/// Catégories de produits actives.
final productCategoriesProvider =
    FutureProvider.autoDispose<List<ProductCategory>>(
      (ref) => ref.read(apiClientProvider).productCategories(),
      retry: (_, _) => null,
    );

/// Recharge les listes et les compteurs après une modification. Prend le
/// conteneur : l'écran qui a modifié peut déjà être fermé (« Annuler » d'un
/// message).
void refreshCatalog(ProviderContainer container) {
  container
    ..invalidate(catalogListProvider)
    ..invalidate(catalogCountsProvider);
}

/// Corps complet d'une modification, repris du produit enregistré :
/// change seulement l'état (mise en vente, retrait).
ProductInput inputFrom(Product p, {required bool isActive}) => ProductInput(
  categoryId: p.categoryId,
  name: p.name,
  description: p.description,
  priceXof: p.priceXof,
  parcelSize: p.parcelSize,
  imageKeys: [for (final image in p.images) image.objectKey],
  isActive: isActive,
);
