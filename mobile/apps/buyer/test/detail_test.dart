import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_buyer/app/router.dart';
import 'package:ivia_buyer/features/product/product_screen.dart';
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
  late Map<String, dynamic> riz;

  setUp(() async {
    await BuyerHarness.resetStorage();
    app = BuyerHarness();
    afi = app.search.shop(
      'Chez Afi',
      location: const GeoPoint(lat: 6.1405, lng: 1.2123),
    );
    riz = app.search.product(
      afi,
      'Riz parfumé 5 kg',
      description: 'Riz long grain parfumé, sac de 5 kg.',
      images: 3,
    );
    app.search
      ..product(afi, 'Lait en poudre', stock: 0, price: 2750)
      ..product(afi, 'Sucre 1 kg', stockMode: 'untracked', price: 800);
  });

  Future<void> open(WidgetTester tester, String location) async {
    await app.launch(tester);
    GoRouter.of(tester.element(find.byType(IviaBottomNav))).push(location);
    await tester.pumpAndSettle();
  }

  group('fiche boutique', () {
    testWidgets('en-tête, distance, produits, recherche dans la boutique', (
      tester,
    ) async {
      await open(tester, Routes.shop(afi['id'] as String));
      expect(find.text('Chez Afi'), findsOneWidget);
      expect(find.text('Rue 248, Tokoin'), findsOneWidget);
      expect(find.text('Ouverte'), findsOneWidget);
      expect(textPlain('330 m'), findsOneWidget);
      expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
      expect(find.text('Épuisé'), findsOneWidget);
      expect(find.text('En stock'), findsNWidgets(2));
      final listed = app.searches('/v1/search/products').last.query;
      expect(listed['shop_id'], afi['id']);

      await tester.enterText(find.byType(TextField), 'lait');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      final searched = app.searches('/v1/search/products').last.query;
      expect(searched['shop_id'], afi['id']);
      expect(searched['q'], 'lait');
      expect(find.text('Riz parfumé 5 kg'), findsNothing);

      await tester.tap(find.text('Lait en poudre'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductScreen), findsOneWidget);
    });

    testWidgets('boutique introuvable, puis réseau coupé et « Réessayer »', (
      tester,
    ) async {
      await open(tester, Routes.shop('inconnue'));
      expect(
        find.text('Cette boutique n’est plus disponible.'),
        findsOneWidget,
      );
      expect(find.text('Réessayer'), findsNothing);

      app.search.failures['GET /v1/shops/'] = FakeResponse.networkError();
      GoRouter.of(tester.element(find.byType(ShopScreen)))
          .push(Routes.shop(afi['id'] as String));
      await tester.pumpAndSettle();
      expect(find.textContaining('Vérifiez votre connexion'), findsOneWidget);
      await tapText(tester, 'Réessayer');
      expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
    });

    testWidgets('produits de la boutique : message du serveur', (tester) async {
      await app.launch(tester);
      // Après les recherches de l'accueil.
      app.search.failures['GET /v1/search/products'] = FakeResponse.error(
        429,
        'rate_limited',
        'Trop de recherches. Patientez un instant.',
      );
      GoRouter.of(tester.element(find.byType(IviaBottomNav)))
          .push(Routes.shop(afi['id'] as String));
      await tester.pumpAndSettle();
      expect(
        find.text('Trop de recherches. Patientez un instant.'),
        findsOneWidget,
      );
    });

    testWidgets('commandes suspendues signalées', (tester) async {
      final closed = app.search.shop('Pharma Bè', acceptingOrders: false);
      await open(tester, Routes.shop(closed['id'] as String));
      expect(find.text('Commandes suspendues'), findsOneWidget);
      expect(
        find.text('Aucun produit en vente pour l’instant.'),
        findsOneWidget,
      );
    });
  });

  group('fiche produit', () {
    testWidgets('photos, prix, stock, boutique, colis, « Ajouter »', (
      tester,
    ) async {
      await open(tester, Routes.product(riz['id'] as String));
      expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
      expect(textPlain('4 500 F'), findsOneWidget);
      expect(find.text('En stock · 12 disponibles'), findsOneWidget);
      expect(find.bySemanticsLabel('Photo 1 sur 3'), findsOneWidget);
      expect(find.text('Riz long grain parfumé, sac de 5 kg.'), findsOneWidget);
      expect(find.text('Alimentation'), findsOneWidget);
      expect(find.text('Colis moyen · moto'), findsOneWidget);
      expect(textPlain('Tokoin · 330 m · Ouverte'), findsOneWidget);

      await tester.tap(find.byTooltip('Ajouter 1'));
      await tester.pump();
      expect(textPlain('Ajouter · 9 000 F'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.text('Le panier arrive bientôt.'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(RegExp('^Boutique Chez Afi')));
      await tester.pumpAndSettle();
      expect(find.byType(ShopScreen), findsOneWidget);
    });

    testWidgets('épuisé : bouton désactivé ; stock non suivi : disponible', (
      tester,
    ) async {
      final lait = app.search.products[1]['id'] as String;
      await open(tester, Routes.product(lait));
      expect(find.text('Épuisé'), findsWidgets);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(find.byType(IviaQuantityStepper), findsNothing);

      final sucre = app.search.products[2]['id'] as String;
      GoRouter.of(tester.element(find.byType(ProductScreen)))
          .push(Routes.product(sucre));
      await tester.pumpAndSettle();
      expect(find.text('Disponible'), findsOneWidget);
    });

    testWidgets('produit retiré : plus disponible', (tester) async {
      await open(tester, Routes.product('retire'));
      expect(find.text('Ce produit n’est plus disponible.'), findsOneWidget);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductScreen), findsNothing);
    });

    testWidgets('police à 200 % sur 320 dp : fiches sans débordement', (
      tester,
    ) async {
      smallScreenLargeFont(tester);
      await open(tester, Routes.product(riz['id'] as String));
      expect(tester.takeException(), isNull);
      GoRouter.of(tester.element(find.byType(ProductScreen)))
          .push(Routes.shop(afi['id'] as String));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
