import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/account.dart';

/// Taille d'une page de commandes : les commandes en cours sont récentes,
/// elles tiennent dans la première page.
const ordersPageSize = 50;

/// Commandes chargées d'un compte, les plus récentes d'abord.
class OrdersState {
  const OrdersState({
    required this.account,
    required this.items,
    required this.nextOffset,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final String? account;
  final List<BuyerOrder> items;
  final int? nextOffset;
  final bool loadingMore;
  final bool loadMoreFailed;

  List<BuyerOrder> get active => [
    for (final o in items)
      if (o.status.isActive) o,
  ];

  List<BuyerOrder> get finished => [
    for (final o in items)
      if (!o.status.isActive) o,
  ];

  OrdersState copyWith({
    List<BuyerOrder>? items,
    int? Function()? nextOffset,
    bool loadingMore = false,
    bool loadMoreFailed = false,
  }) => OrdersState(
    account: account,
    items: items ?? this.items,
    nextOffset: nextOffset == null ? this.nextOffset : nextOffset(),
    loadingMore: loadingMore,
    loadMoreFailed: loadMoreFailed,
  );
}

/// Commandes du compte connecté, relues au changement de compte.
final myOrdersProvider = AsyncNotifierProvider<MyOrders, OrdersState>(
  MyOrders.new,
  // Pas de nouvel essai automatique : l'écran propose « Réessayer ».
  retry: (_, _) => null,
);

/// Commandes à afficher : celles du compte connecté seulement (pendant la
/// relecture qui suit un changement de compte, les anciennes ne sont
/// jamais montrées).
final myOrdersViewProvider = Provider<AsyncValue<OrdersState>>((ref) {
  final account = ref.watch(accountIdProvider);
  final orders = ref.watch(myOrdersProvider);
  if (orders.value case final value? when value.account != account) {
    return orders.hasError && !orders.isLoading
        ? AsyncError(orders.error!, orders.stackTrace ?? StackTrace.current)
        : const AsyncLoading();
  }
  return orders;
});

class MyOrders extends AsyncNotifier<OrdersState> {
  IviaApiClient get _client => ref.read(apiClientProvider);

  /// Change à chaque relecture : une suite demandée avant est ignorée.
  var _generation = 0;
  String? _account;

  @override
  Future<OrdersState> build() async {
    final account = _account = ref.watch(accountIdProvider);
    _generation++;
    if (account == null) {
      return const OrdersState(account: null, items: [], nextOffset: null);
    }
    final page = await _client.myOrders(limit: ordersPageSize);
    return OrdersState(
      account: account,
      items: page.items,
      nextOffset: page.nextOffset,
    );
  }

  /// Relit la première page ; un échec garde la liste affichée (et lève
  /// l'erreur). La génération ne change qu'au succès : une suite en cours
  /// est alors ignorée (la liste relue la remplace) ; sinon elle aboutit.
  Future<void> refresh() async {
    final generation = _generation;
    final page = await _client.myOrders(limit: ordersPageSize);
    if (!ref.mounted || generation != _generation) return;
    _generation++;
    state = AsyncData(
      OrdersState(
        account: _account,
        items: page.items,
        nextOffset: page.nextOffset,
      ),
    );
  }

  /// Page suivante (commandes terminées plus anciennes).
  Future<void> loadMore() async {
    final current = state.value;
    final offset = current?.nextOffset;
    if (current == null || offset == null || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await _client.myOrders(
        offset: offset,
        limit: ordersPageSize,
      );
      if (!ref.mounted || generation != _generation) return;
      final known = {for (final o in current.items) o.id};
      state = AsyncData(
        current.copyWith(
          items: [
            ...current.items,
            ...page.items.where((o) => !known.contains(o.id)),
          ],
          nextOffset: () => page.nextOffset,
        ),
      );
    } on Exception {
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(current.copyWith(loadMoreFailed: true));
    }
  }

  /// Commande relue ou créée ailleurs (suivi, commande) : la liste suit.
  void put(BuyerOrder order) {
    final current = state.value;
    if (current == null || current.account != _account) return;
    final i = current.items.indexWhere((o) => o.id == order.id);
    // Version plus ancienne que celle de la liste : ignorée.
    if (i >= 0 && order.updatedAt.isBefore(current.items[i].updatedAt)) return;
    state = AsyncData(
      current.copyWith(
        items: i < 0 ? [order, ...current.items] : [...current.items]
          ..[i] = order,
      ),
    );
  }
}

/// Suivi d'une commande ; chaque lecture met aussi la liste à jour.
final orderProvider = AsyncNotifierProvider.autoDispose
    .family<OrderController, BuyerOrder, String>(
      OrderController.new,
      retry: (_, _) => null,
    );

class OrderController extends AsyncNotifier<BuyerOrder> {
  OrderController(this.id);

  final String id;

  IviaApiClient get _client => ref.read(apiClientProvider);

  @override
  Future<BuyerOrder> build() async {
    ref.watch(accountIdProvider);
    final order = await _client.myOrder(id);
    // Hors de la construction : un provider n'en modifie pas un autre
    // pendant qu'il se construit.
    scheduleMicrotask(() {
      if (ref.mounted) _share(order);
    });
    return order;
  }

  /// La liste, si elle est chargée, suit la commande relue.
  void _share(BuyerOrder order) {
    if (ref.exists(myOrdersProvider)) {
      ref.read(myOrdersProvider.notifier).put(order);
    }
  }

  /// Relecture en cours, partagée : jamais deux à la fois (relecture
  /// régulière et « tirer pour actualiser »).
  Future<void>? _loading;

  /// Relit la commande ; un échec garde la version affichée (et lève
  /// l'erreur). Une version plus ancienne que l'affichée est ignorée.
  Future<void> refresh() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    final order = await _client.myOrder(id);
    if (!ref.mounted) return;
    final shown = state.value;
    if (shown != null && order.updatedAt.isBefore(shown.updatedAt)) return;
    state = AsyncData(order);
    _share(order);
  }
}
