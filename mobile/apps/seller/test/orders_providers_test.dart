import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_seller/app/seller_shop.dart';
import 'package:ivia_seller/features/orders/order_labels.dart';
import 'package:ivia_seller/features/orders/orders_providers.dart';

/// Boutique publiée, sans passer par la session.
class _PublishedShop extends SellerShop {
  @override
  Future<Shop?> build() async => Shop.fromJson(shopBody(status: 'published'));
}

void main() {
  late FakeApiServer server;
  late FakeSellerOrders orders;
  late ProviderContainer container;

  setUp(() {
    server = FakeApiServer();
    orders = FakeSellerOrders(server);
    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          IviaApiClient(
            config: ApiConfig(baseUrl: Uri.parse('http://api.test')),
            adapter: server,
          ),
        ),
        sellerShopProvider.overrideWith(_PublishedShop.new),
      ],
    );
    addTearDown(container.dispose);
    // Riverpod met en pause un fournisseur que personne n'écoute.
    container.listen(sellerOrdersProvider, (_, _) {});
  });

  SellerOrdersController notifier() =>
      container.read(sellerOrdersProvider.notifier);

  /// « Afficher plus » retenu jusqu'à [gate].
  Completer<void> holdNextPage() {
    final gate = Completer<void>();
    orders.beforeRequest = (r) async {
      if (r.query['offset'] == '100') await gate.future;
    };
    return gate;
  }

  test(
    '« Afficher plus » lent : une relecture arrivée entre-temps reste',
    () async {
      for (var i = 0; i < 103; i++) {
        orders.add(status: 'completed');
      }
      final first = await container.read(sellerOrdersProvider.future);
      expect(first.orders, hasLength(100));

      final gate = holdNextPage();
      final more = notifier().loadMore();
      final fresh = orders.add();
      await notifier().refresh();
      gate.complete();
      await more;

      final state = container.read(sellerOrdersProvider).value!;
      expect(state.of(OrderTab.fresh).single.id, fresh['id']);
      expect(state.orders, hasLength(104));
      expect(state.orders.map((o) => o.id).toSet(), hasLength(104));
    },
  );

  test('« Afficher plus » lent : une action faite entre-temps reste', () async {
    for (var i = 0; i < 102; i++) {
      orders.add(status: 'completed');
    }
    // La plus récente : dans la première page.
    final id = orders.add()['id'] as String;
    await container.read(sellerShopProvider.future);
    await container.read(sellerOrdersProvider.future);

    final gate = holdNextPage();
    final more = notifier().loadMore();
    final client = container.read(apiClientProvider);
    notifier().replace(await client.acceptOrder(id));
    gate.complete();
    await more;

    final state = container.read(sellerOrdersProvider).value!;
    expect(
      state.orders.firstWhere((o) => o.id == id).status,
      OrderStatus.accepted,
    );
    expect(state.count(OrderTab.fresh), 0);
  });

  test('commande inconnue de la liste : pas ajoutée par replace', () async {
    orders.add();
    await container.read(sellerShopProvider.future);
    await container.read(sellerOrdersProvider.future);
    final other = SellerOrder.fromJson(
      sellerOrderBody(
        id: 'c0000000-0000-4000-8000-000000000999',
        status: 'completed',
      ),
    );
    notifier().replace(other);
    expect(container.read(sellerOrdersProvider).value!.orders, hasLength(1));
  });
}
