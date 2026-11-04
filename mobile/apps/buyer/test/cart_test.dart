import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_buyer/app/cart.dart';
import 'package:ivia_buyer/app/router.dart';
import 'package:ivia_buyer/features/cart/cart_screen.dart';
import 'package:ivia_buyer/features/checkout/checkout_screen.dart';
import 'package:ivia_buyer/features/search/search_screen.dart';
import 'package:ivia_buyer/features/shop/shop_screen.dart';
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
    afi = app.search.shop(
      'Chez Afi',
      location: const GeoPoint(lat: 6.1405, lng: 1.2123),
    );
    wax = app.search.shop(
      'Wax & Co',
      neighborhoodId: beId,
      location: const GeoPoint(lat: 6.1280, lng: 1.2200),
    );
    riz = app.search.product(afi, 'Riz parfumé 5 kg');
    huile = app.search.product(
      afi,
      'Huile 1 L',
      price: 1500,
      stockMode: 'untracked',
    );
    pagne = app.search.product(wax, 'Pagne wax', price: 12000);
  });

  /// Requêtes `PUT /v1/cart/items` envoyées.
  List<Map<String, dynamic>> puts() => [
    for (final r in app.server.calls('PUT', '/v1/cart/items'))
      r.body! as Map<String, dynamic>,
  ];

  Future<void> open(WidgetTester tester, String location) async {
    await app.launch(tester);
    GoRouter.of(tester.element(find.byType(IviaBottomNav))).push(location);
    await tester.pumpAndSettle();
  }

  Future<void> hideMessage(WidgetTester tester, Type screen) async {
    ScaffoldMessenger.of(tester.element(find.byType(screen)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
  }

  group('ajout', () {
    testWidgets('fiche produit : quantité ajoutée à celle du panier', (
      tester,
    ) async {
      app.cart.put(riz, 2);
      await open(tester, Routes.product(riz['id'] as String));
      expect(find.text('Déjà 2 dans votre panier'), findsOneWidget);
      expect(find.bySemanticsLabel('Panier, 2 articles'), findsOneWidget);
      await tester.tap(find.byTooltip('Ajouter 1'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(puts().single, {
        'product_id': riz['id'],
        'quantity': 4,
        'replace_cart': false,
      });
      expect(find.bySemanticsLabel('Panier, 4 articles'), findsOneWidget);
      expect(find.text('Déjà 4 dans votre panier'), findsOneWidget);
      expect(
        find.text('2 × Riz parfumé 5 kg ajoutés au panier'),
        findsOneWidget,
      );
      // Quantité remise à 1 après l'ajout.
      expect(textPlain('Ajouter · 4 500 F'), findsOneWidget);

      await tester.tap(find.text('Voir le panier'));
      await tester.pumpAndSettle();
      expect(find.byType(CartScreen), findsOneWidget);
    });

    testWidgets(
      'fiche produit : stock baissé entre-temps, message du serveur',
      (tester) async {
        await open(tester, Routes.product(riz['id'] as String));
        riz['stock_quantity'] = 1;
        await tester.tap(find.byTooltip('Ajouter 1'));
        await tester.pump();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(find.text('Seulement 1 en stock.'), findsOneWidget);
        expect(app.cart.quantityOf(riz), 0);
        expect(find.bySemanticsLabel('Panier'), findsOneWidget);
        // L'attente est levée : le bouton répond de nouveau.
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets('fiche produit : tout le stock, ou 99, déjà au panier', (
      tester,
    ) async {
      app.cart
        ..put(riz, 12)
        ..put(huile, 99);
      await open(tester, Routes.product(riz['id'] as String));
      expect(find.text('Tout le stock est au panier'), findsOneWidget);
      expect(find.byType(IviaQuantityStepper), findsNothing);
      FilledButton button() =>
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button().onPressed, isNull);

      GoRouter.of(tester.element(find.byType(FilledButton)))
          .push(Routes.product(huile['id'] as String));
      await tester.pumpAndSettle();
      expect(find.text('99 au plus : déjà au panier'), findsOneWidget);
    });

    testWidgets('fiche boutique : 99 déjà au panier, « + » refusé', (
      tester,
    ) async {
      app.cart.put(huile, 99);
      await open(tester, Routes.shop(afi['id'] as String));
      await tester.tap(find.bySemanticsLabel('Ajouter Huile 1 L au panier'));
      await tester.pumpAndSettle();
      expect(find.textContaining('99 exemplaires au plus'), findsOneWidget);
      expect(puts(), isEmpty);
    });

    testWidgets('« + » d’un produit retiré entre-temps : message', (
      tester,
    ) async {
      await open(tester, Routes.shop(afi['id'] as String));
      riz['is_active'] = false;
      await tester.tap(
        find.bySemanticsLabel('Ajouter Riz parfumé 5 kg au panier'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ce produit n’est plus disponible.'), findsOneWidget);
    });

    testWidgets('message avec action : disparaît après quelques secondes', (
      tester,
    ) async {
      await open(tester, Routes.shop(afi['id'] as String));
      await tester.tap(find.bySemanticsLabel('Ajouter Huile 1 L au panier'));
      await tester.pumpAndSettle();
      expect(find.text('Huile 1 L ajouté au panier'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('panier non chargé au lancement : l’ajout le relit', (
      tester,
    ) async {
      app.cart
        ..put(riz, 1)
        ..failures['GET /v1/cart'] = FakeResponse.networkError();
      await open(tester, Routes.shop(afi['id'] as String));
      expect(find.bySemanticsLabel('Panier'), findsOneWidget);
      await tester.tap(
        find.bySemanticsLabel('Ajouter Riz parfumé 5 kg au panier'),
      );
      await tester.pumpAndSettle();
      // Panier relu : 1 déjà au panier, 2 envoyé.
      expect(puts().single['quantity'], 2);
      expect(find.bySemanticsLabel('Panier, 2 articles'), findsOneWidget);
    });

    testWidgets('« + » d’une carte : autre boutique, annuler puis vider', (
      tester,
    ) async {
      app.cart.put(pagne, 1);
      await app.launch(tester);
      final add = find.bySemanticsLabel('Ajouter Riz parfumé 5 kg au panier');
      await tester.scrollUntilVisible(
        add,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // En haut de l'écran, loin de la barre du bas.
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Vider le panier ?'), findsOneWidget);
      expect(find.textContaining('produits de Wax & Co'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(puts(), hasLength(1));
      expect(app.cart.quantityOf(pagne), 1);
      expect(app.cart.quantityOf(riz), 0);

      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vider et ajouter'));
      await tester.pumpAndSettle();
      expect(puts().last, {
        'product_id': riz['id'],
        'quantity': 1,
        'replace_cart': true,
      });
      expect(app.cart.lines.keys, [riz['id']]);
      expect(find.text('Riz parfumé 5 kg ajouté au panier'), findsOneWidget);
      expect(
        app.container(tester).read(cartViewProvider).value!.cart.articleCount,
        1,
      );
    });

    testWidgets('fiche boutique : « + », puis barre « Voir le panier »', (
      tester,
    ) async {
      app.search.product(afi, 'Lait en poudre', stock: 0);
      await open(tester, Routes.shop(afi['id'] as String));
      expect(find.textContaining('Voir le panier'), findsNothing);
      // Pas de « + » sur un produit épuisé.
      expect(find.byType(IviaAddButton), findsNWidgets(2));
      expect(
        find.bySemanticsLabel('Ajouter Lait en poudre au panier'),
        findsNothing,
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.bySemanticsLabel('Ajouter Huile 1 L au panier'));
        await tester.pumpAndSettle();
        await hideMessage(tester, ShopScreen);
      }
      expect(puts().map((p) => p['quantity']), [1, 2]);
      expect(find.text('Voir le panier · 2'), findsOneWidget);
      expect(textPlain('3 000 F'), findsOneWidget);
      await tester.tap(find.text('Voir le panier · 2'));
      await tester.pumpAndSettle();
      expect(find.byType(CartScreen), findsOneWidget);
    });

    testWidgets('fiche d’une autre boutique : pas de barre', (tester) async {
      app.cart.put(riz, 1);
      await open(tester, Routes.shop(wax['id'] as String));
      expect(find.textContaining('Voir le panier'), findsNothing);
      expect(find.bySemanticsLabel('Panier, 1 article'), findsOneWidget);
    });
  });

  group('écran Panier', () {
    testWidgets('boutique, lignes, sous-total, quantités', (tester) async {
      app.cart
        ..put(riz, 2)
        ..put(huile, 1);
      await open(tester, Routes.cart);
      expect(find.text('Chez Afi'), findsOneWidget);
      expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
      expect(textPlain('Sous-total · 3 articles'), findsOneWidget);
      expect(textPlain('10 500 F'), findsOneWidget);
      expect(
        find.text('Frais de livraison calculés à l’étape suivante.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'produits d’une seule boutique',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Ajouter un Riz parfumé 5 kg'));
      await tester.pumpAndSettle();
      expect(puts().last['quantity'], 3);
      expect(textPlain('15 000 F'), findsOneWidget);

      // « − » à 1 : la ligne est retirée, « Annuler » la remet.
      await tester.tap(find.byTooltip('Retirer Huile 1 L du panier'));
      await tester.pumpAndSettle();
      expect(puts().last, containsPair('quantity', 0));
      expect(find.text('Huile 1 L'), findsNothing);
      expect(find.text('Huile 1 L retiré du panier'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(puts().last, containsPair('quantity', 1));
      expect(find.text('Huile 1 L'), findsOneWidget);

      await tester.tap(find.text('Commander'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    testWidgets(
      'lignes en erreur : « Ajuster », « Retirer », commande bloquée',
      (tester) async {
        app.cart
          ..put(riz, 3)
          ..put(huile, 1)
          ..put(app.search.product(afi, 'Sucre 1 kg', price: 800), 1);
        riz['stock_quantity'] = 2;
        huile['is_active'] = false;
        await open(tester, Routes.cart);
        expect(find.text('Plus que 2 en stock.'), findsOneWidget);
        expect(find.text("Ce produit n'est plus disponible."), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Corrigez les produits signalés pour commander.'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        FilledButton order() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Commander'),
        );
        expect(order().onPressed, isNull);
        // Lignes en erreur hors du sous-total.
        expect(textPlain('Sous-total · 1 article'), findsOneWidget);

        await tapText(tester, 'Ajuster à 2');
        expect(puts().last, {
          'product_id': riz['id'],
          'quantity': 2,
          'replace_cart': false,
        });
        expect(find.text('Plus que 2 en stock.'), findsNothing);
        await tapText(tester, 'Retirer');
        expect(puts().last, containsPair('quantity', 0));
        expect(find.text('Huile 1 L'), findsNothing);
        expect(order().onPressed, isNotNull);
      },
    );

    testWidgets('épuisé : « Retirer » seulement', (tester) async {
      app.cart.put(riz, 2);
      riz['stock_quantity'] = 0;
      await open(tester, Routes.cart);
      expect(find.text('Épuisé pour l’instant.'), findsOneWidget);
      expect(find.text('Retirer'), findsOneWidget);
      expect(find.textContaining('Ajuster'), findsNothing);
    });

    testWidgets('boutique qui ne prend plus de commandes', (tester) async {
      app.cart.put(riz, 1);
      afi['accepting_orders'] = false;
      await open(tester, Routes.cart);
      expect(
        find.text('Chez Afi ne prend pas de commandes pour l’instant.'),
        findsOneWidget,
      );
      final order = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Commander'),
      );
      expect(order.onPressed, isNull);
    });

    testWidgets('« Vider » confirmé, puis panier vide et recherche', (
      tester,
    ) async {
      app.cart.put(riz, 2);
      await open(tester, Routes.cart);
      await tester.tap(find.text('Vider'));
      await tester.pumpAndSettle();
      expect(find.text('Vider le panier ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(app.server.calls('DELETE', '/v1/cart'), isEmpty);

      await tester.tap(find.text('Vider'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vider le panier'));
      await tester.pumpAndSettle();
      expect(app.server.calls('DELETE', '/v1/cart'), hasLength(1));
      expect(find.text('Votre panier est vide.'), findsOneWidget);
      expect(find.text('Vider'), findsNothing);
      expect(find.text('Commander'), findsNothing);
      await tester.tap(find.text('Découvrir les produits'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('réseau coupé : quantité remise, puis chargement à refaire', (
      tester,
    ) async {
      app.cart.put(riz, 2);
      await open(tester, Routes.cart);
      app.cart.failures['PUT /v1/cart/items'] = FakeResponse.networkError();
      await tester.tap(find.byTooltip('Ajouter un Riz parfumé 5 kg'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pas de connexion internet'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Quantité de Riz parfumé 5 kg'))
            .value,
        '2',
      );
      expect(app.cart.quantityOf(riz), 2);
    });

    testWidgets('panier non chargé : « Réessayer »', (tester) async {
      app.cart
        ..put(riz, 1)
        ..failures['GET /v1/cart'] = FakeResponse.networkError();
      await app.launch(tester);
      expect(find.bySemanticsLabel('Panier'), findsOneWidget);
      // L'écran relit le panier à l'ouverture : seconde coupure.
      app.cart.failures['GET /v1/cart'] = FakeResponse.networkError();
      GoRouter.of(tester.element(find.byType(IviaBottomNav))).push(Routes.cart);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Impossible de charger le panier'),
        findsOneWidget,
      );
      await tapText(tester, 'Réessayer');
      expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
    });

    testWidgets('appuis rapides : une requête à la fois, la dernière gagne', (
      tester,
    ) async {
      app.cart.put(riz, 1);
      await open(tester, Routes.cart);
      final gate = Completer<void>();
      app.cart.beforeRequest = (r) =>
          r.method == 'PUT' ? gate.future : Future.value();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Ajouter un Riz parfumé 5 kg'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Quantité voulue affichée pendant l'envoi.
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Quantité de Riz parfumé 5 kg'))
            .value,
        '4',
      );
      expect(puts().map((p) => p['quantity']), [2]);
      final order = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Commander'),
      );
      expect(order.onPressed, isNull);
      gate.complete();
      await tester.pumpAndSettle();
      expect(puts().map((p) => p['quantity']), [2, 4]);
      expect(app.cart.quantityOf(riz), 4);
      expect(textPlain('18 000 F'), findsOneWidget);
    });

    testWidgets('échec au milieu de la file : quantité enregistrée', (
      tester,
    ) async {
      app.cart.put(riz, 1);
      await open(tester, Routes.cart);
      final gate = Completer<void>();
      var sent = 0;
      // Le premier envoi (2) attend puis passe, le suivant (4) est refusé.
      app.cart.beforeRequest = (r) {
        if (r.method != 'PUT') return Future.value();
        if (++sent == 2) {
          app.cart.failures['PUT /v1/cart/items'] = FakeResponse.error(
            409,
            'insufficient_stock',
            'Seulement 3 en stock.',
          );
        }
        return sent == 1 ? gate.future : Future.value();
      };
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Ajouter un Riz parfumé 5 kg'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      gate.complete();
      await tester.pumpAndSettle();
      expect(puts().map((p) => p['quantity']), [2, 4]);
      expect(find.text('Seulement 3 en stock.'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Quantité de Riz parfumé 5 kg'))
            .value,
        '2',
      );
      final order = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Commander'),
      );
      expect(order.onPressed, isNotNull);
    });

    testWidgets('« Vider » pendant un envoi : rien ne recrée le panier', (
      tester,
    ) async {
      app.cart.put(riz, 1);
      await open(tester, Routes.cart);
      final gate = Completer<void>();
      app.cart.beforeRequest = (r) =>
          r.method == 'PUT' ? gate.future : Future.value();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Ajouter un Riz parfumé 5 kg'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.text('Vider'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vider le panier'));
      await tester.pump(const Duration(milliseconds: 50));
      // Pendant le vidage, le panier ne se modifie pas.
      final vider = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Vider'),
      );
      expect(vider.onPressed, isNull);
      gate.complete();
      await tester.pumpAndSettle();
      // Seul le premier envoi est parti, avant le vidage.
      expect(puts().map((p) => p['quantity']), [2]);
      expect(app.server.calls('DELETE', '/v1/cart'), hasLength(1));
      expect(app.cart.lines, isEmpty);
      expect(find.text('Votre panier est vide.'), findsOneWidget);
    });

    testWidgets('« Annuler » après avoir quitté le panier', (tester) async {
      app.cart
        ..put(riz, 3)
        ..put(huile, 1);
      await open(tester, Routes.cart);
      await tester.tap(find.byTooltip('Retirer Huile 1 L du panier'));
      await tester.pumpAndSettle();
      expect(app.cart.quantityOf(huile), 0);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(find.byType(CartScreen), findsNothing);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(app.cart.quantityOf(huile), 1);
      expect(find.bySemanticsLabel('Panier, 4 articles'), findsOneWidget);
    });

    testWidgets('lignes en erreur : boutons lus avec le nom du produit', (
      tester,
    ) async {
      app.cart.put(riz, 3);
      riz['stock_quantity'] = 2;
      await open(tester, Routes.cart);
      expect(
        find.bySemanticsLabel('Retirer Riz parfumé 5 kg du panier'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Ajuster Riz parfumé 5 kg à 2'),
        findsOneWidget,
      );
    });

    testWidgets(
      'police à 200 % sur 320 dp : panier et barre sans débordement',
      (tester) async {
        smallScreenLargeFont(tester);
        app.cart
          ..put(riz, 3)
          ..put(huile, 1);
        riz['stock_quantity'] = 2;
        await open(tester, Routes.cart);
        expect(tester.takeException(), isNull);
        GoRouter.of(tester.element(find.byType(CartScreen)))
            .push(Routes.shop(afi['id'] as String));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Voir le panier · 4'), findsOneWidget);
        // Une ligne bloque : pas de sous-total trompeur dans la barre.
        expect(find.text('À vérifier'), findsOneWidget);
      },
    );
  });

  testWidgets('autre compte : panier du compte connecté seulement', (
    tester,
  ) async {
    const kofi = '9e8d7c6b-5a49-4382-a170-6b5c4d3e2f10';
    app.server.on(
      'POST',
      '/v1/auth/login',
      (_) => FakeResponse.json(200, {
        'token': 'jeton-kofi',
        'expires_at': '2026-12-30T08:00:00Z',
        'is_new_user': false,
        'user': {
          ...userBody(complete: true, email: 'kofi@test.tg'),
          'id': kofi,
          'first_name': 'Kofi',
        },
      }),
    );
    app.cart.put(riz, 2);
    await app.launch(tester);
    final container = app.container(tester);
    expect(container.read(cartViewProvider).value!.cart.articleCount, 2);
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tapText(tester, 'Se déconnecter');
    // Pendant la relecture, l'ancien panier n'est jamais montré.
    expect(container.read(cartViewProvider).value, isNull);
    await container.read(cartProvider.future);
    expect(container.read(cartViewProvider).value!.cart.isEmpty, isTrue);

    // Kofi se connecte sur le même téléphone : son panier, vide.
    Finder input(String label) => find.descendant(
      of: find.widgetWithText(IviaFieldLabel, label),
      matching: find.byType(TextField),
    );
    await tester.enterText(input('Adresse e-mail'), 'kofi@test.tg');
    await tester.enterText(input('Mot de passe'), 'pagne-wax-2026');
    await tapText(tester, 'Se connecter');
    await tester.pumpAndSettle();
    expect(find.textContaining('Bonjour Kofi'), findsOneWidget);
    expect(find.bySemanticsLabel('Panier'), findsOneWidget);
    expect(container.read(cartViewProvider).value!.cart.isEmpty, isTrue);
    expect(
      app.server.calls('GET', '/v1/cart').last.headers['authorization'],
      'Bearer jeton-kofi',
    );
    // Le panier d'Awa reste le sien.
    expect(app.cart.quantityOf(riz), 2);
  });
}
