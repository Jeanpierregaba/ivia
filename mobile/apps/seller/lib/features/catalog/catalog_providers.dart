import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/seller_shop.dart';

/// Taille d'une page du catalogue.
const catalogPageSize = 20;

/// Compte connecté : l'onglet et la recherche repartent de zéro quand il
/// change (déconnexion, autre marchand).
String? _accountId(Ref ref) => ref.watch(
  authControllerProvider.select(
    (auth) => switch (auth) {
      AuthSignedIn(:final user) || AuthNeedsProfile(:final user) => user.id,
      _ => null,
    },
  ),
);

/// Onglet ouvert du catalogue (En vente, Brouillons, Retirés).
final catalogTabProvider = NotifierProvider<CatalogTab, ProductStatus>(
  CatalogTab.new,
);

class CatalogTab extends Notifier<ProductStatus> {
  @override
  ProductStatus build() {
    _accountId(ref);
    return ProductStatus.active;
  }

  void select(ProductStatus status) => state = status;
}

/// Texte cherché, appliqué après le délai de frappe.
final catalogQueryProvider = NotifierProvider<CatalogQuery, String>(
  CatalogQuery.new,
);

class CatalogQuery extends Notifier<String> {
  @override
  String build() {
    _accountId(ref);
    return '';
  }

  void set(String query) => state = query.trim();
}

/// Catégorie filtrée (elle ou ses sous-catégories) ; `null` : toutes.
final catalogCategoryProvider = NotifierProvider<CatalogCategory, String?>(
  CatalogCategory.new,
);

class CatalogCategory extends Notifier<String?> {
  @override
  String? build() {
    _accountId(ref);
    return null;
  }

  void select(String? id) => state = id;
}

/// Affichage du catalogue : liste (par défaut) ou grille de vignettes.
final catalogGridProvider = NotifierProvider<CatalogGrid, bool>(
  CatalogGrid.new,
);

class CatalogGrid extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

/// Filtre d'une liste : état, texte cherché, catégorie.
typedef CatalogFilter = (ProductStatus, String, String?);

/// Filtre affiché : onglet, recherche et catégorie choisis.
CatalogFilter watchCatalogFilter(WidgetRef ref) => (
  ref.watch(catalogTabProvider),
  ref.watch(catalogQueryProvider),
  ref.watch(catalogCategoryProvider),
);

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
    .family<CatalogList, CatalogPage, CatalogFilter>(
      CatalogList.new,
      // Pas de nouvel essai automatique : l'écran propose « Réessayer ».
      retry: (_, _) => null,
    );

class CatalogList extends AsyncNotifier<CatalogPage> {
  CatalogList(this.filter);

  final CatalogFilter filter;

  /// Incrémenté à chaque (re)chargement : une page de suite demandée avant
  /// un rechargement est ignorée (Riverpod garde la même instance du
  /// notifier, `ref.mounted` ne le signale pas).
  var _generation = 0;

  @override
  Future<CatalogPage> build() async {
    _generation++;
    final shopId = _shopId(ref);
    if (shopId == null) return const CatalogPage(items: [], nextOffset: null);
    final page = await ref
        .read(apiClientProvider)
        .sellerProducts(
          shopId,
          status: filter.$1,
          query: filter.$2,
          categoryId: filter.$3,
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
        state.isLoading ||
        shopId == null) {
      return;
    }
    final generation = _generation;
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
            categoryId: filter.$3,
            offset: offset,
            limit: catalogPageSize,
          );
      if (!ref.mounted || generation != _generation) return;
      // Sans doublon si un produit a glissé d'une page à l'autre.
      final known = {for (final p in current.items) p.id};
      state = AsyncData(
        CatalogPage(
          items: [
            ...current.items,
            ...page.items.where((p) => !known.contains(p.id)),
          ],
          nextOffset: page.nextOffset,
        ),
      );
    } on Exception {
      if (!ref.mounted || generation != _generation) return;
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

/// Bibliothèque de photos de la boutique (spec : refonte Ivia Business).
final shopMediaProvider = FutureProvider.autoDispose<List<ProductImage>>((
  ref,
) async {
  final shopId = _shopId(ref);
  if (shopId == null) return const [];
  return ref.read(apiClientProvider).shopMedia(shopId);
}, retry: (_, _) => null);

/// Recharge les listes et les compteurs après une modification. Prend le
/// conteneur : l'écran qui a modifié peut déjà être fermé (« Annuler » d'un
/// message).
void refreshCatalog(ProviderContainer container) {
  container
    ..invalidate(catalogListProvider)
    ..invalidate(catalogCountsProvider)
    ..invalidate(shopMediaProvider);
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

/// Produits en vente dont le stock suivi est bas (3 ou moins) : tuile
/// « Stock bas » de l'Accueil. `null` : boutique pas encore connue.
final lowStockProvider = FutureProvider.autoDispose<List<Product>?>((
  ref,
) async {
  final shopId = _shopId(ref);
  if (shopId == null) return null;
  final page = await ref
      .read(apiClientProvider)
      .sellerProducts(shopId, status: ProductStatus.active, limit: 100);
  return [
    for (final p in page.items)
      if (p.stockMode == StockMode.tracked && (p.stockQuantity ?? 0) <= 3) p,
  ];
}, retry: (_, _) => null);
