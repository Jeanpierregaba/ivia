import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_buyer/app/router.dart';
import 'package:ivia_buyer/features/cart/cart_screen.dart';
import 'package:ivia_buyer/features/checkout/checkout_screen.dart';
import 'package:ivia_buyer/features/orders/order_screen.dart';
import 'package:ivia_buyer/features/orders/orders_providers.dart';
import 'package:ivia_buyer/features/orders/orders_screen.dart';
import 'package:ivia_buyer/features/payment/payment_screen.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'support/buyer_app.dart';

/// Espaces typographiques remplacés par des espaces simples.
String plain(String s) => s.replaceAll(' ', ' ').replaceAll(' ', ' ');

Finder textPlain(String text) => find.byWidgetPredicate(
  (w) => w is Text && plain(w.data ?? w.textSpan?.toPlainText() ?? '') == text,
);

void main() {
  late BuyerHarness app;
  late Map<String, dynamic> afi;
  late Map<String, dynamic> wax;
  late Map<String, dynamic> riz;
  late Map<String, dynamic> huile;
  late Map<String, dynamic> pagne;

  setUp(() async {
    await BuyerHarness.resetStorage();
    app = BuyerHarness();
    afi = app.search.shop('Chez Afi');
    wax = app.search.shop('Wax & Co', neighborhoodId: beId);
    riz = app.search.product(afi, 'Riz parfumé 5 kg');
    huile = app.search.product(
      afi,
      'Huile 1 L',
      price: 1500,
      stockMode: 'untracked',
    );
    pagne = app.search.product(wax, 'Pagne wax', price: 12000);
  });

  Iterable<RecordedRequest> creations() =>
      app.server.calls('POST', '/v1/orders');

  Future<void> open(WidgetTester tester, String location) async {
    await app.launch(tester);
    GoRouter.of(tester.element(find.byType(IviaBottomNav))).push(location);
    await tester.pumpAndSettle();
  }

  /// Écran de téléphone haut : tout le suivi tient sans défiler.
  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> openOrders(WidgetTester tester) async {
    await app.launch(tester);
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
  }

  group('écran Commande', () {
    setUp(() {
      app.cart
        ..put(riz, 2)
        ..put(huile, 1);
    });

    testWidgets('récapitulatif, livraison « Bientôt », « Payer », suivi', (
      tester,
    ) async {
      await open(tester, Routes.checkout);
      expect(app.server.calls('POST', '/v1/orders/quote').single.body, {
        'fulfillment': 'pickup',
      });
      expect(find.text('Retrait chez Chez Afi'), findsOneWidget);
      expect(textPlain('2 × Riz parfumé 5 kg'), findsOneWidget);
      expect(textPlain('9 000 F'), findsOneWidget);
      expect(textPlain('Produits · 3 articles'), findsOneWidget);
      expect(textPlain('10 500 F'), findsNWidgets(2));
      expect(find.text('Bientôt'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('^Livraison.*bientôt disponible')),
        findsOneWidget,
      );
      expect(
        find.textContaining('réservés 15 minutes', skipOffstage: false),
        findsOneWidget,
      );

      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      final body = creations().single.body! as Map<String, dynamic>;
      expect(body['fulfillment'], 'pickup');
      expect(body['client_request_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      // Le paiement s'ouvre au-dessus du suivi.
      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(app.cart.lines, isEmpty);
      expect(riz['stock_quantity'], 10);

      // Retour : le suivi, commande toujours à payer.
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderScreen), findsOneWidget);
      expect(find.text('Commande #1042'), findsOneWidget);
      expect(find.textContaining('À payer avant'), findsOneWidget);

      // Retour : l'onglet Commandes, avec la commande en cours.
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(find.byType(OrdersScreen), findsOneWidget);
      expect(find.text('Chez Afi'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Panier')), findsNothing);
    });

    testWidgets('réseau coupé, puis nouvel essai : même identifiant', (
      tester,
    ) async {
      await open(tester, Routes.checkout);
      app.orders.failures['POST /v1/orders'] = FakeResponse.networkError();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Pas de connexion internet'), findsOneWidget);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(find.byType(PaymentScreen), findsOneWidget);
      final ids = creations().map(
        (r) => (r.body! as Map<String, dynamic>)['client_request_id'],
      );
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(1));
      expect(app.orders.orders, hasLength(1));
    });

    testWidgets('double appui : une seule commande', (tester) async {
      await open(tester, Routes.checkout);
      final gate = Completer<void>();
      app.orders.beforeRequest = (r) =>
          r.method == 'POST' ? gate.future : Future.value();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pump();
      await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
      await tester.pump();
      expect(find.bySemanticsLabel('Commande en cours'), findsOneWidget);
      expect(find.byTooltip('Retour'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(creations(), hasLength(1));
      expect(find.byType(PaymentScreen), findsOneWidget);
    });

    testWidgets('refus à la commande : message, « Revenir au panier »', (
      tester,
    ) async {
      await open(tester, Routes.cart);
      await tester.tap(find.text('Commander'));
      await tester.pumpAndSettle();
      afi['accepting_orders'] = false;
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(
        find.text('Cette boutique ne prend pas de commandes pour l’instant.'),
        findsOneWidget,
      );
      expect(app.orders.orders, isEmpty);
      final reads = app.server.calls('GET', '/v1/cart').length;
      await tester.tap(find.text('Revenir au panier'));
      await tester.pumpAndSettle();
      expect(find.byType(CartScreen), findsOneWidget);
      expect(app.server.calls('GET', '/v1/cart').length, greaterThan(reads));
    });

    testWidgets('« Revenir au panier » après avoir quitté l’écran', (
      tester,
    ) async {
      await open(tester, Routes.cart);
      await tester.tap(find.text('Commander'));
      await tester.pumpAndSettle();
      afi['accepting_orders'] = false;
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutScreen), findsNothing);
      await tester.tap(find.text('Revenir au panier'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CartScreen), findsOneWidget);
    });

    testWidgets('réponse perdue : commande créée, panier relu au retour', (
      tester,
    ) async {
      await open(tester, Routes.cart);
      await tester.tap(find.text('Commander'));
      await tester.pumpAndSettle();
      app.orders.loseNextCreateResponse = true;
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Pas de connexion internet'), findsOneWidget);
      expect(app.orders.orders, hasLength(1));
      // L'acheteur repart au lieu de réessayer : le panier n'est plus celui
      // qu'il a commandé.
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(find.byType(CartScreen), findsOneWidget);
      expect(find.text('Votre panier est vide.'), findsOneWidget);
    });

    testWidgets('réponse perdue puis nouvel essai : la même commande', (
      tester,
    ) async {
      await open(tester, Routes.checkout);
      app.orders.loseNextCreateResponse = true;
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(app.orders.orders, hasLength(1));
      expect(creations(), hasLength(2));
    });

    testWidgets('création déjà en cours (`duplicate_request`) : rendue', (
      tester,
    ) async {
      await open(tester, Routes.checkout);
      app.orders.failures['POST /v1/orders'] = FakeResponse.error(
        409,
        'duplicate_request',
        'Cette commande est déjà en cours de création.',
      );
      await tester.tap(find.byType(FilledButton).last);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(creations(), hasLength(2));
      expect(app.orders.orders, hasLength(1));
    });

    testWidgets('retour système pendant « Payer » : bloqué', (tester) async {
      await open(tester, Routes.checkout);
      final gate = Completer<void>();
      app.orders.beforeRequest = (r) =>
          r.method == 'POST' ? gate.future : Future.value();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(CheckoutScreen), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PaymentScreen), findsOneWidget);
    });

    testWidgets('trop de commandes, profil incomplet : message du serveur', (
      tester,
    ) async {
      await open(tester, Routes.checkout);
      app.orders.rateLimited = true;
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(
        find.text('Trop de commandes en peu de temps. Réessayez plus tard.'),
        findsOneWidget,
      );
      app.orders
        ..rateLimited = false
        ..profileComplete = false;
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Complétez votre profil'), findsOneWidget);
      expect(app.orders.orders, isEmpty);
    });

    testWidgets('récapitulatif refusé : panier vide', (tester) async {
      app.cart.lines.clear();
      app.cart.shopId = null;
      await open(tester, Routes.checkout);
      expect(find.text('Votre panier est vide.'), findsOneWidget);
      expect(find.textContaining('Payer'), findsNothing);
      await tester.tap(find.text('Revenir au panier'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutScreen), findsNothing);
    });

    testWidgets('récapitulatif : erreur du serveur, « Réessayer »', (
      tester,
    ) async {
      app.orders.failures['POST /v1/orders/quote'] = FakeResponse.error(
        500,
        'internal',
        'Une erreur est survenue. Réessayez dans un instant.',
      );
      await open(tester, Routes.checkout);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.text('Revenir au panier'), findsNothing);
    });

    testWidgets('modes annoncés comme boutons radio', (tester) async {
      await open(tester, Routes.checkout);
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Retrait, Gratuit'))),
        isSemantics(
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          isChecked: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
    });

    testWidgets('récapitulatif injoignable : « Réessayer »', (tester) async {
      app.orders.failures['POST /v1/orders/quote'] =
          FakeResponse.networkError();
      await open(tester, Routes.checkout);
      expect(find.textContaining('Vérifiez votre connexion'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Retrait chez Chez Afi'), findsOneWidget);
    });
  });

  group('onglet Commandes', () {
    testWidgets('en cours, « Récemment », terminées, pastilles', (
      tester,
    ) async {
      final day = DateTime.utc(2026, 10, 24, 9);
      for (var i = 0; i < 4; i++) {
        app.orders.seed(
          afi,
          [(riz, 1)],
          status: i == 0 ? 'refunded' : 'completed',
          at: day.subtract(Duration(days: i)),
        );
      }
      app.orders
        ..seed(wax, [(pagne, 1)], status: 'preparing')
        ..seed(afi, [(riz, 2), (huile, 1)]);
      tallScreen(tester);
      await openOrders(tester);
      expect(find.bySemanticsLabel('En cours, 2'), findsOneWidget);
      expect(textPlain('#1047 · Retrait · 3 articles'), findsOneWidget);
      expect(find.text('En attente de paiement'), findsOneWidget);
      expect(find.text('En préparation'), findsOneWidget);
      expect(find.text('RÉCEMMENT'), findsOneWidget);
      expect(find.bySemanticsLabel('Récemment'), findsOneWidget);
      expect(find.text('Remboursée'), findsOneWidget);
      expect(find.text('Retirée'), findsNWidgets(2));
      expect(textPlain('#1042 · 24 oct.'), findsOneWidget);

      await tester.tap(find.text('Terminées'));
      await tester.pumpAndSettle();
      expect(find.text('Retirée'), findsNWidgets(3));
      expect(find.text('En préparation'), findsNothing);

      await tester.tap(find.text('Remboursée'));
      await tester.pumpAndSettle();
      expect(find.text('Commande #1042'), findsOneWidget);
    });

    testWidgets('aucune commande : « Découvrir les produits »', (tester) async {
      await openOrders(tester);
      expect(find.text('Aucune commande en cours.'), findsOneWidget);
      await tester.tap(find.text('Terminées'));
      await tester.pumpAndSettle();
      expect(find.text('Aucune commande terminée.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp('^En cours')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Découvrir les produits'));
      await tester.pumpAndSettle();
      expect(find.byType(OrdersScreen), findsNothing);
    });

    testWidgets('relue à l’ouverture de l’onglet', (tester) async {
      await openOrders(tester);
      expect(find.text('Aucune commande en cours.'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.home_outlined));
      await tester.pumpAndSettle();
      app.orders.seed(afi, [(riz, 1)], status: 'accepted');
      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Acceptée par la boutique'), findsOneWidget);
    });
  });

  group('suivi', () {
    testWidgets('en attente de paiement : heure limite, « Payer », frise', (
      tester,
    ) async {
      tallScreen(tester);
      final o = app.orders.seed(afi, [(riz, 2), (huile, 1)]);
      await open(tester, Routes.order(o['id'] as String));
      expect(find.text('Commande #1042'), findsOneWidget);
      expect(find.text('En attente de paiement'), findsOneWidget);
      expect(find.textContaining('À payer avant'), findsOneWidget);
      expect(find.textContaining('Code de remise'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'^Commande passée, \d\d:\d\d, en cours')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Paiement reçu, à venir'), findsOneWidget);
      expect(textPlain('2 × Riz parfumé 5 kg'), findsOneWidget);
      expect(textPlain('10 500 F'), findsWidgets);
      await tester.tap(textPlain('Payer 10 500 F'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentScreen), findsOneWidget);
    });

    testWidgets('prête à retirer : code de remise et adresse', (tester) async {
      tallScreen(tester);
      final o = app.orders.seed(afi, [(riz, 1)], status: 'ready_for_pickup');
      await open(tester, Routes.order(o['id'] as String));
      expect(find.text('Prête à retirer'), findsWidgets);
      expect(find.text('Chez Chez Afi'), findsOneWidget);
      expect(find.bySemanticsLabel('Code de remise : 4 8 2 7'), findsOneWidget);
      expect(find.textContaining('uniquement au retrait'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Acceptée par Chez Afi, \d\d:\d\d, terminé'),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Retirée, à venir'), findsOneWidget);
    });

    testWidgets('relue toutes les 20 s, plus après la fin', (tester) async {
      tallScreen(tester);
      final o = app.orders.seed(afi, [(riz, 1)]);
      await open(tester, Routes.order(o['id'] as String));
      int reads() => app.server.calls('GET', '/v1/orders/${o['id']}').length;
      final first = reads();
      app.orders.advance(o, 'awaiting_seller');
      await tester.pump(orderRefreshInterval);
      await tester.pumpAndSettle();
      expect(reads(), first + 1);
      expect(find.text('En attente de la boutique'), findsWidgets);
      expect(find.bySemanticsLabel('Code de remise : 4 8 2 7'), findsOneWidget);
      for (final s in [
        'accepted',
        'preparing',
        'ready_for_pickup',
        'completed',
      ]) {
        app.orders.advance(o, s);
      }
      await tester.pump(orderRefreshInterval);
      await tester.pumpAndSettle();
      expect(find.text('Retirée'), findsWidgets);
      expect(
        find.textContaining(RegExp(r"^Aujourd'hui à \d\d:\d\d\. Merci")),
        findsOneWidget,
      );
      expect(find.textContaining('Code de remise'), findsNothing);
      final done = reads();
      await tester.pump(orderRefreshInterval * 3);
      await tester.pumpAndSettle();
      expect(reads(), done);
    });

    testWidgets('pas de relecture en arrière-plan ni sous un autre écran', (
      tester,
    ) async {
      tallScreen(tester);
      final o = app.orders.seed(afi, [(riz, 1)], status: 'preparing');
      await open(tester, Routes.order(o['id'] as String));
      int reads() => app.server.calls('GET', '/v1/orders/${o['id']}').length;
      var before = reads();
      // App en arrière-plan : rien ; au retour, relue aussitôt.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(orderRefreshInterval * 3);
      expect(reads(), before);
      app.orders.advance(o, 'ready_for_pickup');
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(reads(), before + 1);
      expect(find.text('Chez Chez Afi'), findsOneWidget);

      // Fiche boutique par-dessus : rien.
      await tester.tap(find.bySemanticsLabel(RegExp('^Boutique Chez Afi')));
      await tester.pumpAndSettle();
      before = reads();
      await tester.pump(orderRefreshInterval * 3);
      expect(reads(), before);

      // Suivi fermé : plus rien.
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      before = reads();
      await tester.pump(orderRefreshInterval * 3);
      expect(reads(), before);
    });

    testWidgets('délai dépassé pendant le suivi, puis paiement tardif', (
      tester,
    ) async {
      tallScreen(tester);
      final o = app.orders.seed(afi, [(riz, 1)]);
      await open(tester, Routes.order(o['id'] as String));
      app.orders.advance(o, 'expired');
      await tester.pump(orderRefreshInterval);
      await tester.pumpAndSettle();
      expect(find.text('Paiement expiré'), findsWidgets);
      // Paiement arrivé juste après l'heure limite : la commande reprend.
      app.orders.advance(o, 'awaiting_seller');
      await tester.pump(orderRefreshInterval);
      await tester.pumpAndSettle();
      expect(find.text('En attente de la boutique'), findsWidgets);
      expect(find.bySemanticsLabel('Code de remise : 4 8 2 7'), findsOneWidget);
    });

    testWidgets('frise : seules les raisons d’annulation sont montrées', (
      tester,
    ) async {
      tallScreen(tester);
      final o = app.orders.seed(afi, [(riz, 1)]);
      app.orders.advance(
        o,
        'awaiting_seller',
        reason: 'Paiement confirmé par le prestataire.',
      );
      await open(tester, Routes.order(o['id'] as String));
      expect(find.textContaining('prestataire'), findsNothing);
    });

    testWidgets('annulée : raison, frise close', (tester) async {
      tallScreen(tester);
      final o = app.orders.seed(afi, [(riz, 1)], status: 'awaiting_seller');
      app.orders.advance(o, 'cancelled', reason: 'Refusée par la boutique');
      await open(tester, Routes.order(o['id'] as String));
      expect(find.text('Annulée'), findsWidgets);
      expect(find.text('Refusée par la boutique'), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('à venir')), findsNothing);
    });

    testWidgets('commande introuvable', (tester) async {
      await open(tester, Routes.order('inconnue'));
      expect(
        find.text('Cette commande n’est plus disponible.'),
        findsOneWidget,
      );
    });

    testWidgets('police à 200 % sur 320 dp : commande, liste, suivi', (
      tester,
    ) async {
      smallScreenLargeFont(tester);
      app.cart.put(riz, 2);
      final o = app.orders.seed(afi, [(riz, 1)], status: 'ready_for_pickup');
      await open(tester, Routes.checkout);
      expect(tester.takeException(), isNull);
      GoRouter.of(tester.element(find.byType(CheckoutScreen)))
          .go(Routes.orders);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      GoRouter.of(tester.element(find.byType(OrdersScreen)))
          .push(Routes.order(o['id'] as String));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Les 4 chiffres sur une ligne.
      final tops = {
        for (final d in ['4', '8', '2', '7'])
          tester.getTopLeft(find.text(d)).dy,
      };
      expect(tops, hasLength(1));
    });
  });

  testWidgets('autre compte : commandes du compte connecté seulement', (
    tester,
  ) async {
    app.server
      ..on('POST', '/v1/auth/otp', (_) => FakeResponse.json(202, otpBody))
      ..on(
        'POST',
        '/v1/auth/verify',
        (_) => FakeResponse.json(200, {
          'token': 'jeton-kofi',
          'expires_at': '2026-12-30T08:00:00Z',
          'is_new_user': false,
          'user': {
            ...userBody(complete: true, email: 'kofi@test.tg'),
            'id': '9e8d7c6b-5a49-4382-a170-6b5c4d3e2f10',
            'first_name': 'Kofi',
          },
        }),
      );
    app.orders.seed(afi, [(riz, 1)], status: 'preparing');
    await openOrders(tester);
    final container = app.container(tester);
    expect(container.read(myOrdersViewProvider).value!.items, hasLength(1));
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tapText(tester, 'Se déconnecter');
    expect(container.read(myOrdersViewProvider).value, isNull);
    await container.read(myOrdersProvider.future);
    expect(container.read(myOrdersViewProvider).value!.items, isEmpty);

    // Kofi se connecte sur le même téléphone : aucune commande d'Awa.
    await tester.enterText(find.byType(TextField), 'kofi@test.tg');
    await tapText(tester, 'Recevoir le code');
    await tester.enterText(find.byType(TextField), '481902');
    await tester.pump();
    await tapText(tester, 'Vérifier le code');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Aucune commande en cours.'), findsOneWidget);
    expect(
      app.server.calls('GET', '/v1/orders').last.headers['authorization'],
      'Bearer jeton-kofi',
    );
  });

  group('annulation', () {
    Future<Map<String, dynamic>> seed({
      String status = 'pending_payment',
    }) async {
      final order = app.orders.seed(afi, [(riz, 2), (huile, 1)], status: status)
        ..['payment_deadline_at'] = DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String();
      return order;
    }

    Future<void> openOrder(
      WidgetTester tester,
      Map<String, dynamic> order,
    ) async {
      tallScreen(tester);
      await open(tester, Routes.order(order['id'] as String));
    }

    Finder cancelButton() =>
        find.widgetWithText(OutlinedButton, 'Annuler la commande');
    Finder confirm() =>
        find.widgetWithText(FilledButton, 'Annuler la commande');

    Future<void> askCancel(WidgetTester tester) async {
      await tester.ensureVisible(cancelButton());
      await tester.pumpAndSettle();
      await tester.tap(cancelButton());
      await tester.pumpAndSettle();
    }

    Iterable<RecordedRequest> cancels(Map<String, dynamic> order) =>
        app.server.calls('POST', '/v1/orders/${order['id']}/cancel');

    /// Demande de paiement en attente, faite par le même compte.
    Future<Map<String, dynamic>> pendingPayment(
      WidgetTester tester,
      Map<String, dynamic> order,
    ) async {
      final client = IviaApiClient(
        config: ApiConfig(baseUrl: Uri.parse('http://api.test')),
        adapter: app.server,
      )..token = 'jeton-secret';
      await tester.runAsync(
        () => client.startPayment(
          order['id'] as String,
          operator: PaymentOperator.flooz,
          phone: '96451278',
        ),
      );
      return app.payments.payments.last;
    }

    testWidgets('bouton seulement avant l\'acceptation', (tester) async {
      for (final (status, shown) in [
        ('pending_payment', true),
        ('awaiting_seller', true),
        ('accepted', false),
        ('ready_for_pickup', false),
        ('completed', false),
      ]) {
        final order = await seed(status: status);
        await openOrder(tester, order);
        expect(
          cancelButton(),
          shown ? findsOneWidget : findsNothing,
          reason: status,
        );
      }
    });

    testWidgets('non payée : feuille, « Garder », puis annulée', (
      tester,
    ) async {
      final order = await seed();
      await openOrder(tester, order);
      await askCancel(tester);
      expect(find.text('Annuler la commande #1042 ?'), findsOneWidget);
      expect(find.text('Vos produits seront libérés.'), findsOneWidget);
      await tester.tap(find.text('Garder ma commande'));
      await tester.pumpAndSettle();
      expect(cancels(order), isEmpty);

      final stock = riz['stock_quantity'] as int;
      await askCancel(tester);
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(cancels(order), hasLength(1));
      expect(find.text('Commande annulée.'), findsOneWidget);
      expect(find.text('Annulée'), findsWidgets);
      expect(find.textContaining("Annulée par l'acheteur."), findsWidgets);
      expect(find.textContaining('remboursé'), findsNothing);
      expect(cancelButton(), findsNothing);
      // Stock rendu (2 riz).
      expect(riz['stock_quantity'], stock + 2);
    });

    testWidgets('payée : remboursement annoncé, puis suivi « Annulée »', (
      tester,
    ) async {
      final order = await seed(status: 'awaiting_seller');
      await openOrder(tester, order);
      await askCancel(tester);
      const refund =
          'Vous serez remboursé de 10 500 F sur votre compte Mobile Money.';
      expect(textPlain(refund), findsOneWidget);
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(find.text('Annulée'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && plain(w.data ?? '').contains(refund),
        ),
        findsOneWidget,
      );

      // La liste suit : la commande est dans « Terminées ».
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terminées'));
      await tester.pumpAndSettle();
      expect(find.text('Annulée'), findsOneWidget);
    });

    testWidgets('demande de paiement en attente : annulée d\'abord', (
      tester,
    ) async {
      final order = await seed();
      final payment = await pendingPayment(tester, order);
      final before = app.server.requests.length;
      await openOrder(tester, order);
      await askCancel(tester);
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      final posts = [
        for (final r in app.server.requests.skip(before))
          if (r.method == 'POST') r.path,
      ];
      expect(posts, [
        '/v1/payments/${payment['id']}/cancel',
        '/v1/orders/${order['id']}/cancel',
      ]);
      expect(payment['status'], 'failed');
      expect(find.text('Annulée'), findsWidgets);
    });

    testWidgets('paiement validé entre-temps : feuille rouverte, remboursée', (
      tester,
    ) async {
      final order = await seed();
      final payment = await pendingPayment(tester, order);
      await openOrder(tester, order);
      // Le prestataire confirme juste avant l'annulation de la demande.
      app.payments.beforeRequest = (r) async {
        if (r.path.endsWith('/cancel') && r.path.contains('/payments/')) {
          app.payments.succeed(payment);
        }
      };
      await askCancel(tester);
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(cancels(order), isEmpty);
      expect(find.text('Annuler la commande #1042 ?'), findsOneWidget);
      expect(
        textPlain(
          'Vous serez remboursé de 10 500 F sur votre compte Mobile Money.',
        ),
        findsOneWidget,
      );
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(cancels(order), hasLength(1));
      expect(find.text('Annulée'), findsWidgets);
    });

    testWidgets('acceptée pendant la confirmation : message, bouton retiré', (
      tester,
    ) async {
      final order = await seed(status: 'awaiting_seller');
      await openOrder(tester, order);
      await askCancel(tester);
      app.orders.advance(order, 'accepted');
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(
        find.text(
          "La boutique a déjà accepté cette commande : contactez le support pour l'annuler.",
        ),
        findsOneWidget,
      );
      expect(cancelButton(), findsNothing);
    });

    testWidgets('expirée pendant la confirmation : message juste', (
      tester,
    ) async {
      final order = await seed();
      await openOrder(tester, order);
      await askCancel(tester);
      app.orders.advance(order, 'expired');
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(
        find.text('Cette commande a expiré : vos produits sont déjà libérés.'),
        findsOneWidget,
      );
      expect(find.text('Paiement expiré'), findsWidgets);
      expect(cancelButton(), findsNothing);
    });

    testWidgets('refusée par la boutique pendant la confirmation', (
      tester,
    ) async {
      final order = await seed(status: 'awaiting_seller');
      await openOrder(tester, order);
      await askCancel(tester);
      app.orders.advance(order, 'cancelled', reason: 'Boutique fermée');
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(find.text('Cette commande est déjà annulée.'), findsOneWidget);
      expect(find.textContaining('La boutique a déjà accepté'), findsNothing);
      expect(cancelButton(), findsNothing);
    });

    testWidgets(
      'payée entre deux relectures : feuille rouverte avec le montant',
      (tester) async {
        final order = await seed();
        await openOrder(tester, order);
        // Payée côté serveur, le suivi affiche encore « à payer ».
        app.orders.advance(order, 'awaiting_seller');
        await askCancel(tester);
        expect(find.text('Vos produits seront libérés.'), findsOneWidget);
        await tester.tap(confirm());
        await tester.pumpAndSettle();
        expect(cancels(order), isEmpty);
        expect(
          textPlain(
            'Vous serez remboursé de 10 500 F sur votre compte Mobile Money.',
          ),
          findsOneWidget,
        );
        await tester.tap(confirm());
        await tester.pumpAndSettle();
        expect(cancels(order), hasLength(1));
      },
    );

    testWidgets(
      'suivi quitté pendant l\'envoi, liste jamais ouverte : à jour',
      (tester) async {
        final order = await seed(status: 'awaiting_seller');
        await openOrder(tester, order);
        final release = Completer<void>();
        app.orders.beforeRequest = (r) async {
          if (r.path.endsWith('/cancel')) await release.future;
        };
        await askCancel(tester);
        await tester.tap(confirm());
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byTooltip('Retour'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.receipt_long_outlined));
        await tester.pumpAndSettle();
        release.complete();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Terminées'));
        await tester.pumpAndSettle();
        expect(find.text('Annulée'), findsOneWidget);
      },
    );

    testWidgets('réseau coupé : message, rien ne change ; nouvel essai', (
      tester,
    ) async {
      final order = await seed(status: 'awaiting_seller');
      await openOrder(tester, order);
      app.orders.failures['POST /v1/orders/'] = FakeResponse.networkError();
      await askCancel(tester);
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(find.text('Pas de connexion. Réessayez.'), findsOneWidget);
      expect(cancelButton(), findsOneWidget);
      expect(order['status'], 'awaiting_seller');
      await askCancel(tester);
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(find.text('Annulée'), findsWidgets);
    });

    testWidgets('police à 200 % sur 320 dp : bouton et feuille', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final order = await seed(status: 'awaiting_seller');
      await open(tester, Routes.order(order['id'] as String));
      await tester.scrollUntilVisible(
        cancelButton(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSemantics(cancelButton()),
        isSemantics(label: 'Annuler la commande', isButton: true),
      );
      await tester.tap(cancelButton());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Garder ma commande'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('pendant l\'envoi : bouton désactivé, une seule annulation', (
      tester,
    ) async {
      final order = await seed(status: 'awaiting_seller');
      await openOrder(tester, order);
      final release = Completer<void>();
      app.orders.beforeRequest = (r) async {
        if (r.path.endsWith('/cancel')) await release.future;
      };
      await askCancel(tester);
      await tester.tap(confirm());
      await tester.pump(const Duration(milliseconds: 500));
      final busy = find.ancestor(
        of: find.byType(ButtonProgress),
        matching: find.byType(OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(busy).onPressed, isNull);
      release.complete();
      await tester.pumpAndSettle();
      expect(cancels(order), hasLength(1));
    });
  });
}
