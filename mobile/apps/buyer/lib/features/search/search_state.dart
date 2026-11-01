import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

import '../../app/buyer_area.dart';

/// Onglet des résultats.
enum SearchTab { products, shops }

/// Rayons proposés pour « Autour de moi », en kilomètres.
const searchRadii = [1, 2, 5, 10];

/// Filtres de l'onglet Recherche ; l'accueil les remplit avant d'y aller.
class SearchFilters {
  const SearchFilters({
    this.text = '',
    this.tab = SearchTab.products,
    this.radiusKm = 2,
    this.categoryId,
    this.minPrice,
    this.maxPrice,
    this.inStockOnly = false,
    this.sort = SearchSort.relevance,
  });

  final String text;
  final SearchTab tab;

  /// Rayon autour de la position du téléphone ; `null` : sans limite.
  final int? radiusKm;
  final String? categoryId;
  final int? minPrice;
  final int? maxPrice;
  final bool inStockOnly;
  final SearchSort sort;

  /// Filtres posés en plus du texte et de la zone (« Effacer les filtres »).
  bool get hasFilters =>
      categoryId != null ||
      minPrice != null ||
      maxPrice != null ||
      inStockOnly ||
      sort != SearchSort.relevance;

  /// Requête envoyée au serveur pour [area] : rayon et tri par distance
  /// seulement avec la position du téléphone.
  SearchQuery toQuery(BuyerArea area) {
    final hasPoint = area.point != null;
    final km = radiusKm;
    return area.apply(
      SearchQuery(
        text: text,
        categoryId: categoryId,
        minPrice: minPrice,
        maxPrice: maxPrice,
        inStockOnly: inStockOnly,
        sort: !hasPoint && sort == SearchSort.distance
            ? SearchSort.relevance
            : sort,
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
  );
}

final searchFiltersProvider =
    NotifierProvider<SearchFiltersState, SearchFilters>(SearchFiltersState.new);

class SearchFiltersState extends Notifier<SearchFilters> {
  @override
  SearchFilters build() => const SearchFilters();

  void update(SearchFilters Function(SearchFilters) change) =>
      state = change(state);

  /// Depuis l'accueil : nouvelle recherche, filtres remis à zéro (rayon
  /// gardé), éventuellement dans une catégorie ou sur un onglet.
  void startFromHome({
    String? categoryId,
    SearchTab tab = SearchTab.products,
  }) => state = SearchFilters(
    radiusKm: state.radiusKm,
    categoryId: categoryId,
    tab: tab,
  );

  /// Garde la zone et le texte, retire les autres filtres.
  void clearFilters() => state = SearchFilters(
    text: state.text,
    tab: state.tab,
    radiusKm: state.radiusKm,
  );
}

/// Incrémenté pour donner le focus au champ de recherche (appui sur le champ
/// de l'accueil).
final searchFocusRequestProvider = NotifierProvider<SearchFocusRequest, int>(
  SearchFocusRequest.new,
);

class SearchFocusRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}
