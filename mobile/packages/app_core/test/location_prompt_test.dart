import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_app_core/testing.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

const _identity = AppIdentity(
  brand: IviaAppBrand.driver,
  loginTitle: 'Espace livreur',
  loginBody: 'Connexion',
  codeHint: _hint,
  locationPrompt: LocationPromptCopy(
    space: 'Livreur',
    center: Icons.two_wheeler,
    satellites: [
      Icons.storefront,
      Icons.home,
      Icons.home,
      Icons.local_pharmacy,
    ],
    title: 'Des missions',
    titleAccent: 'près de vous',
    body: 'Activez la localisation pour recevoir les missions proches.',
  ),
);

String _hint(Duration d) => '';

/// Stockage du téléphone illisible.
class _UnreadableStore extends InMemorySharedPreferencesStore {
  _UnreadableStore() : super.empty();

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => Future.error(PlatformException(code: 'storage'));
}

/// Autorisation qui ne répond jamais (navigateur).
class _SilentLocation extends FakeLocationService {
  @override
  Future<LocationAccess> access() => Completer<LocationAccess>().future;
}

void main() {
  group('LocationPromptStore', () {
    setUp(() {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance =
          InMemorySharedPreferencesStore.empty();
    });

    test('premier lancement : écran à montrer, puis mémorisé', () async {
      final location = FakeLocationService(state: LocationAccess.askable);
      final store = await LocationPromptStore.open(location);
      expect(store.doneAtLaunch, isFalse);
      await store.markDone();
      expect((await LocationPromptStore.open(location)).doneAtLaunch, isTrue);
    });

    test(
      'position déjà autorisée : pas d\'écran, même retirée ensuite',
      () async {
        final location = FakeLocationService();
        expect((await LocationPromptStore.open(location)).doneAtLaunch, isTrue);
        location.state = LocationAccess.askable;
        expect((await LocationPromptStore.open(location)).doneAtLaunch, isTrue);
      },
    );

    test('refus définitif déjà connu : l\'écran est montré', () async {
      final store = await LocationPromptStore.open(
        FakeLocationService(state: LocationAccess.deniedForever),
      );
      expect(store.doneAtLaunch, isFalse);
    });

    test('stockage illisible : écran montré, sans erreur', () async {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = _UnreadableStore();
      final store = await LocationPromptStore.open(
        FakeLocationService(state: LocationAccess.askable),
      );
      expect(store.doneAtLaunch, isFalse);
      await store.markDone();
    });

    test('autorisation sans réponse : le lancement n\'attend pas', () async {
      final watch = Stopwatch()..start();
      final store = await LocationPromptStore.open(_SilentLocation());
      expect(store.doneAtLaunch, isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });

  group('écran', () {
    late FakeLocationService location;
    late int done;

    setUp(() {
      location = FakeLocationService(state: LocationAccess.askable);
      done = 0;
    });

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appIdentityProvider.overrideWithValue(_identity),
            locationServiceProvider.overrideWithValue(location),
          ],
          child: MaterialApp(
            theme: IviaTheme.light(),
            home: LocationPromptScreen(onDone: () => done++),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Plus tard'));
    }

    testWidgets('textes de l\'app', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Livreur'), findsOneWidget);
      expect(
        find.text('Des missions près de vous', findRichText: true),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.two_wheeler), findsOneWidget);
    });

    testWidgets('« Plus tard » : suite, sans fenêtre du système', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Plus tard'));
      expect(done, 1);
      expect(location.requests, 0);
    });

    for (final answer in [LocationAccess.granted, LocationAccess.askable]) {
      testWidgets('« Autoriser » puis $answer : fenêtre du système, suite', (
        tester,
      ) async {
        location.onRequest = answer;
        await pumpScreen(tester);
        await tester.tap(find.text('Autoriser la localisation'));
        await tester.pump();
        expect(location.requests, 1);
        expect(done, 1);
      });
    }

    testWidgets('refus définitif : réglages ouverts, pas de fenêtre', (
      tester,
    ) async {
      location.state = LocationAccess.deniedForever;
      await pumpScreen(tester);
      await tester.tap(find.text('Autoriser la localisation'));
      await tester.pump();
      expect(location.settingsOpened, 1);
      expect(location.requests, 0);
      expect(done, 1);
    });

    testWidgets('double appui : une seule demande, suite une seule fois', (
      tester,
    ) async {
      location.requestPending = Completer();
      await pumpScreen(tester);
      await tester.tap(find.text('Autoriser la localisation'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Autoriser la localisation'));
      await tester.pump();
      expect(location.requests, 1);
      location.requestPending!.complete();
      await tester.pump();
      expect(done, 1);
    });

    testWidgets('fenêtre du système sans réponse : « Plus tard » fait suivre', (
      tester,
    ) async {
      location.requestPending = Completer();
      await pumpScreen(tester);
      await tester.tap(find.text('Autoriser la localisation'));
      await tester.pump();
      await tester.tap(find.text('Plus tard'));
      await tester.pump();
      expect(done, 1);
      // Réponse tardive : pas de seconde suite.
      location.requestPending!.complete();
      await tester.pump();
      expect(done, 1);
    });
  });

  testWidgets('écran du lancement : passé, il est mémorisé', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final location = FakeLocationService(state: LocationAccess.askable);
    final store = await LocationPromptStore.open(location);
    final container = ProviderContainer(
      overrides: [
        appIdentityProvider.overrideWithValue(_identity),
        locationServiceProvider.overrideWithValue(location),
        locationPromptStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: IviaTheme.light(),
          home: const LaunchLocationPromptScreen(),
        ),
      ),
    );
    expect(container.read(locationPromptDoneProvider), isFalse);
    await tester.ensureVisible(find.text('Plus tard'));
    await tester.tap(find.text('Plus tard'));
    await tester.pump();
    expect(container.read(locationPromptDoneProvider), isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool('location_prompt_done'),
      isTrue,
    );
  });

  group('askForLocation', () {
    late FakeLocationService location;
    bool? result;

    setUp(() {
      location = FakeLocationService(state: LocationAccess.askable);
      result = null;
    });

    Future<void> pumpFeature(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appIdentityProvider.overrideWithValue(_identity),
            locationServiceProvider.overrideWithValue(location),
          ],
          child: MaterialApp(
            theme: IviaTheme.light(),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () async =>
                      result = await askForLocation(context, ref),
                  child: const Text('Utiliser ma position'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Utiliser ma position'));
      await tester.pumpAndSettle();
    }

    testWidgets('déjà autorisée : pas d\'écran', (tester) async {
      location.state = LocationAccess.granted;
      await pumpFeature(tester);
      expect(find.text('Plus tard'), findsNothing);
      expect(result, isTrue);
    });

    testWidgets('« Plus tard » : écran fermé, sans position', (tester) async {
      await pumpFeature(tester);
      await tester.ensureVisible(find.text('Plus tard'));
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();
      expect(find.text('Plus tard'), findsNothing);
      expect(find.text('Utiliser ma position'), findsOneWidget);
      expect(result, isFalse);
      expect(location.requests, 0);
    });

    testWidgets('« Autoriser » puis accepté : position autorisée', (
      tester,
    ) async {
      await pumpFeature(tester);
      await tester.ensureVisible(find.text('Plus tard'));
      await tester.tap(find.text('Autoriser la localisation'));
      await tester.pumpAndSettle();
      expect(find.text('Plus tard'), findsNothing);
      expect(result, isTrue);
    });

    testWidgets('deux appels rapprochés : un seul écran, même réponse', (
      tester,
    ) async {
      final answers = <Future<bool>>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appIdentityProvider.overrideWithValue(_identity),
            locationServiceProvider.overrideWithValue(location),
          ],
          child: MaterialApp(
            theme: IviaTheme.light(),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => answers
                    ..add(askForLocation(context, ref))
                    ..add(askForLocation(context, ref)),
                  child: const Text('Utiliser ma position'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Utiliser ma position'));
      await tester.pumpAndSettle();
      expect(find.byType(LocationPromptScreen), findsOneWidget);
      await tester.ensureVisible(find.text('Plus tard'));
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();
      expect(await Future.wait(answers), [false, false]);
      expect(find.byType(LocationPromptScreen), findsNothing);
    });

    testWidgets('retour système : vaut « Plus tard »', (tester) async {
      await pumpFeature(tester);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Plus tard'), findsNothing);
      expect(result, isFalse);
      expect(location.requests, 0);
    });
  });
}
