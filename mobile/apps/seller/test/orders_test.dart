import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:ivia_seller/app/device_services.dart';
import 'package:ivia_seller/app/identity.dart';
import 'package:ivia_seller/app/router.dart';
import 'package:ivia_seller/features/orders/order_labels.dart';
import 'package:ivia_seller/features/orders/orders_screen.dart';
import 'package:ivia_seller/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoLocation implements LocationService {
  @override
  Future<bool> openSettings() async => true;

  @override
  Future<LocationResult> current() async =>
      const LocationResult.found(GeoPoint(lat: 6.1375, lng: 1.2123));
}

/// Texte affiché, espaces typographiques remplacés (« 10 500 F »).
Finder textPlain(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? '').replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ') ==
          text,
);

void main() {
  late FakeApiServer server;
  late FakeSellerOrders orders;

  Map<String, dynamic> seller() => {
    ...userBody(complete: true),
    'roles': ['buyer', 'seller'],
  };

  void withShop(String status) => server.on(
    'GET',
    '/v1/seller/shops',
    (_) => FakeResponse.json(200, {
      'items': [shopBody(status: status)],
    }),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding_seen': true});
    FlutterSecureStorage.setMockInitialValues({});
    server = FakeApiServer()
      ..on('GET', '/v1/me', (_) => FakeResponse.json(200, seller()))
      ..on('POST', '/v1/auth/logout', (_) => FakeResponse.json(204, null));
    withShop('published');
    FakeCatalog(server);
    orders = FakeSellerOrders(server);
    await SessionStore().save('jeton-secret', User.fromJson(seller()));
  });

  Future<void> launch(WidgetTester tester) async {
    final store = await OnboardingStore.open();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(store),
          appIdentityProvider.overrideWithValue(sellerIdentity),
          apiClientProvider.overrideWithValue(
            IviaApiClient(
              config: ApiConfig(baseUrl: Uri.parse('http://api.test')),
              adapter: server,
            ),
          ),
          authTimingsProvider.overrideWithValue(
            const AuthTimings(
              minSplash: Duration.zero,
              meTimeout: Duration(seconds: 1),
            ),
          ),
          photoPickerProvider.overrideWithValue(_NoPicker()),
          locationServiceProvider.overrideWithValue(_NoLocation()),
          mapsEnabledProvider.overrideWithValue(false),
        ],
        child: const SellerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Iterable<RecordedRequest> lists() => server.calls('GET', '/v1/seller/orders');

  void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  group('arrivée des commandes', () {
    testWidgets('lues au lancement, pour la boutique, 100 au plus', (
      tester,
    ) async {
      await launch(tester);
      expect(lists().single.query, {
        'shop_id': shopId,
        'offset': '0',
        'limit': '100',
      });
    });

    testWidgets('nouvelle commande : visible 30 s après, pastille', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await launch(tester);
      expect(find.bySemanticsLabel('Commandes'), findsOneWidget);

      orders.add();
      await tester.pump(const Duration(seconds: 29));
      expect(lists(), hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(lists(), hasLength(2));
      expect(find.bySemanticsLabel('Commandes, 1 nouvelle'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      orders.add();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Commandes, 2 nouvelles'), findsOneWidget);

      // Acceptée ailleurs : plus nouvelle, pastille retirée au passage
      // suivant.
      for (final o in orders.orders) {
        o['status'] = 'accepted';
      }
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Commandes'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('arrière-plan : aucune requête ; au retour, relue aussitôt', (
      tester,
    ) async {
      await launch(tester);
      lifecycle(tester, const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      await tester.pump(const Duration(minutes: 2));
      expect(lists(), hasLength(1));

      orders.add();
      lifecycle(tester, const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await tester.pumpAndSettle();
      expect(lists(), hasLength(2));
      expect(find.text('1'), findsOneWidget);

      // Puis de nouveau toutes les 30 s.
      await tester.pump(const Duration(seconds: 30));
      expect(lists(), hasLength(3));
    });

    testWidgets('relecture en échec : la pastille reste, sans message', (
      tester,
    ) async {
      orders.add();
      await launch(tester);
      expect(find.text('1'), findsOneWidget);
      orders.failures['GET /v1/seller/orders'] = FakeResponse.networkError();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('boutique en validation : aucune lecture des commandes', (
      tester,
    ) async {
      withShop('pending_review');
      await launch(tester);
      await tester.pump(const Duration(minutes: 1));
      expect(lists(), isEmpty);
    });

    testWidgets('boutique suspendue entre-temps : écran « suspendue »', (
      tester,
    ) async {
      await launch(tester);
      orders.shopSuspended = true;
      withShop('suspended');
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.textContaining('suspendue'), findsWidgets);
      expect(find.bySemanticsLabel('Commandes'), findsNothing);
    });
  });

  /// Ouvre l'onglet Commandes de la barre du bas.
  Future<void> openOrders(WidgetTester tester) async {
    await launch(tester);
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.textContaining(label).first);
    await tester.pumpAndSettle();
  }

  /// Titres des lignes, dans l'ordre de l'écran.
  List<String> rows(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(
        of: find.byType(OrderRow),
        matching: find.textContaining(RegExp(r'^#\d+')),
      ),
    ))
      t.data!,
  ];

  group('onglet Commandes', () {
    testWidgets('répartition, ordre, compteurs, compte à rebours', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      orders
        ..add(buyerFirstName: 'Ama', paidAgo: const Duration(minutes: 2))
        ..add(buyerFirstName: 'Yao', paidAgo: const Duration(minutes: 10))
        ..add(status: 'accepted', buyerFirstName: 'Kossi')
        ..add(status: 'ready_for_pickup', buyerFirstName: 'Efua')
        ..add(status: 'completed', buyerFirstName: 'Abla')
        ..add(
          status: 'cancelled',
          buyerFirstName: 'Kodjo',
          cancelReason: 'Boutique fermée',
        );
      await openOrders(tester);

      expect(find.bySemanticsLabel('Nouvelles, 2'), findsOneWidget);
      expect(find.bySemanticsLabel('En cours, 2'), findsOneWidget);
      // La plus urgente (payée il y a 10 min) en haut.
      expect(rows(tester), ['#1043 · Yao', '#1042 · Ama']);
      expect(find.text('Retrait · 3 articles'), findsNWidgets(2));
      expect(textPlain('10 500 F'), findsNWidgets(2));
      expect(find.text('Nouvelle'), findsNWidgets(2));
      expect(find.text('05:00'), findsOneWidget);
      expect(find.text('13:00'), findsOneWidget);
      expect(find.bySemanticsLabel('Il reste 5 min'), findsOneWidget);

      await openTab(tester, 'En cours');
      // Plus récentes d'abord.
      expect(rows(tester), ['#1045 · Efua', '#1044 · Kossi']);
      expect(find.text('Acceptée'), findsOneWidget);
      expect(find.text('Prête à retirer'), findsOneWidget);
      expect(find.byType(IviaCountdown), findsNothing);

      await openTab(tester, 'Terminées');
      expect(rows(tester), ['#1047 · Kodjo', '#1046 · Abla']);
      expect(find.text('Retirée'), findsOneWidget);
      expect(find.text('Annulée'), findsOneWidget);
      expect(find.textContaining("Aujourd'hui "), findsNWidgets(2));
      semantics.dispose();
    });

    testWidgets('textes vides', (tester) async {
      await openOrders(tester);
      expect(find.text('Aucune nouvelle commande.'), findsOneWidget);
      await openTab(tester, 'En cours');
      expect(find.text('Aucune commande en cours.'), findsOneWidget);
      await openTab(tester, 'Terminées');
      expect(find.text('Aucune commande terminée.'), findsOneWidget);
      expect(find.text('Afficher plus'), findsNothing);
    });

    testWidgets('tirer vers le bas : relue ; échec : message', (tester) async {
      await openOrders(tester);
      orders.add();
      await tester.fling(
        find.text('Aucune nouvelle commande.'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(rows(tester), ['#1042 · Koffi']);

      orders.failures['GET /v1/seller/orders'] = FakeResponse.networkError();
      await tester.fling(
        find.text('#1042 · Koffi'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Commandes non actualisées. Vérifiez votre connexion.'),
        findsOneWidget,
      );
      expect(rows(tester), ['#1042 · Koffi']);
    });

    testWidgets('premier chargement en échec : « Réessayer »', (tester) async {
      orders.failures['GET /v1/seller/orders'] = FakeResponse.networkError();
      await openOrders(tester);
      expect(find.textContaining('Impossible de charger'), findsOneWidget);
      orders.add();
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(rows(tester), ['#1042 · Koffi']);
    });

    testWidgets('Terminées : « Afficher plus » ajoute la suite', (
      tester,
    ) async {
      // Au-delà de 50 Ko, dio décode la réponse dans un isolat, qui ne
      // tourne pas dans le temps simulé du test : on lui laisse du temps réel.
      Future<void> settle() async {
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }

      for (var i = 0; i < 103; i++) {
        orders.add(status: 'completed');
      }
      await launch(tester);
      await settle();
      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await settle();
      await openTab(tester, 'Terminées');
      expect(find.byType(OrderRow, skipOffstage: false), findsNWidgets(100));
      await tester.scrollUntilVisible(
        find.text('Afficher plus'),
        2000,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Afficher plus'));
      await settle();
      expect(lists().last.query['offset'], '100');
      expect(find.byType(OrderRow, skipOffstage: false), findsNWidgets(103));
      expect(find.text('Afficher plus', skipOffstage: false), findsNothing);

      // Relecture suivante : la suite reste affichée.
      await tester.pump(const Duration(seconds: 30));
      await settle();
      expect(find.byType(OrderRow, skipOffstage: false), findsNWidgets(103));
    });

    testWidgets('lien ?tab=active : onglet En cours', (tester) async {
      orders.add(status: 'preparing');
      await launch(tester);
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go(Routes.ordersTab(OrderTab.active));
      await tester.pumpAndSettle();
      expect(rows(tester), ['#1042 · Koffi']);
      expect(find.text('En préparation'), findsOneWidget);
    });
  });
}

class _NoPicker implements PhotoPicker {
  @override
  Future<Uint8List?> pick({
    PhotoSource source = PhotoSource.gallery,
    int maxSide = 1024,
  }) async => null;
}
