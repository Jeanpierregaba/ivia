import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_buyer/features/search/search_screen.dart';
import 'package:ivia_buyer/features/shop/shop_screen.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'support/buyer_app.dart';

void main() {
  late BuyerHarness app;
  late Map<String, dynamic> afi;

  setUp(() async {
    await BuyerHarness.resetStorage();
    app = BuyerHarness();
    afi = app.search.shop(
      'Chez Afi',
      location: const GeoPoint(lat: 6.1405, lng: 1.2123),
    );
    final wax = app.search.shop(
      'Wax & Co',
      neighborhoodId: beId,
      location: const GeoPoint(lat: 6.1280, lng: 1.2200),
    );
    app.search
      ..product(afi, 'Riz parfumé 5 kg')
      ..product(afi, 'Riz local 1 kg', price: 900, stock: 0)
      ..product(
        wax,
        'Pagne wax 6 yards',
        price: 12000,
        categoryId: 'c1000000-0000-4000-8000-000000000003',
      );
  });

  Iterable<RecordedRequest> products() =>
      app.searches('/v1/search/products').where((r) => r.query['lat'] != null);

  Finder priceField(String label) => find.descendant(
    of: find.widgetWithText(IviaFieldLabel, label),
    matching: find.byType(TextField),
  );

  Future<void> openSearch(WidgetTester tester) async {
    await app.launch(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(IviaBottomNav),
        matching: find.byIcon(Icons.search),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(IviaSearchField),
        matching: find.byType(TextField),
      ),
      text,
    );
  }

  testWidgets('recherche envoyée 300 ms après la dernière frappe', (
    tester,
  ) async {
    await openSearch(tester);
    final before = products().length;
    await type(tester, 'r');
    await tester.pump(const Duration(milliseconds: 100));
    await type(tester, 'ri');
    await tester.pump(const Duration(milliseconds: 100));
    await type(tester, 'riz');
    await tester.pump(const Duration(milliseconds: 100));
    expect(products().length, before, reason: 'pendant la frappe');
    await tester.pump(searchDelay);
    await tester.pumpAndSettle();
    final sent = products().skip(before).toList();
    expect(sent, hasLength(1), reason: 'une seule requête');
    expect(sent.single.query['q'], 'riz');
    expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
    expect(find.text('Pagne wax 6 yards'), findsNothing);
    // Épuisé signalé.
    expect(find.text('Épuisé'), findsOneWidget);
  });

  testWidgets('filtres : rayon, catégorie, prix, en stock, tri', (
    tester,
  ) async {
    await openSearch(tester);
    expect(products().last.query['radius_m'], '5000', reason: 'par défaut');

    await tapText(tester, 'Autour de moi · 5 km');
    await tapText(tester, '2 km');
    expect(products().last.query['radius_m'], '2000');

    await tapText(tester, 'Catégorie');
    await tapText(tester, 'Alimentation');
    expect(
      products().last.query['category_id'],
      'c1000000-0000-4000-8000-000000000001',
    );
    expect(find.text('Pagne wax 6 yards'), findsNothing);

    await tapText(tester, 'Prix');
    await tester.enterText(priceField('Minimum'), '5000');
    await tester.enterText(priceField('Maximum'), '1000');
    await tapText(tester, 'Appliquer');
    expect(
      find.text('Le prix minimal dépasse le prix maximal.'),
      findsOneWidget,
    );
    await tester.enterText(priceField('Maximum'), '8000');
    await tapText(tester, 'Appliquer');
    final query = products().last.query;
    expect(query['min_price'], '5000');
    expect(query['max_price'], '8000');

    await tapText(tester, 'En stock');
    expect(products().last.query['in_stock'], 'true');

    await tapText(tester, 'Trier : pertinence');
    expect(find.text('Distance'), findsOneWidget);
    await tapText(tester, 'Prix croissant');
    expect(products().last.query['sort'], 'price_asc');
  });

  testWidgets('aucun résultat avec filtres : « Effacer les filtres »', (
    tester,
  ) async {
    await openSearch(tester);
    await tapText(tester, 'En stock');
    await type(tester, 'local');
    await tester.pump(searchDelay);
    await tester.pumpAndSettle();
    expect(
      find.text('Aucun produit ne correspond à « local ».'),
      findsOneWidget,
    );
    await tapText(tester, 'Effacer les filtres');
    expect(products().last.query.containsKey('in_stock'), isFalse);
    expect(products().last.query['q'], 'local', reason: 'texte gardé');
    expect(find.text('Riz local 1 kg'), findsOneWidget);
  });

  testWidgets('onglet Boutiques : recherche de boutiques, fiche', (
    tester,
  ) async {
    await openSearch(tester);
    await tapText(tester, 'Boutiques');
    final shops = app.searches('/v1/search/shops').last.query;
    expect(shops['radius_m'], '5000');
    expect(find.text('Chez Afi'), findsOneWidget);
    // Pas de filtres propres aux produits.
    expect(find.text('Prix'), findsNothing);
    await tester.tap(find.text('Chez Afi'));
    await tester.pumpAndSettle();
    expect(find.byType(ShopScreen), findsOneWidget);
  });

  testWidgets('quartier : puce du quartier, pas de distance ni de rayon', (
    tester,
  ) async {
    app.location.next = const LocationResult.failed(LocationFailure.denied);
    await BuyerHarness.resetStorage(prefs: {'buyer_area': 'n|$beId|Bè'});
    await openSearch(tester);
    final query = app.searches('/v1/search/products').last.query;
    expect(query['neighborhood_id'], beId);
    expect(query.containsKey('radius_m'), isFalse);
    expect(find.text('Bè'), findsWidgets);
    expect(find.text('Pagne wax 6 yards'), findsOneWidget);
    await tapText(tester, 'Trier : pertinence');
    expect(find.text('Distance'), findsNothing);
  });

  testWidgets('trop de recherches : message du serveur', (tester) async {
    await openSearch(tester);
    app.search.failures['GET /v1/search/products'] = FakeResponse.error(
      429,
      'rate_limited',
      'Trop de recherches. Patientez un instant.',
    );
    await type(tester, 'riz');
    await tester.pump(searchDelay);
    await tester.pumpAndSettle();
    expect(
      find.text('Trop de recherches. Patientez un instant.'),
      findsOneWidget,
    );
    await tapText(tester, 'Réessayer');
    expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
  });

  testWidgets('défilement : la page suivante se charge', (tester) async {
    for (var i = 0; i < 25; i++) {
      app.search.product(afi, 'Article ${i.toString().padLeft(2, '0')}');
    }
    await openSearch(tester);
    await tester.scrollUntilVisible(
      find.text('Article 00'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(products().where((r) => r.query['offset'] == '20'), isNotEmpty);
  });

  testWidgets('depuis l\'accueil : catégorie appliquée', (tester) async {
    await app.launch(tester);
    await tester.tap(find.text('Alimentation'));
    await tester.pumpAndSettle();
    expect(
      products().last.query['category_id'],
      'c1000000-0000-4000-8000-000000000001',
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Alimentation')),
      isSemantics(isSelected: true, isButton: true),
    );
  });

  testWidgets('police à 200 % sur 320 dp : recherche sans débordement', (
    tester,
  ) async {
    smallScreenLargeFont(tester);
    await openSearch(tester);
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Boutiques');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tri par prix puis onglet Boutiques : pertinence, résultats', (
    tester,
  ) async {
    await openSearch(tester);
    await tapText(tester, 'Trier : pertinence');
    await tapText(tester, 'Prix croissant');
    await tapText(tester, 'Boutiques');
    final shops = app.searches('/v1/search/shops').last;
    expect(shops.query['sort'], 'relevance');
    expect(find.text('Chez Afi'), findsOneWidget);
    expect(find.text('Trier : pertinence'), findsOneWidget);
    // Retour aux produits : le tri par prix est retrouvé.
    await tapText(tester, 'Produits');
    expect(products().last.query['sort'], 'price_asc');
  });

  testWidgets('réseau coupé : message et « Réessayer »', (tester) async {
    await openSearch(tester);
    app.search.failures['GET /v1/search/products'] =
        FakeResponse.networkError();
    await type(tester, 'riz');
    await tester.pump(searchDelay);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Impossible de charger les résultats. Vérifiez votre connexion.',
      ),
      findsOneWidget,
    );
    await tapText(tester, 'Réessayer');
    expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
  });

  testWidgets('boutique qui suspend ses commandes : signalée', (tester) async {
    app.search.shop('Pharma Bè', acceptingOrders: false);
    await openSearch(tester);
    await tapText(tester, 'Boutiques');
    expect(find.text('Commandes suspendues'), findsOneWidget);
  });

  testWidgets('page en retard après un changement de recherche : ignorée', (
    tester,
  ) async {
    for (var i = 0; i < 25; i++) {
      app.search.product(afi, 'Article ${i.toString().padLeft(2, '0')}');
    }
    await openSearch(tester);
    final slow = Completer<void>();
    app.search.beforeSearch = (r) async {
      if (r.query['offset'] == '20') await slow.future;
    };
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(products().where((r) => r.query['offset'] == '20'), hasLength(1));
    // Nouvelle recherche pendant l'attente (champ en haut de la liste).
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 6000));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await type(tester, 'riz');
    await tester.pump(searchDelay);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    slow.complete();
    await tester.pumpAndSettle();
    expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
    expect(find.textContaining('Article'), findsNothing);
  });

  testWidgets('texte collé de plus de 100 caractères : tronqué', (
    tester,
  ) async {
    await openSearch(tester);
    await type(tester, 'a' * 120);
    await tester.pump(searchDelay);
    await tester.pumpAndSettle();
    expect(products().last.query['q'], 'a' * 100);
  });

  testWidgets('depuis le champ de l\'accueil : le champ prend le focus', (
    tester,
  ) async {
    await app.launch(tester);
    await tester.tap(
      find.bySemanticsLabel('Rechercher un produit ou une boutique'),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(IviaSearchField),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.focusNode.hasFocus, isTrue);
  });

  testWidgets('frappe en attente puis puce de l\'accueil : texte abandonné', (
    tester,
  ) async {
    await openSearch(tester);
    await type(tester, 'riz');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(
      find.descendant(
        of: find.byType(IviaBottomNav),
        matching: find.byIcon(Icons.home_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alimentation'));
    await tester.pumpAndSettle();
    await tester.pump(searchDelay);
    await tester.pumpAndSettle();
    expect(products().last.query.containsKey('q'), isFalse);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byType(IviaSearchField),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      isEmpty,
    );
  });
}
