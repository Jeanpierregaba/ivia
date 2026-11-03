import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/seller_shop.dart';
import 'order_labels.dart';

/// Commandes lues à chaque relecture : une nouvelle commande ne vit que
/// 15 min, elle est toujours parmi les dernières.
const ordersPageSize = 100;

/// Intervalle de relecture des commandes, app au premier plan.
const ordersRefreshInterval = Duration(seconds: 30);

/// Commandes de la boutique publiée, réparties par onglet.
class SellerOrders {
  const SellerOrders({required this.orders, required this.nextOffset});

  static const empty = SellerOrders(orders: [], nextOffset: null);

  /// Commandes lues, plus récentes d'abord.
  final List<SellerOrder> orders;

  /// Suite de la liste (« Afficher plus ») ; `null` : tout est lu.
  final int? nextOffset;

  /// Commandes d'un onglet : les nouvelles par délai croissant (la plus
  /// urgente en haut), les autres plus récentes d'abord.
  List<SellerOrder> of(OrderTab tab) {
    final list = [
      for (final o in orders)
        if (tabOf(o.status) == tab) o,
    ];
    if (tab == OrderTab.fresh) {
      list.sort((a, b) {
        final da = a.sellerDeadlineAt ?? a.createdAt;
        final db = b.sellerDeadlineAt ?? b.createdAt;
        return da.compareTo(db);
      });
    }
    return list;
  }

  int count(OrderTab tab) => orders.where((o) => tabOf(o.status) == tab).length;
}

/// Boutique dont on lit les commandes : publiée seulement.
String? _publishedShopId(AsyncValue<Shop?> shop) => switch (shop.value) {
  final s? when s.status == ShopStatus.published => s.id,
  _ => null,
};

/// Commandes de la boutique publiée. Relues par le cadre des onglets :
/// nouvelles seulement toutes les 30 s au premier plan ([poll]), liste
/// complète au retour dans l'app et à l'ouverture de l'onglet Commandes
/// ([refresh]) ; en tirant vers le bas ; mises à jour par chaque action.
final sellerOrdersProvider =
    AsyncNotifierProvider<SellerOrdersController, SellerOrders>(
      SellerOrdersController.new,
      // Pas de nouvel essai automatique : la relecture suivante s'en charge.
      retry: (_, _) => null,
    );

class SellerOrdersController extends AsyncNotifier<SellerOrders> {
  String? _shopId;

  @override
  Future<SellerOrders> build() async {
    _shopId = ref.watch(sellerShopProvider.select(_publishedShopId));
    if (_shopId == null) return SellerOrders.empty;
    return _fetchFirst();
  }

  IviaApiClient get _client => ref.read(apiClientProvider);

  Future<SellerOrders> _fetchFirst() async {
    final page = await _guard(
      () => _client.sellerOrders(shopId: _shopId, limit: ordersPageSize),
    );
    return SellerOrders(orders: page.items, nextOffset: page.nextOffset);
  }

  /// Boutique suspendue ou retirée entre-temps : la boutique est relue et
  /// le routeur ouvre l'écran « suspendue ».
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiException catch (e) {
      if (e.code == 'shop_suspended' || e.code == 'shop_not_found') {
        await ref.read(sellerShopProvider.notifier).refresh();
      }
      rethrow;
    }
  }

  /// Relit la première page. Les pages déjà ajoutées par « Afficher plus »
  /// restent ; une commande changée ici depuis le départ de la requête
  /// (action du marchand) garde sa version la plus récente. Échec : les
  /// données affichées restent, l'erreur remonte à l'appelant.
  Future<void> refresh() async {
    final shopId = _shopId;
    if (shopId == null) return;
    final fresh = await _fetchFirst();
    // Boutique ou compte changé pendant la requête : réponse ignorée.
    if (!ref.mounted || _shopId != shopId) return;
    final current = state.value;
    if (current == null) {
      state = AsyncData(fresh);
      return;
    }
    final byId = {for (final o in current.orders) o.id: o};
    final merged = [
      for (final o in fresh.orders) _newest(byId.remove(o.id), o),
    ];
    // Commandes plus anciennes que la première page (« Afficher plus »).
    final oldest = fresh.orders.lastOrNull?.createdAt;
    final older = [
      for (final o in current.orders)
        if (byId.containsKey(o.id) &&
            oldest != null &&
            !o.createdAt.isAfter(oldest))
          o,
    ];
    state = AsyncData(
      SellerOrders(
        orders: [...merged, ...older],
        nextOffset: older.isEmpty ? fresh.nextOffset : current.nextOffset,
      ),
    );
  }

  /// Relecture légère (toutes les 30 s) : les nouvelles commandes
  /// seulement. Une nouvelle commande arrivée prend sa place dans la liste ;
  /// une commande « nouvelle » absente de la réponse (acceptée ailleurs,
  /// annulée, délai dépassé) est relue seule. La liste complète est relue
  /// par [refresh] (ouverture de l'onglet, retour dans l'app, tirer vers le
  /// bas).
  Future<void> poll() async {
    final shopId = _shopId;
    if (shopId == null) return;
    if (state.value == null) return refresh();
    final page = await _guard(
      () => _client.sellerOrders(
        shopId: shopId,
        status: OrderStatus.awaitingSeller,
        limit: ordersPageSize,
      ),
    );
    if (!ref.mounted || _shopId != shopId) return;
    final current = state.value;
    if (current == null) return;
    final orders = [...current.orders];
    for (final o in page.items) {
      final i = orders.indexWhere((known) => known.id == o.id);
      if (i >= 0) {
        orders[i] = _newest(orders[i], o);
      } else {
        // Plus récentes d'abord, comme le serveur.
        final at = orders.indexWhere((k) => k.createdAt.isBefore(o.createdAt));
        orders.insert(at < 0 ? orders.length : at, o);
      }
    }
    state = AsyncData(
      SellerOrders(orders: orders, nextOffset: current.nextOffset),
    );
    final waiting = {for (final o in page.items) o.id};
    final gone = [
      for (final o in orders)
        if (o.status == OrderStatus.awaitingSeller && !waiting.contains(o.id))
          o.id,
    ];
    for (final id in gone) {
      try {
        replace(await _client.sellerOrder(id));
      } on Exception {
        // Relue au passage suivant.
      }
      if (!ref.mounted || _shopId != shopId) return;
    }
  }

  /// Ajoute la page suivante (« Afficher plus »). La liste est relue à la
  /// réponse : une relecture ou une action arrivée entre-temps est gardée.
  Future<void> loadMore() async {
    final shopId = _shopId;
    final offset = state.value?.nextOffset;
    if (offset == null || shopId == null) return;
    final page = await _guard(
      () => _client.sellerOrders(
        shopId: shopId,
        offset: offset,
        limit: ordersPageSize,
      ),
    );
    if (!ref.mounted || _shopId != shopId) return;
    final current = state.value;
    if (current == null) return;
    final known = {for (final o in current.orders) o.id};
    state = AsyncData(
      SellerOrders(
        orders: [
          ...current.orders,
          for (final o in page.items)
            if (!known.contains(o.id)) o,
        ],
        nextOffset: page.nextOffset,
      ),
    );
  }

  /// Commande rendue par le serveur (action, détail relu) : remplace la
  /// version de la liste si elle est au moins aussi récente. Une commande
  /// absente de la liste (ancienne, lien) n'y est pas ajoutée : sa place
  /// dépend de la pagination, la relecture suivante la range.
  void replace(SellerOrder order) {
    final current = state.value;
    if (current == null) return;
    final orders = [...current.orders];
    final i = orders.indexWhere((o) => o.id == order.id);
    if (i < 0) return;
    orders[i] = _newest(orders[i], order);
    state = AsyncData(
      SellerOrders(orders: orders, nextOffset: current.nextOffset),
    );
  }
}

/// Version la plus récente d'une commande (`updated_at`) ; à égalité, celle
/// qui vient d'arriver.
SellerOrder _newest(SellerOrder? known, SellerOrder incoming) =>
    known != null && known.updatedAt.isAfter(incoming.updatedAt)
    ? known
    : incoming;

/// Une commande, pour son détail. Relue par l'écran (toutes les 30 s au
/// premier plan) et mise à jour par chaque action, qui met aussi la liste à
/// jour.
final sellerOrderProvider = AsyncNotifierProvider.autoDispose
    .family<SellerOrderController, SellerOrder, String>(
      SellerOrderController.new,
      retry: (_, _) => null,
    );

class SellerOrderController extends AsyncNotifier<SellerOrder> {
  SellerOrderController(this.id);

  final String id;

  @override
  Future<SellerOrder> build() async {
    // Version de la liste en attendant : l'écran s'ouvre sans attendre.
    final listed = ref
        .read(sellerOrdersProvider)
        .value
        ?.orders
        .where((o) => o.id == id)
        .firstOrNull;
    if (listed != null) {
      Future.microtask(() => refresh().catchError((Object _) {}));
      return listed;
    }
    return _fetch();
  }

  /// Lit la commande et la reporte dans la liste (même si l'écran est
  /// quitté entre-temps). Boutique suspendue : la boutique est relue.
  Future<SellerOrder> _fetch() async {
    final client = ref.read(apiClientProvider);
    final list = ref.read(sellerOrdersProvider.notifier);
    final shop = ref.read(sellerShopProvider.notifier);
    try {
      final order = await client.sellerOrder(id);
      list.replace(order);
      return order;
    } on ApiException catch (e) {
      if (e.code == 'shop_suspended' || e.code == 'shop_not_found') {
        unawaited(shop.refresh());
      }
      rethrow;
    }
  }

  /// Relit la commande ; une version plus récente déjà affichée (action
  /// faite pendant la requête) est gardée.
  Future<void> refresh() async {
    final order = await _fetch();
    set(order);
  }

  /// Commande rendue par le serveur : affichée si elle est au moins aussi
  /// récente, et reportée dans la liste. Sans effet si le détail n'est plus
  /// affiché (fournisseur libéré).
  void set(SellerOrder order) {
    if (!ref.mounted) return;
    state = AsyncData(_newest(state.value, order));
    ref.read(sellerOrdersProvider.notifier).replace(order);
  }
}
