import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_buyer/features/home/shop_card.dart';
import 'package:ivia_buyer/features/product/product_screen.dart';
import 'package:ivia_buyer/features/search/search_state.dart';
import 'package:ivia_buyer/features/shop/shop_screen.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'support/buyer_app.dart';

void main() {
  late BuyerHarness app;

  setUp(() async {
    await BuyerHarness.resetStorage();
    app = BuyerHarness();
    final afi = app.search.shop(
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
      ..product(wax, 'Pagne wax 6 yards', price: 12000);
  });

  testWidgets('position autorisée : boutiques proches avec distance', (
    tester,
  ) async {
    await app.launch(tester);
    expect(find.textContaining('Bonjour Awa'), findsOneWidget);
    expect(find.text('Ma position'), findsOneWidget);
    // Aucune recherche sans zone avant la position.
    expect(
      app.searches('/v1/search/shops').every((r) => r.query['lat'] != null),
      isTrue,
    );
    final shops = app.searches('/v1/search/shops').last.query;
    // Position arrondie à 3 décimales avant l'envoi (ADR 0010).
    expect(shops['lat'], lomeTokoin.lat.toStringAsFixed(3));
    expect(shops['radius_m'], '5000');
    expect(shops['sort'], 'distance');
    // Plus proche d'abord ; quartier et distance.
    expect(find.text('Chez Afi'), findsOneWidget);
    // Distance du serveur, depuis la position arrondie.
    expect(find.textContaining('Tokoin · 280'), findsOneWidget);
    final afi = tester.getTopLeft(find.text('Chez Afi'));
    final wax = tester.getTopLeft(find.text('Wax & Co'));
    expect(afi.dx, lessThan(wax.dx));
    // Nouveautés, plus bas.
    await tester.scrollUntilVisible(
      find.text('Pagne wax 6 yards'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
  });

  testWidgets(
    'position refusée : quartier choisi, gardé au lancement suivant',
    (tester) async {
      app.location.next = const LocationResult.failed(LocationFailure.denied);
      await app.launch(tester);
      expect(
        find.text('Position non autorisée. Choisissez votre quartier.'),
        findsOneWidget,
      );
      await tapText(tester, 'Choisir mon quartier');
      await tester.tap(find.widgetWithText(ListTile, 'Bè'));
      await tester.pumpAndSettle();
      // En-tête : en haut de l'accueil.
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, 2000),
        3000,
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Zone de recherche : Bè. Changer'),
        findsOneWidget,
      );
      final shops = app.searches('/v1/search/shops').last.query;
      expect(shops['neighborhood_id'], beId);
      expect(shops.containsKey('lat'), isFalse);
      expect(
        find.descendant(
          of: find.byType(ShopCard),
          matching: find.text('Wax & Co'),
        ),
        findsOneWidget,
      );
      expect(find.text('Chez Afi'), findsNothing);
      expect(
        // Espace insécable avant l'unité (formatDistance).
        find.textContaining(RegExp('\u00A0(m|km)\\b')),
        findsNothing,
        reason: 'aucune distance',
      );

      // Relance : quartier retrouvé, position pas redemandée.
      final calls = app.location.calls;
      await app.launch(tester);
      expect(
        find.bySemanticsLabel('Zone de recherche : Bè. Changer'),
        findsOneWidget,
      );
      expect(app.location.calls, calls);
    },
  );

  testWidgets('« Utiliser ma position » depuis la feuille', (tester) async {
    app.location.next = const LocationResult.failed(
      LocationFailure.unavailable,
    );
    await app.launch(tester);
    app.location.next = const LocationResult.found(lomeTokoin);
    await tester.tap(find.bySemanticsLabel(RegExp('^Zone de recherche')));
    await tester.pumpAndSettle();
    await tapText(tester, 'Utiliser ma position');
    expect(find.text('Ma position'), findsOneWidget);
    expect(app.searches('/v1/search/shops').last.query['lat'], isNotNull);
  });

  testWidgets('champ, catégorie et « Voir tout » ouvrent l\'onglet Recherche', (
    tester,
  ) async {
    await app.launch(tester);
    final container = app.container(tester);
    await tester.tap(
      find.bySemanticsLabel('Rechercher un produit ou une boutique'),
    );
    await tester.pumpAndSettle();
    expect(container.read(searchFocusRequestProvider), 1);
    expect(
      tester.getSemantics(
        find.descendant(
          of: find.byType(IviaBottomNav),
          matching: find.bySemanticsLabel('Recherche'),
        ),
      ),
      isSemantics(isSelected: true, isButton: true),
    );

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(IviaChip, 'Alimentation'));
    await tester.pumpAndSettle();
    expect(
      container.read(searchFiltersProvider).categoryId,
      'c1000000-0000-4000-8000-000000000001',
    );

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsLabel('Voir tout : Boutiques près de vous'),
    );
    await tester.pumpAndSettle();
    final filters = container.read(searchFiltersProvider);
    expect(filters.tab, SearchTab.shops);
    expect(filters.categoryId, isNull, reason: 'nouvelle recherche');
  });

  testWidgets('cartes : fiche boutique et fiche produit', (tester) async {
    await app.launch(tester);
    await tester.tap(find.text('Chez Afi'));
    await tester.pumpAndSettle();
    expect(find.byType(ShopScreen), findsOneWidget);
    GoRouter.of(tester.element(find.byType(ShopScreen))).pop();
    await tester.pumpAndSettle();
    await tapText(tester, 'Riz parfumé 5 kg');
    expect(find.byType(ProductScreen), findsOneWidget);
  });

  testWidgets('aucune boutique : messages des sections vides', (tester) async {
    app.search.shops.clear();
    app.search.products.clear();
    await app.launch(tester);
    expect(
      find.text('Aucune boutique autour de vous pour l’instant.'),
      findsOneWidget,
    );
    expect(
      find.text('Aucun produit autour de vous pour l’instant.'),
      findsOneWidget,
    );
  });

  testWidgets('section en erreur : « Réessayer » ; actualisation en échec', (
    tester,
  ) async {
    app.search.failures['GET /v1/search/shops'] = FakeResponse.networkError();
    await app.launch(tester);
    expect(
      find.text(
        'Impossible de charger cette section. Vérifiez votre connexion.',
      ),
      findsOneWidget,
    );
    await tapText(tester, 'Réessayer');
    expect(find.text('Chez Afi'), findsOneWidget);

    // Actualisation sans réseau : la liste reste, un message le dit.
    app.search.failures['GET /v1/search/shops'] = FakeResponse.networkError();
    // Haut de l'accueil, puis tirer vers le bas.
    await tester.fling(
      find.byType(ListView).first,
      const Offset(0, 2000),
      3000,
    );
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(
      find.text('Accueil non actualisé. Vérifiez votre connexion.'),
      findsOneWidget,
    );
    expect(find.text('Chez Afi'), findsOneWidget);
  });

  testWidgets('police à 200 % sur 320 dp : accueil sans débordement', (
    tester,
  ) async {
    smallScreenLargeFont(tester);
    await app.launch(tester);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Riz parfumé 5 kg'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(IviaProductCard), findsWidgets);
  });

  testWidgets('« Voir tout » boutiques : même rayon, tri par distance', (
    tester,
  ) async {
    await app.launch(tester);
    final home = app.searches('/v1/search/shops').last.query;
    await tester.tap(
      find.bySemanticsLabel('Voir tout : Boutiques près de vous'),
    );
    await tester.pumpAndSettle();
    final all = app.searches('/v1/search/shops').last.query;
    expect(all['radius_m'], home['radius_m']);
    expect(all['sort'], 'distance');
  });

  testWidgets('position refusée définitivement : « Ouvrir les réglages »', (
    tester,
  ) async {
    app.location.state = LocationAccess.deniedForever;
    await app.launch(tester);
    await tapText(tester, 'Ouvrir les réglages');
    expect(app.location.settingsOpened, 1);
  });

  group('autorisation de la localisation (030)', () {
    testWidgets('Accueil sans autorisation : ni écran ni fenêtre du système', (
      tester,
    ) async {
      app.location.state = LocationAccess.askable;
      await app.launch(tester);
      expect(find.byType(LocationPromptScreen), findsNothing);
      expect(app.location.requests, 0);
    });

    for (final allow in [false, true]) {
      testWidgets('« Utiliser ma position » sans autorisation : écran, puis '
          '${allow ? 'position' : 'message'}', (tester) async {
        app.location.state = LocationAccess.askable;
        await app.launch(tester);
        await tester.tap(find.bySemanticsLabel(RegExp('^Zone de recherche')));
        await tester.pumpAndSettle();
        await tapText(tester, 'Utiliser ma position');
        expect(find.byType(LocationPromptScreen), findsOneWidget);
        await tapText(
          tester,
          allow ? 'Autoriser la localisation' : 'Plus tard',
        );
        expect(find.byType(LocationPromptScreen), findsNothing);
        expect(app.location.requests, allow ? 1 : 0);
        if (allow) {
          expect(find.text('Ma position'), findsOneWidget);
        } else {
          expect(
            find.text('Position non autorisée. Choisissez votre quartier.'),
            findsWidgets,
          );
        }
      });
    }

    testWidgets('« Utiliser ma position » déjà autorisée : pas d\'écran', (
      tester,
    ) async {
      await app.launch(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^Zone de recherche')));
      await tester.pumpAndSettle();
      await tapText(tester, 'Utiliser ma position');
      expect(find.byType(LocationPromptScreen), findsNothing);
      expect(find.text('Ma position'), findsOneWidget);
    });
  });
}
