import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_app_core/testing.dart';
import 'package:ivia_ui/ivia_ui.dart';

const _identity = AppIdentity(
  brand: IviaAppBrand.pharmacy,
  loginTitle: 'Espace pharmacie',
  loginBody: 'Connexion',
  codeHint: _hint,
  locationPrompt: LocationPromptCopy(
    space: 'Pharmacie',
    center: Icons.local_pharmacy,
    satellites: [Icons.person, Icons.person, Icons.person, Icons.person],
    title: 'Les alertes',
    titleAccent: 'de votre quartier',
    body: 'Activez la localisation pour recevoir les demandes proches.',
  ),
);

String _hint(Duration d) => '';

void main() {
  late FakeApiServer server;
  late FakeLocationService location;

  setUp(() {
    server = FakeApiServer()
      ..on(
        'GET',
        '/v1/geo/reverse',
        (_) => FakeResponse.json(200, {'label': 'Tokoin'}),
      )
      ..on(
        'GET',
        '/v1/geo/my-places',
        (_) => FakeResponse.json(200, {'items': <Object>[]}),
      );
    location = FakeLocationService(state: LocationAccess.askable);
  });

  Future<void> openPicker(WidgetTester tester, {GeoPoint? initial}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appIdentityProvider.overrideWithValue(_identity),
          locationServiceProvider.overrideWithValue(location),
          apiClientProvider.overrideWithValue(
            IviaApiClient(
              config: ApiConfig(baseUrl: Uri.parse('http://api.test')),
              adapter: server,
            ),
          ),
        ],
        child: MaterialApp(
          theme: IviaTheme.light(),
          home: PlacePickerScreen(initial: initial),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('PlacePickerScreen et autorisation (030)', () {
    testWidgets('sans autorisation : écran, « Plus tard » sans demande', (
      tester,
    ) async {
      await openPicker(tester);
      expect(
        find.text('Les alertes de votre quartier', findRichText: true),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Plus tard'));
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();
      expect(find.text('Plus tard'), findsNothing);
      expect(find.text('Confirmer ce lieu'), findsOneWidget);
      expect(location.requests, 0);
    });

    testWidgets('« Autoriser » : demande au système, puis position lue', (
      tester,
    ) async {
      await openPicker(tester);
      await tester.ensureVisible(find.text('Autoriser la localisation'));
      await tester.tap(find.text('Autoriser la localisation'));
      await tester.pumpAndSettle();
      expect(location.requests, 1);
      expect(location.calls, greaterThan(0));
      expect(find.text('Confirmer ce lieu'), findsOneWidget);
    });

    testWidgets('position déjà autorisée : pas d\'écran', (tester) async {
      location.state = LocationAccess.granted;
      await openPicker(tester);
      expect(find.text('Plus tard'), findsNothing);
      expect(location.calls, greaterThan(0));
    });

    testWidgets('lieu déjà connu : ni écran ni lecture', (tester) async {
      await openPicker(tester, initial: const GeoPoint(lat: 6.2, lng: 1.2));
      expect(find.text('Plus tard'), findsNothing);
      expect(location.calls, 0);
    });
  });
}
