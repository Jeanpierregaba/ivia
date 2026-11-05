import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_buyer/app/buyer_area.dart';
import 'package:ivia_buyer/app/identity.dart';
import 'package:ivia_buyer/features/payment/payment_providers.dart';
import 'package:ivia_buyer/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Position de « Chez Afi » (Tokoin).
const lomeTokoin = GeoPoint(lat: 6.1375, lng: 1.2123);

/// Position simulée du téléphone.
class FakeLocation implements LocationService {
  var settingsOpened = 0;

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }

  LocationResult next = const LocationResult.found(lomeTokoin);
  var calls = 0;

  @override
  Future<LocationResult> current() async {
    calls++;
    return next;
  }
}

/// App acheteur connectée (Awa, profil complet), recherche, panier,
/// commandes et paiements en mémoire.
class BuyerHarness {
  BuyerHarness() {
    server = FakeApiServer()
      ..on(
        'GET',
        '/v1/me',
        (_) => FakeResponse.json(200, userBody(complete: true)),
      )
      ..on('POST', '/v1/auth/logout', (_) => FakeResponse.json(204, null));
    search = FakeSearch(server);
    cart = FakeCart(search);
    orders = FakeOrders(cart);
    payments = FakePayments(orders);
  }

  late final FakeApiServer server;
  late final FakeSearch search;
  late final FakeCart cart;
  late final FakeOrders orders;
  late final FakePayments payments;
  final location = FakeLocation();

  /// Surcharges propres à un test (navigateur externe, hasard…).
  final overrides = <Override>[];

  /// Boutons de simulation du paiement (`IVIA_DEV_PAYMENT`).
  var devPayments = false;

  /// Avant chaque test : stockage vide, session ouverte.
  static Future<void> resetStorage({
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({'onboarding_seen': true, ...prefs});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionStore().save(
      'jeton-secret',
      User.fromJson(userBody(complete: true)),
    );
  }

  Future<void> launch(WidgetTester tester) async {
    // Accueil A01 plus haut que l'écran de test par défaut (800 × 600) :
    // écran de téléphone haut, sauf si le test a choisi sa taille.
    if (tester.view.physicalSize == const Size(2400, 1800)) {
      tester.view.physicalSize = const Size(2400, 7200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }
    final onboarding = await OnboardingStore.open();
    final area = await AreaStore.open();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides,
          onboardingStoreProvider.overrideWithValue(onboarding),
          areaStoreProvider.overrideWithValue(area),
          locationServiceProvider.overrideWithValue(location),
          appIdentityProvider.overrideWithValue(buyerIdentity),
          devPaymentsProvider.overrideWithValue(devPayments),
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
        ],
        child: const BuyerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Requêtes de recherche envoyées à [path].
  Iterable<RecordedRequest> searches(String path) =>
      server.requests.where((r) => r.method == 'GET' && r.path == path);

  /// Conteneur des providers de l'app.
  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// Fait défiler jusqu'au texte puis appuie, clavier fermé.
Future<void> tapText(WidgetTester tester, String text) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final target = find.text(text, skipOffstage: false).last;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Petit écran, police agrandie (remis à zéro à la fin du test).
void smallScreenLargeFont(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}
