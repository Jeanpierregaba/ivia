import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart' show formatXof;
import 'package:ivia_buyer/features/cart/cart_screen.dart';
import 'package:ivia_buyer/features/product/product_screen.dart';
import 'package:ivia_buyer/features/promo/promo_overlay.dart';
import 'package:ivia_buyer/features/promo/promo_state.dart';

import 'support/buyer_app.dart';

ProductHit hit(String id, {int? rank}) => ProductHit(
  id: id,
  shopId: 's',
  name: id,
  priceXof: 500,
  parcelSize: ParcelSize.small,
  shopName: 'S',
  neighborhoodId: null,
  imageUrl: null,
  inStock: true,
  distanceM: null,
  featuredRank: rank,
);

PromoVisual visual(String id, {int weight = 1, int priority = 0}) =>
    PromoVisual(
      id: id,
      title: id,
      imageUrl: '',
      placements: const [PromoPlacement.modal],
      weight: weight,
      priority: priority,
    );

void main() {
  group('rotation et listes', () {
    test('un produit vedette toutes les N cartes, chacun une fois', () {
      final items = [for (var i = 0; i < 9; i++) hit('p$i')];
      final out = interleaveFeatured(items, [
        hit('ivi1', rank: 1),
        hit('ivi2', rank: 2),
        hit('p3'), // déjà dans la liste : pas de doublon
      ], every: 4);
      expect(out.map((h) => h.id).toList(), [
        'ivi1',
        'p0',
        'p1',
        'p2',
        'p3',
        'ivi2',
        'p4',
        'p5',
        'p6',
        'p7',
        'p8',
      ]);
      expect(interleaveFeatured(items, const [], every: 4), same(items));
    });

    test('rotation : priorité, pondérée, sans répéter le dernier', () {
      final a = visual('a', weight: 1, priority: 10);
      final b = visual('b', weight: 99, priority: 90);
      final r = Random(1);
      expect(pickVisual([a, b], PromoRotation.priority, r)!.id, 'b');
      expect(
        pickVisual([a, b], PromoRotation.priority, r, lastId: 'b')!.id,
        'a',
      );
      final picks = [
        for (var i = 0; i < 200; i++)
          pickVisual([a, b], PromoRotation.weighted, r)!.id,
      ];
      expect(picks.where((id) => id == 'b').length, greaterThan(180));
      expect(pickVisual([a], PromoRotation.random, r, lastId: 'a')!.id, 'a');
      expect(pickVisual(const [], PromoRotation.random, r), isNull);
    });
  });

  group('app acheteur', () {
    late BuyerHarness app;
    late FakePromo promo;
    late Map<String, dynamic> awu;
    final opened = <Uri>[];

    setUp(() async {
      await BuyerHarness.resetStorage();
      app = BuyerHarness();
      promo = FakePromo(app.server);
      opened.clear();
      app.overrides.addAll([
        linkOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
        promoRandomProvider.overrideWithValue(Random(7)),
      ]);
      final ivi = app.search.shop('IVI — Eau minérale naturelle');
      final afi = app.search.shop('Chez Afi');
      app.search.product(afi, 'Riz parfumé 5 kg');
      awu = app.search.product(ivi, 'AWU IVI 1,5 L', price: 500)
        ..addAll({
          'promo_price_xof': 400,
          'promo_active': true,
          'effective_price_xof': 400,
          'badges': ['promotion', 'featured'],
          'featured_rank': 1,
          'features': ['Eau minérale naturelle', 'Au goût agréable'],
        });
      promo.featured.add(awu);
    });

    testWidgets('accueil : carrousel, produits vedettes, prix promotionnel', (
      tester,
    ) async {
      promo
        ..visual('La gamme IVI', product: awu)
        ..visual('AWU IVI 0,5 L');
      promo.settings['modal_enabled'] = false;
      promo.settings['interstitial_enabled'] = false;
      await app.launch(tester);

      expect(find.text('Publicité'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Produits vedettes'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      // Prix promotionnel, prix normal barré, badge.
      expect(find.text(formatXof(400), skipOffstage: false), findsWidgets);
      expect(find.text(formatXof(500), skipOffstage: false), findsWidgets);
      expect(find.text('Promotion', skipOffstage: false), findsWidgets);

      // Fiche : promotion et caractéristiques.
      await tester.tap(find.text('AWU IVI 1,5 L').first);
      await tester.pumpAndSettle();
      expect(find.byType(ProductScreen), findsOneWidget);
      expect(find.text('Au goût agréable'), findsOneWidget);
      expect(find.text('Ajouter · ${formatXof(400)}'), findsOneWidget);

      // Statistiques envoyées par lot, anonymes.
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(promo.of('impression'), isNotEmpty);
      expect(promo.of('click_product').single['product_id'], awu['id']);
      expect(promo.sessions.single.length, greaterThanOrEqualTo(8));
    });

    testWidgets(
      'fenêtre après le délai : « Commander maintenant » passe par le panier',
      (tester) async {
        promo
          ..settings['first_delay_seconds'] = 10
          ..settings['max_per_session'] = 1
          ..visual(
            'Hydratez-vous, vivez mieux !',
            kind: 'modal',
            placements: const ['modal'],
            product: awu,
          );
        await app.launch(tester);
        expect(find.byType(PromoAdView), findsNothing);

        await tester.pump(PromoHost.tick);
        await tester.pumpAndSettle();
        expect(find.byType(PromoAdView), findsNothing, reason: 'trop tôt');

        await tester.pump(PromoHost.tick);
        await tester.pumpAndSettle();
        expect(find.byType(PromoAdView), findsOneWidget);
        expect(find.text('Découvrir le produit'), findsOneWidget);
        expect(find.text('Visiter le site officiel IVI'), findsOneWidget);

        await tester.ensureVisible(find.text('Commander maintenant'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Commander maintenant'));
        await tester.pumpAndSettle();
        expect(find.byType(CartScreen), findsOneWidget);
        expect(app.cart.lines[awu['id']], 1);

        // Plafond atteint : plus de fenêtre, même longtemps après.
        Navigator.of(tester.element(find.byType(CartScreen))).pop();
        await tester.pumpAndSettle();
        for (var i = 0; i < 40; i++) {
          await tester.pump(PromoHost.tick);
        }
        await tester.pumpAndSettle();
        expect(find.byType(PromoAdView), findsNothing);
        expect(promo.of('click_order'), hasLength(1));
        expect(promo.of('dismiss'), isEmpty);
      },
    );

    testWidgets('interstitiel fermable ; site officiel dans le navigateur', (
      tester,
    ) async {
      promo
        ..settings['first_delay_seconds'] = 0
        ..settings['min_interval_seconds'] = 15
        ..settings['max_per_session'] = 2
        ..visual(
          'Le choix naturel pour une vie meilleure',
          kind: 'interstitial',
          placements: const ['interstitial'],
        );
      await app.launch(tester);

      await tester.pump(PromoHost.tick);
      await tester.pumpAndSettle();
      expect(find.byType(PromoAdView), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Fermer la publicité').last);
      await tester.pumpAndSettle();
      expect(find.byType(PromoAdView), findsNothing);

      // Intervalle minimal respecté avant la suivante.
      await tester.pump(PromoHost.tick);
      await tester.pumpAndSettle();
      expect(find.byType(PromoAdView), findsNothing);
      for (var i = 0; i < 3; i++) {
        await tester.pump(PromoHost.tick);
      }
      await tester.pumpAndSettle();
      expect(find.byType(PromoAdView), findsOneWidget);
      await tester.ensureVisible(find.text('Visiter le site officiel IVI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visiter le site officiel IVI'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'https://www.eaumineraleivi.com');

      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(promo.of('dismiss'), hasLength(1));
      expect(promo.of('click_site'), hasLength(1));
    });

    testWidgets('publicité coupée par l’admin : rien ne s’affiche', (
      tester,
    ) async {
      promo
        ..settings['enabled'] = false
        ..settings['first_delay_seconds'] = 0
        ..visual('IVI', placements: const ['home_hero', 'modal']);
      await app.launch(tester);
      for (var i = 0; i < 4; i++) {
        await tester.pump(PromoHost.tick);
      }
      await tester.pumpAndSettle();
      expect(find.byType(PromoAdView), findsNothing);
      expect(find.text('Produits vedettes'), findsNothing);
      expect(find.text('Publicité'), findsNothing);
    });
  });
}
