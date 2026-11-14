import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

import '../../app/account.dart';
import '../../app/buyer_area.dart';

/// Onglet des résultats.
enum SearchTab { products, shops }

/// Rayons proposés pour « Autour de moi », en kilomètres.
const searchRadii = [1, 2, 5, 10];

/// Rayon par défaut, commun à l'accueil et à la recherche (« Voir tout »
/// montre les mêmes boutiques que la section).
const defaultRadiusKm = 5;

/// Filtres de l'onglet Recherche ; l'accueil les remplit avant d'y aller.
class SearchFilters {
  const SearchFilters({
    this.text = '',
    this.tab = SearchTab.products,
    this.radiusKm = defaultRadiusKm,
    this.categoryId,
    this.minPrice,
    this.maxPrice,
    this.inStockOnly = false,
    this.sort = SearchSort.relevance,
    this.session = 0,
  });

  /// Numéro de la recherche lancée depuis l'accueil : l'écran de recherche
  /// abandonne la frappe en attente quand il change.
  final int session;

  final String text;
  final SearchTab tab;

  /// Rayon autour de la position du téléphone ; `null` : sans limite.
  final int? radiusKm;
  final String? categoryId;
  final int? minPrice;
  final int? maxPrice;
  final bool inStockOnly;
  final SearchSort sort;

  /// Filtres visibles posés en plus du texte et de la zone, pour l'onglet
  /// ouvert (« Effacer les filtres »).
  bool hasFiltersFor(BuyerArea area) {
    final effectiveSort = toQuery(area).sort;
    if (tab == SearchTab.shops) return effectiveSort != SearchSort.relevance;
    return categoryId != null ||
        minPrice != null ||
        maxPrice != null ||
        inStockOnly ||
        effectiveSort != SearchSort.relevance;
  }

  /// Requête envoyée au serveur pour [area] et l'onglet ouvert : rayon et
  /// tri par distance seulement avec la position du téléphone ; pour les
  /// boutiques, ni catégorie, ni prix, ni stock, ni tri par prix (clé de
  /// liste stable quand ces filtres changent sur l'autre onglet).
  SearchQuery toQuery(BuyerArea area) {
    final hasPoint = area.point != null;
    final km = radiusKm;
    final products = tab == SearchTab.products;
    final effectiveSort = switch (sort) {
      SearchSort.distance when !hasPoint => SearchSort.relevance,
      SearchSort.priceAsc ||
      SearchSort.priceDesc when !products => SearchSort.relevance,
      _ => sort,
    };
    return area.apply(
      SearchQuery(
        text: text,
        categoryId: products ? categoryId : null,
        minPrice: products ? minPrice : null,
        maxPrice: products ? maxPrice : null,
        inStockOnly: products && inStockOnly,
        sort: effectiveSort,
        radiusM: hasPoint && km != null ? km * 1000 : null,
      ),
    );
  }

  SearchFilters copyWith({
    String? text,
    SearchTab? tab,
    int? Function()? radiusKm,
    String? Function()? categoryId,
    int? Function()? minPrice,
    int? Function()? maxPrice,
    bool? inStockOnly,
    SearchSort? sort,
  }) => SearchFilters(
    text: text ?? this.text,
    tab: tab ?? this.tab,
    radiusKm: radiusKm == null ? this.radiusKm : radiusKm(),
    categoryId: categoryId == null ? this.categoryId : categoryId(),
    minPrice: minPrice == null ? this.minPrice : minPrice(),
    maxPrice: maxPrice == null ? this.maxPrice : maxPrice(),
    inStockOnly: inStockOnly ?? this.inStockOnly,
    sort: sort ?? this.sort,
    session: session,
  );
}

final searchFiltersProvider =
    NotifierProvider<SearchFiltersState, SearchFilters>(SearchFiltersState.new);

class SearchFiltersState extends Notifier<SearchFilters> {
  @override
  SearchFilters build() {
    // Filtres et focus repartent de zéro au changement de compte.
    ref.watch(accountIdProvider);
    return const SearchFilters();
  }

  void update(SearchFilters Function(SearchFilters) change) =>
      state = change(state);

  /// Depuis l'accueil : nouvelle recherche, filtres remis à zéro (rayon
  /// gardé), éventuellement dans une catégorie, sur un onglet ou triée.
  void startFromHome({
    String? categoryId,
    SearchTab tab = SearchTab.products,
    SearchSort sort = SearchSort.relevance,
  }) => state = SearchFilters(
    radiusKm: state.radiusKm,
    categoryId: categoryId,
    tab: tab,
    sort: sort,
    session: state.session + 1,
  );

  /// Garde la zone et le texte, retire les autres filtres.
  void clearFilters() => state = SearchFilters(
    text: state.text,
    tab: state.tab,
    radiusKm: state.radiusKm,
    session: state.session,
  );
}

/// Incrémenté pour donner le focus au champ de recherche (appui sur le champ
/// de l'accueil).
final searchFocusRequestProvider = NotifierProvider<SearchFocusRequest, int>(
  SearchFocusRequest.new,
);

class SearchFocusRequest extends Notifier<int> {
  @override
  int build() {
    // Filtres et focus repartent de zéro au changement de compte.
    ref.watch(accountIdProvider);
    return 0;
  }

  void request() => state++;
}
