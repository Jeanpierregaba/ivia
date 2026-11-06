import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_app_core/testing.dart';
import 'package:ivia_pharmacy/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _title = 'Les alertes de votre quartier';

void main() {
  late FakeApiServer server;
  late FakeLocationService location;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    location = FakeLocationService(state: LocationAccess.askable);
    server = FakeApiServer();
  });

  Future<void> launchApp(WidgetTester tester) async {
    final locationPrompt = await LocationPromptStore.open(location);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appIdentityProvider.overrideWithValue(pharmacyIdentity),
          locationServiceProvider.overrideWithValue(location),
          locationPromptStoreProvider.overrideWithValue(locationPrompt),
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
        child: const PharmacyApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text);
    // Liste longue : l'élément n'est construit qu'en s'en approchant.
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  group('lancement (030)', () {
    testWidgets('écran de localisation après le splash, puis connexion', (
      tester,
    ) async {
      await launchApp(tester);
      expect(find.text('Pharmacie'), findsOneWidget);
      expect(find.text(_title, findRichText: true), findsOneWidget);
      await tapText(tester, "Saisir l'adresse");
      expect(find.text('Espace pharmacie'), findsOneWidget);
      expect(location.requests, 0);

      // Relancée : plus d'écran.
      await launchApp(tester);
      expect(find.text(_title, findRichText: true), findsNothing);
      expect(find.text('Espace pharmacie'), findsOneWidget);
    });

    testWidgets('« Autoriser » : fenêtre du système, puis connexion', (
      tester,
    ) async {
      await launchApp(tester);
      await tapText(tester, 'Autoriser la localisation');
      expect(location.requests, 1);
      expect(find.text('Espace pharmacie'), findsOneWidget);
    });

    testWidgets('position déjà autorisée : connexion directement', (
      tester,
    ) async {
      location.state = LocationAccess.granted;
      await launchApp(tester);
      expect(find.text(_title, findRichText: true), findsNothing);
      expect(find.text('Espace pharmacie'), findsOneWidget);
    });
  });

  group('dossier de la pharmacie', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({'location_prompt_done': true});
      await SessionStore().save(
        'jeton-secret',
        User.fromJson(userBody(complete: true)),
      );
      server
        ..on(
          'GET',
          '/v1/me',
          (_) => FakeResponse.json(200, userBody(complete: true)),
        )
        ..on(
          'GET',
          '/v1/pharmacy/me',
          (_) => FakeResponse.error(404, 'not_found', 'Introuvable.'),
        )
        ..on(
          'GET',
          '/v1/geo/reverse',
          (_) => FakeResponse.json(200, {'label': 'Tokoin'}),
        )
        ..on(
          'GET',
          '/v1/geo/my-places',
          (_) => FakeResponse.json(200, {'items': <Object>[]}),
        )
        ..on(
          'POST',
          '/v1/pharmacy/application',
          (_) => FakeResponse.error(
            400,
            'validation_failed',
            'Données invalides.',
            fields: {'name': 'Saisissez le nom de la pharmacie.'},
          ),
        );
    });

    for (final allow in [false, true]) {
      testWidgets('carte sans autorisation : écran, puis '
          '${allow ? 'position du téléphone' : 'repère placé à la main'}', (
        tester,
      ) async {
        await launchApp(tester);
        await tapText(tester, 'Placer sur la carte');
        expect(find.text(_title, findRichText: true), findsOneWidget);
        await tapText(
          tester,
          allow ? 'Autoriser la localisation' : "Saisir l'adresse",
        );
        expect(find.text(_title, findRichText: true), findsNothing);
        expect(location.requests, allow ? 1 : 0);
        await tapText(tester, 'Confirmer cet emplacement');
        final sent =
            server.calls('POST', '/v1/pharmacy/application').single.body
                as Map<String, dynamic>;
        if (allow) {
          expect(sent['location'], {'lat': 6.1375, 'lng': 1.2123});
        } else {
          expect(sent['location'], isNotNull);
        }
      });
    }
  });
}
