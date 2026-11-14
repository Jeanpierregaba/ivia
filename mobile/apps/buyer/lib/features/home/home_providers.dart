import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/buyer_area.dart';
import '../search/search_state.dart';

/// Requête des sections de l'accueil : même rayon que l'onglet Recherche,
/// pour que « Voir tout » montre les mêmes résultats.
SearchQuery homeQuery(BuyerArea area, int? radiusKm) => area.apply(
  SearchQuery(
    radiusM: area.point == null || radiusKm == null ? null : radiusKm * 1000,
    sort: area.point == null ? SearchSort.relevance : SearchSort.distance,
  ),
);

int? _radius(Ref ref) =>
    ref.watch(searchFiltersProvider.select((f) => f.radiusKm));

/// « Boutiques autour de vous » : les plus proches d'abord.
final homeShopsProvider = FutureProvider.autoDispose<List<ShopHit>>((
  ref,
) async {
  final area = ref.watch(buyerAreaProvider);
  final page = await ref
      .read(apiClientProvider)
      .searchShops(homeQuery(area, _radius(ref)), limit: 10);
  return page.items;
}, retry: (_, _) => null);

/// « Nouveautés autour de vous » : produits récents de la zone.
final homeProductsProvider = FutureProvider.autoDispose<List<ProductHit>>((
  ref,
) async {
  final area = ref.watch(buyerAreaProvider);
  final query = homeQuery(
    area,
    _radius(ref),
  ).copyWith(sort: SearchSort.relevance);
  final page = await ref
      .read(apiClientProvider)
      .searchProducts(query, limit: 10);
  return page.items;
}, retry: (_, _) => null);
