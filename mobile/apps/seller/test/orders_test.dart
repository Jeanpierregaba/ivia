import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_seller/app/device_services.dart';
import 'package:ivia_seller/app/identity.dart';
import 'package:ivia_seller/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoLocation implements LocationService {
  @override
  Future<bool> openSettings() async => true;

  @override
  Future<LocationResult> current() async =>
      const LocationResult.found(GeoPoint(lat: 6.1375, lng: 1.2123));
}

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
}

class _NoPicker implements PhotoPicker {
  @override
  Future<Uint8List?> pick({
    PhotoSource source = PhotoSource.gallery,
    int maxSide = 1024,
  }) async => null;
}
