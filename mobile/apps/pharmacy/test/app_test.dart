import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import 'helpers.dart';

void main() {
  late PharmacyHarness app;

  setUp(() {
    PharmacyHarness.resetDevice();
    app = PharmacyHarness();
  });

  group('lancement (030)', () {
    testWidgets('écran de localisation après le splash, puis connexion', (
      tester,
    ) async {
      await app.launch(tester);
      expect(find.text('Pharmacie'), findsOneWidget);
      expect(find.text(locationTitle, findRichText: true), findsOneWidget);
      await tapText(tester, "Saisir l'adresse");
      expect(find.text('Espace pharmacie'), findsOneWidget);
      expect(app.location.requests, 0);

      // Relancée : plus d'écran.
      await app.launch(tester);
      expect(find.text(locationTitle, findRichText: true), findsNothing);
      expect(find.text('Espace pharmacie'), findsOneWidget);
    });

    testWidgets('« Autoriser » : fenêtre du système, puis connexion', (
      tester,
    ) async {
      await app.launch(tester);
      await tapText(tester, 'Autoriser la localisation');
      expect(app.location.requests, 1);
      expect(find.text('Espace pharmacie'), findsOneWidget);
    });

    testWidgets('position déjà autorisée : connexion directement', (
      tester,
    ) async {
      app.location.state = LocationAccess.granted;
      await app.launch(tester);
      expect(find.text(locationTitle, findRichText: true), findsNothing);
      expect(find.text('Espace pharmacie'), findsOneWidget);
    });
  });

  group('dossier de la pharmacie', () {
    setUp(() async {
      await app.signIn();
      app.server
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
        await app.launch(tester);
        await tapText(tester, 'Placer sur la carte');
        expect(find.text(locationTitle, findRichText: true), findsOneWidget);
        await tapText(
          tester,
          allow ? 'Autoriser la localisation' : "Saisir l'adresse",
        );
        expect(find.text(locationTitle, findRichText: true), findsNothing);
        expect(app.location.requests, allow ? 1 : 0);
        await tapText(tester, 'Confirmer cet emplacement');
        final sent =
            app.server.calls('POST', '/v1/pharmacy/application').single.body
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
