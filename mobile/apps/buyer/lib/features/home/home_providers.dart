import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/buyer_area.dart';

/// Rayon des sections de l'accueil avec la position du téléphone.
const homeRadiusM = 5000;

/// Requête des sections de l'accueil pour la zone de l'acheteur.
SearchQuery homeQuery(BuyerArea area) => area.apply(
  SearchQuery(
    radiusM: area.point == null ? null : homeRadiusM,
    sort: area.point == null ? SearchSort.relevance : SearchSort.distance,
  ),
);

/// « Boutiques autour de vous » : les plus proches d'abord.
final homeShopsProvider = FutureProvider.autoDispose<List<ShopHit>>((
  ref,
) async {
  final area = ref.watch(buyerAreaProvider);
  final page = await ref
      .read(apiClientProvider)
      .searchShops(homeQuery(area), limit: 10);
  return page.items;
}, retry: (_, _) => null);

/// « Nouveautés autour de vous » : produits récents de la zone.
final homeProductsProvider = FutureProvider.autoDispose<List<ProductHit>>((
  ref,
) async {
  final area = ref.watch(buyerAreaProvider);
  final query = homeQuery(area).copyWith(sort: SearchSort.relevance);
  final page = await ref
      .read(apiClientProvider)
      .searchProducts(query, limit: 10);
  return page.items;
}, retry: (_, _) => null);
