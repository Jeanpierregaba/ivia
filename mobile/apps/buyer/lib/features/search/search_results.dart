import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

/// Taille d'une page de résultats.
const resultsPageSize = 20;

/// Résultats chargés d'une recherche.
class Results<T> {
  const Results({
    required this.items,
    required this.nextOffset,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<T> items;

  /// Décalage de la page suivante ; `null` : tout est chargé.
  final int? nextOffset;
  final bool loadingMore;
  final bool loadMoreFailed;
}

/// Résultats d'une requête, chargés page par page.
abstract class PagedResults<T> extends AsyncNotifier<Results<T>> {
  PagedResults(this.query);

  final SearchQuery query;

  /// Incrémenté à chaque (re)chargement : une page de suite demandée avant
  /// est ignorée (même instance du notifier, `ref.mounted` ne le dit pas).
  var _generation = 0;

  Future<Page<T>> fetch(IviaApiClient client, int offset);

  String idOf(T item);

  @override
  Future<Results<T>> build() async {
    _generation++;
    final page = await fetch(ref.read(apiClientProvider), 0);
    return Results(items: page.items, nextOffset: page.nextOffset);
  }

  /// Page suivante (défilement en bas de liste).
  Future<void> loadMore() async {
    final current = state.value;
    final offset = current?.nextOffset;
    if (current == null ||
        offset == null ||
        current.loadingMore ||
        state.isLoading) {
      return;
    }
    final generation = _generation;
    state = AsyncData(
      Results(
        items: current.items,
        nextOffset: current.nextOffset,
        loadingMore: true,
      ),
    );
    try {
      final page = await fetch(ref.read(apiClientProvider), offset);
      if (!ref.mounted || generation != _generation) return;
      final known = {for (final item in current.items) idOf(item)};
      state = AsyncData(
        Results(
          items: [
            ...current.items,
            ...page.items.where((item) => !known.contains(idOf(item))),
          ],
          nextOffset: page.nextOffset,
        ),
      );
    } on Exception {
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        Results(
          items: current.items,
          nextOffset: current.nextOffset,
          loadMoreFailed: true,
        ),
      );
    }
  }
}

final productResultsProvider = AsyncNotifierProvider.autoDispose
    .family<ProductResults, Results<ProductHit>, SearchQuery>(
      ProductResults.new,
      // Pas de nouvel essai automatique : l'écran propose « Réessayer ».
      retry: (_, _) => null,
    );

class ProductResults extends PagedResults<ProductHit> {
  ProductResults(super.query);

  @override
  Future<Page<ProductHit>> fetch(IviaApiClient client, int offset) =>
      client.searchProducts(query, offset: offset, limit: resultsPageSize);

  @override
  String idOf(ProductHit item) => item.id;
}

final shopResultsProvider = AsyncNotifierProvider.autoDispose
    .family<ShopResults, Results<ShopHit>, SearchQuery>(
      ShopResults.new,
      retry: (_, _) => null,
    );

class ShopResults extends PagedResults<ShopHit> {
  ShopResults(super.query);

  @override
  Future<Page<ShopHit>> fetch(IviaApiClient client, int offset) =>
      client.searchShops(query, offset: offset, limit: resultsPageSize);

  @override
  String idOf(ShopHit item) => item.id;
}
