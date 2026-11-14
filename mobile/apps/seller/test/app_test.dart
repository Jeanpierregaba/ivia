import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_app_core/testing.dart';
import 'package:ivia_seller/app/device_services.dart';
import 'package:ivia_seller/app/identity.dart';
import 'package:ivia_seller/app/router.dart';
import 'package:ivia_seller/app/seller_shop.dart';
import 'package:ivia_seller/main.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lome = GeoPoint(lat: 6.1375, lng: 1.2123);

/// Image PNG de 1 × 1 pixel.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _FakePicker implements PhotoPicker {
  Uint8List? next = _png;

  @override
  Future<Uint8List?> pick({
    PhotoSource source = PhotoSource.gallery,
    int maxSide = 1024,
  }) async => next;
}

class _FakeLocation extends FakeLocationService {
  _FakeLocation() : super(next: const LocationResult.found(_lome));
}

/// Utilisateur renvoyé par le serveur, avec ou sans rôle seller.
Map<String, dynamic> _user({bool consent = true, bool seller = false}) => {
  ...userBody(complete: consent),
  'roles': ['buyer', if (seller) 'seller'],
};

void main() {
  late FakeApiServer server;
  late _FakePicker picker;
  late _FakeLocation location;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    picker = _FakePicker();
    location = _FakeLocation();
    server = FakeApiServer()
      ..on(
        'POST',
        '/v1/auth/phone/code',
        (_) => FakeResponse.json(202, phoneOtpBody),
      )
      ..on(
        'POST',
        '/v1/auth/phone/verify',
        (_) => FakeResponse.json(200, {
          'status': 'signed_in',
          'session': {...phoneSessionBody(), 'user': _user(consent: false)},
        }),
      )
      ..on('POST', '/v1/auth/logout', (_) => FakeResponse.json(204, null))
      ..on(
        'GET',
        '/v1/shop-categories',
        (_) => FakeResponse.json(200, shopCategoriesBody),
      )
      ..on(
        'GET',
        '/v1/neighborhoods',
        (_) => FakeResponse.json(200, neighborhoodsBody),
      )
      ..on('PATCH', '/v1/me', (_) => FakeResponse.json(200, _user()))
      // Nouveau marchand : aucune pièce encore déposée.
      ..on(
        'POST',
        '/v1/shops',
        (_) => FakeResponse.json(201, shopBody(documents: [])),
      )
      ..on(
        'POST',
        '/v1/uploads',
        (_) => FakeResponse.json(201, {
          'object_key': 'shop_logo/u1/logo.jpg',
          'upload': {
            'method': 'PUT',
            'url': 'https://stockage.test/shop_logo/u1/logo.jpg?sig=x',
            'headers': {'Content-Type': 'image/jpeg'},
            'expires_at': '2026-10-31T10:05:00Z',
          },
        }),
      )
      ..on(
        'PUT',
        '/shop_logo/u1/logo.jpg',
        (_) => FakeResponse.json(200, null),
      );
    // Espace « boutique » actif lié à la boutique de [shopBody] : seul
    // chemin, depuis Ivia Business, vers les écrans de création de boutique
    // et de pièces (boutique pas encore publiée).
    FakeBusiness(server);
  });

  Future<void> launchApp(
    WidgetTester tester, {
    Duration minSplash = Duration.zero,
    bool settle = true,
    bool devCode = false,
  }) async {
    // Animations réduites : le point « en direct » du pilotage s'arrête.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final store = await OnboardingStore.open();
    await tester.pumpWidget(const SizedBox());
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
            AuthTimings(
              minSplash: minSplash,
              meTimeout: const Duration(seconds: 1),
            ),
          ),
          photoPickerProvider.overrideWithValue(picker),
          locationServiceProvider.overrideWithValue(location),
          locationPromptStoreProvider.overrideWithValue(
            await LocationPromptStore.open(location),
          ),
          mapsEnabledProvider.overrideWithValue(false),
          devAutoCodeProvider.overrideWithValue(devCode),
        ],
        child: const SellerApp(),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    // Clavier fermé : un champ actif ramènerait l'écran sur son curseur.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final target = find.text(text, skipOffstage: false);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  void onboardingSeen() =>
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});

  Future<void> signedInWith(Map<String, dynamic> user) async {
    onboardingSeen();
    await SessionStore().save('jeton-secret', User.fromJson(user));
    server.on('GET', '/v1/me', (_) => FakeResponse.json(200, user));
  }

  Future<void> login(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '90 12 34 56');
    await tapText(tester, 'Recevoir le code sur WhatsApp');
    await tester.enterText(find.byType(TextField), '481902');
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(IviaFieldLabel, label),
    matching: find.byType(TextField),
  );

  Future<void> choose(WidgetTester tester, String label, String item) async {
    final select = find.descendant(
      of: find.widgetWithText(IviaFieldLabel, label),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await tester.ensureVisible(select);
    await tester.pumpAndSettle();
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  /// Remplit tout le formulaire, consentement compris s'il est demandé.
  Future<void> fillShopForm(WidgetTester tester) async {
    await tester.enterText(field('Nom de la boutique'), 'Chez Afi');
    await choose(tester, 'Catégorie', 'Alimentation');
    await tester.enterText(field('Téléphone de la boutique'), '90123456');
    await tester.enterText(field('Adresse'), 'Rue 248');
    await choose(tester, 'Quartier', 'Tokoin');
    await tapText(tester, 'Ma position');
    if (find.byType(Checkbox).evaluate().isNotEmpty) {
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
    }
  }

  group('lancement et présentation', () {
    const firstTitle = 'Votre boutique en ligne, sans site web.';

    testWidgets('thème Berkeley et splash avec tuile', (tester) async {
      await launchApp(
        tester,
        minSplash: const Duration(milliseconds: 800),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Business'), findsOneWidget);
      expect(find.text("Votre activité, pilotée d'ici."), findsOneWidget);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.title, 'Ivia Business');
      expect(app.theme?.colorScheme.primary, IviaColors.berkeleyBlue);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text(firstTitle, findRichText: true), findsOneWidget);
    });

    testWidgets(
      "localisation (030) : écran après le splash, « Saisir l'adresse »",
      (tester) async {
        location.state = LocationAccess.askable;
        await launchApp(tester);
        expect(find.text('Business'), findsOneWidget);
        expect(
          find.text('Soyez visible dans votre quartier', findRichText: true),
          findsOneWidget,
        );
        expect(find.text(firstTitle, findRichText: true), findsNothing);
        await tapText(tester, "Saisir l'adresse");
        expect(find.text(firstTitle, findRichText: true), findsOneWidget);
        expect(location.requests, 0);
      },
    );

    testWidgets('présentation : « Suivant », « Commencer », puis connexion', (
      tester,
    ) async {
      await launchApp(tester);
      await tapText(tester, 'Suivant');
      expect(
        find.text('Des commandes déjà payées.', findRichText: true),
        findsOneWidget,
      );
      await tapText(tester, 'Suivant');
      await tapText(tester, 'Commencer');
      expect(find.text('Votre activité vous attend'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getBool('onboarding_seen'),
        isTrue,
      );
    });

    testWidgets('« Passer » : connexion directement', (tester) async {
      await launchApp(tester);
      await tapText(tester, 'Passer');
      expect(find.text('Votre activité vous attend'), findsOneWidget);
    });

    testWidgets('présentation : police à 200 % sur 320 dp sans débordement', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 640)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await launchApp(tester);
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Suivant');
      expect(tester.takeException(), isNull);
    });
  });

  group('connexion et boutique', () {
    setUp(() {
      onboardingSeen();
      // Profil complet : « Faisons connaissance » est passé, le formulaire de
      // la boutique s'ouvre (espace boutique actif sans boutique).
      server.on(
        'POST',
        '/v1/auth/phone/verify',
        (_) => FakeResponse.json(200, {
          'status': 'signed_in',
          'session': {...phoneSessionBody(), 'user': _user()},
        }),
      );
    });

    testWidgets('profil incomplet : « Faisons connaissance » d\'abord', (
      tester,
    ) async {
      server.on(
        'POST',
        '/v1/auth/phone/verify',
        (_) => FakeResponse.json(200, {
          'status': 'signed_in',
          'session': {...phoneSessionBody(), 'user': _user(consent: false)},
        }),
      );
      await launchApp(tester);
      await login(tester);
      expect(find.text('Faisons connaissance'), findsOneWidget);
      expect(find.text('Créez votre boutique'), findsNothing);
    });

    testWidgets('nouveau marchand : code, boutique, validation', (
      tester,
    ) async {
      await launchApp(tester);
      await tester.enterText(find.byType(TextField), '90 12 34 56');
      await tapText(tester, 'Recevoir le code sur WhatsApp');
      expect(find.text('Saisissez le code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '481902');
      await tester.pumpAndSettle();

      expect(find.text('Créez votre boutique'), findsOneWidget);
      expect(find.text('Étape 1 sur 2'), findsOneWidget);
      // Pas de rôle seller : aucune boutique demandée au serveur.
      expect(server.calls('GET', '/v1/seller/shops'), isEmpty);

      await fillShopForm(tester);
      await tapText(tester, 'Envoyer pour validation');

      // Consentement déjà donné dans « Faisons connaissance ».
      expect(server.calls('PATCH', '/v1/me'), isEmpty);
      expect(server.calls('POST', '/v1/shops').single.body, {
        'name': 'Chez Afi',
        'category_id': '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d',
        'phone': '+22890123456',
        'address_text': 'Rue 248',
        'neighborhood_id': '5f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b',
        'location': {'lat': 6.1375, 'lng': 1.2123},
      });
      // Sans pièce d'identité : l'écran des pièces s'ouvre au-dessus de
      // l'écran de validation.
      expect(find.text('Vérifions votre identité'), findsOneWidget);
      expect(find.text('Étape 2 sur 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(
        find.text('Votre boutique est en cours de validation'),
        findsOneWidget,
      );
      expect(find.text('Chez Afi · Tokoin'), findsOneWidget);
    });

    testWidgets('compte acheteur existant : téléphone prérempli, pas de case', (
      tester,
    ) async {
      server.on(
        'POST',
        '/v1/auth/phone/verify',
        (_) => FakeResponse.json(200, {
          'status': 'signed_in',
          'session': {...phoneSessionBody(), 'user': _user()},
        }),
      );
      await launchApp(tester);
      await login(tester);
      expect(
        tester
            .widget<TextField>(field('Téléphone de la boutique'))
            .controller!
            .text,
        '90 12 34 56',
      );
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('logo : envoyé sur l\'URL signée, clé transmise', (
      tester,
    ) async {
      await launchApp(tester);
      await login(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.text('Retirer le logo'), findsOneWidget);
      await fillShopForm(tester);
      await tapText(tester, 'Envoyer pour validation');

      expect(server.calls('POST', '/v1/uploads').single.body, {
        'purpose': 'shop_logo',
        'content_type': 'image/jpeg',
        'size_bytes': _png.length,
      });
      final put = server.calls('PUT', '/shop_logo/u1/logo.jpg').single;
      expect(put.headers['authorization'], isNull);
      expect(
        (server.calls('POST', '/v1/shops').single.body! as Map)['logo_key'],
        'shop_logo/u1/logo.jpg',
      );
    });

    testWidgets('logo non envoyé : message, boutique non créée', (
      tester,
    ) async {
      server.on(
        'PUT',
        '/shop_logo/u1/logo.jpg',
        (_) => FakeResponse.json(403, 'refusé'),
      );
      await launchApp(tester);
      await login(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await fillShopForm(tester);
      await tapText(tester, 'Envoyer pour validation');
      expect(
        find.textContaining("Le logo n'a pas pu être envoyé"),
        findsOneWidget,
      );
      expect(server.calls('POST', '/v1/shops'), isEmpty);
    });

    testWidgets('logo trop lourd : refusé dès le choix', (tester) async {
      picker.next = Uint8List(5 * 1024 * 1024 + 1);
      await launchApp(tester);
      await login(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.text('Photo trop lourde (5 Mo au plus).'), findsOneWidget);
      expect(find.text('Retirer le logo'), findsNothing);
    });

    testWidgets('formulaire vide : messages, aucun envoi', (tester) async {
      await launchApp(tester);
      await login(tester);
      await tester.enterText(field('Téléphone de la boutique'), '');
      await tapText(tester, 'Envoyer pour validation');
      for (final message in [
        'Le nom compte de 2 à 100 caractères.',
        'Choisissez une catégorie.',
        "Saisissez l'adresse (300 caractères au plus).",
        'Choisissez le quartier.',
        'Placez votre boutique sur la carte.',
      ]) {
        expect(
          find.text(message, skipOffstage: false),
          findsOneWidget,
          reason: message,
        );
      }
      // Consentement donné dans « Faisons connaissance » : pas de case.
      expect(
        find.textContaining('Cochez la case', skipOffstage: false),
        findsNothing,
      );
      expect(server.calls('POST', '/v1/shops'), isEmpty);
      expect(server.calls('PATCH', '/v1/me'), isEmpty);
    });

    testWidgets('échec puis nouvel essai : logo non renvoyé', (tester) async {
      var attempts = 0;
      server.on(
        'POST',
        '/v1/shops',
        (_) => attempts++ == 0
            ? FakeResponse.networkError()
            : FakeResponse.json(201, shopBody()),
      );
      await launchApp(tester);
      await login(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await fillShopForm(tester);
      await tapText(tester, 'Envoyer pour validation');
      expect(find.textContaining('Pas de connexion internet'), findsOneWidget);
      await tapText(tester, 'Envoyer pour validation');
      expect(
        find.text('Votre boutique est en cours de validation'),
        findsOneWidget,
      );
      expect(server.calls('POST', '/v1/uploads'), hasLength(1));
      expect(server.calls('POST', '/v1/shops'), hasLength(2));
    });

    testWidgets('erreur sur un champ non affiché : message général', (
      tester,
    ) async {
      server.on(
        'POST',
        '/v1/shops',
        (_) => FakeResponse.error(
          400,
          'validation_failed',
          'Données invalides.',
          fields: {'description': 'Trop long.'},
        ),
      );
      await launchApp(tester);
      await login(tester);
      await fillShopForm(tester);
      await tapText(tester, 'Envoyer pour validation');
      expect(find.text('Données invalides.'), findsOneWidget);
    });

    testWidgets('catégories indisponibles : « Réessayer »', (tester) async {
      server.on(
        'GET',
        '/v1/shop-categories',
        (_) => FakeResponse.networkError(),
      );
      await launchApp(tester);
      await login(tester);
      expect(find.textContaining('Impossible de charger'), findsOneWidget);
      server.on(
        'GET',
        '/v1/shop-categories',
        (_) => FakeResponse.json(200, shopCategoriesBody),
      );
      await tapText(tester, 'Réessayer');
      expect(find.text('Nom de la boutique'), findsOneWidget);
    });

    testWidgets('erreur inattendue de la localisation : bouton libéré', (
      tester,
    ) async {
      location.error = Exception('demande déjà en cours');
      await launchApp(tester);
      await login(tester);
      await tapText(tester, 'Ma position');
      expect(find.textContaining('Position introuvable'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Ma position'),
          matching: find.byWidgetPredicate((w) => w is TextButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('localisation refusée : message, placement à la main', (
      tester,
    ) async {
      location.next = const LocationResult.failed(LocationFailure.denied);
      await launchApp(tester);
      await login(tester);
      await tapText(tester, 'Ma position');
      expect(
        find.text(
          'Localisation refusée. Autorisez-la pour placer la boutique.',
        ),
        findsOneWidget,
      );
      expect(find.text('Aucune position'), findsOneWidget);
    });

    for (final allow in [false, true]) {
      testWidgets(
        'épingle sans autorisation : écran, puis ${allow ? 'position' : 'refus'}',
        (tester) async {
          SharedPreferences.setMockInitialValues({
            'onboarding_seen': true,
            'location_prompt_done': true,
          });
          location.state = LocationAccess.askable;
          await launchApp(tester);
          await login(tester);
          await tapText(tester, 'Ma position');
          expect(
            find.text('Soyez visible dans votre quartier', findRichText: true),
            findsOneWidget,
          );
          await tapText(
            tester,
            allow ? 'Autoriser la localisation' : "Saisir l'adresse",
          );
          expect(location.requests, allow ? 1 : 0);
          expect(
            find.text(
              'Localisation refusée. Autorisez-la pour placer la boutique.',
            ),
            allow ? findsNothing : findsOneWidget,
          );
          expect(
            find.text('Aucune position'),
            allow ? findsNothing : findsOneWidget,
          );
        },
      );
    }

    testWidgets('erreur du serveur sur un champ : message sous le champ', (
      tester,
    ) async {
      server.on(
        'POST',
        '/v1/shops',
        (_) => FakeResponse.error(
          400,
          'validation_failed',
          'Données invalides.',
          fields: {'location.lat': 'Position hors du Togo.'},
        ),
      );
      await launchApp(tester);
      await login(tester);
      await fillShopForm(tester);
      await tapText(tester, 'Envoyer pour validation');
      expect(find.text('Position hors du Togo.'), findsOneWidget);
      expect(find.text('Envoyer pour validation'), findsOneWidget);
    });

    testWidgets('réseau coupé : message, formulaire conservé', (tester) async {
      server.on('POST', '/v1/shops', (_) => FakeResponse.networkError());
      await launchApp(tester);
      await login(tester);
      await fillShopForm(tester);
      await tapText(tester, 'Envoyer pour validation');
      expect(find.textContaining('Pas de connexion internet'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('Nom de la boutique')).controller!.text,
        'Chez Afi',
      );
    });

    testWidgets('double appui : une seule boutique créée', (tester) async {
      final reply = Completer<FakeResponse>();
      server.on('POST', '/v1/shops', (_) => reply.future);
      await launchApp(tester);
      await login(tester);
      await fillShopForm(tester);
      final submit = find.text('Envoyer pour validation');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      reply.complete(FakeResponse.json(201, shopBody()));
      await tester.pumpAndSettle();
      expect(server.calls('POST', '/v1/shops'), hasLength(1));
    });

    testWidgets('développement : code de l\'API locale saisi tout seul', (
      tester,
    ) async {
      onboardingSeen();
      server.on(
        'POST',
        '/v1/dev/otp',
        (_) => FakeResponse.json(200, {'code': '481902'}),
      );
      await launchApp(tester, devCode: true);
      await tester.enterText(find.byType(TextField), '90 12 34 56');
      await tapText(tester, 'Recevoir le code sur WhatsApp');
      await tester.pumpAndSettle();
      expect(server.calls('POST', '/v1/dev/otp').single.body, {
        'recipient': '+22890123456',
      });
      expect(
        (server.calls('POST', '/v1/auth/phone/verify').single.body!
            as Map)['code'],
        '481902',
      );
      expect(find.text('Créez votre boutique'), findsOneWidget);
    });

    testWidgets('sans le drapeau de développement : code demandé', (
      tester,
    ) async {
      onboardingSeen();
      await launchApp(tester);
      await tester.enterText(find.byType(TextField), '90 12 34 56');
      await tapText(tester, 'Recevoir le code sur WhatsApp');
      expect(server.calls('POST', '/v1/dev/otp'), isEmpty);
      expect(find.text('Saisissez le code'), findsOneWidget);
    });

    testWidgets('retour sur le formulaire : déconnexion', (tester) async {
      await launchApp(tester);
      await login(tester);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(server.calls('POST', '/v1/auth/logout'), hasLength(1));
      expect(find.text('Votre activité vous attend'), findsOneWidget);
    });

    testWidgets('police à 200 % sur 320 dp : formulaire sans débordement', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await launchApp(tester);
      await login(tester);
      await tester.ensureVisible(find.text('Envoyer pour validation'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  /// Choisit une photo pour une ligne de l'écran des pièces (le libellé
  /// « Pièce d'identité » est aussi sur l'écran en attente, dessous).
  Future<void> addPhoto(WidgetTester tester, String document) async {
    final row = find.widgetWithText(DocumentPhotoRow, document);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choisir une photo'));
    await tester.pumpAndSettle();
  }

  group('pièces du marchand', () {
    late FakeMerchantDocuments docs;

    setUp(() async {
      // Compte acheteur existant : la création ne demande pas d'accord.
      await signedInWith(_user());
      docs = FakeMerchantDocuments(server);
    });

    /// Crée la boutique : l'écran des pièces s'ouvre.
    Future<void> createShop(WidgetTester tester) async {
      await launchApp(tester);
      await fillShopForm(tester);
      await tapText(tester, 'Envoyer pour validation');
      expect(find.text('Vérifions votre identité'), findsOneWidget);
    }

    Finder row(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(DocumentPhotoRow),
    );

    testWidgets('pièce d\'identité obligatoire, RCCM facultatif', (
      tester,
    ) async {
      await createShop(tester);
      expect(
        find.descendant(
          of: row("Pièce d'identité"),
          matching: find.text('Obligatoire'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "Carte d'identité, passeport ou carte d'électeur, face avec la photo",
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row('Registre du commerce (RCCM)'),
          matching: find.text('Facultatif'),
        ),
        findsOneWidget,
      );
      expect(find.text('Ajouter'), findsNWidgets(2));
    });

    testWidgets('sans pièce d\'identité : message, rien d\'envoyé', (
      tester,
    ) async {
      await createShop(tester);
      await addPhoto(tester, 'Registre du commerce (RCCM)');
      await tapText(tester, 'Envoyer mes pièces');
      expect(find.text("Ajoutez votre pièce d'identité."), findsOneWidget);
      expect(server.calls('POST', '/v1/uploads'), isEmpty);
      expect(find.text('Vérifions votre identité'), findsOneWidget);

      // Pièce ajoutée : message retiré.
      await addPhoto(tester, "Pièce d'identité");
      expect(find.text("Ajoutez votre pièce d'identité."), findsNothing);
    });

    testWidgets('envoi : URL signée privée, rattachement, écran en attente', (
      tester,
    ) async {
      await createShop(tester);
      await addPhoto(tester, "Pièce d'identité");
      await addPhoto(tester, 'Registre du commerce (RCCM)');
      expect(find.text('Ajoutée'), findsNWidgets(2));
      await tapText(tester, 'Envoyer mes pièces');

      final uploads = server.calls('POST', '/v1/uploads');
      expect(uploads, hasLength(2));
      for (final upload in uploads) {
        expect(upload.body, {
          'purpose': 'merchant_document',
          'content_type': 'image/jpeg',
          'size_bytes': picker.next!.length,
        });
      }
      expect(docs.uploaded, hasLength(2));
      expect(
        server
            .calls('POST', '/v1/seller/documents')
            .map((r) => (r.body! as Map)['kind']),
        ['id_card', 'business_registration'],
      );
      expect(docs.kinds, ['id_card', 'business_registration']);
      expect(
        find.text('Votre boutique est en cours de validation'),
        findsOneWidget,
      );
      expect(find.text('Pièces envoyées.'), findsOneWidget);
    });

    testWidgets('réseau coupé : photos gardées, rien d\'envoyé deux fois', (
      tester,
    ) async {
      await createShop(tester);
      await addPhoto(tester, "Pièce d'identité");
      await addPhoto(tester, 'Registre du commerce (RCCM)');
      // La pièce d'identité passe, le RCCM est coupé au rattachement.
      var attach = 0;
      server.on('POST', '/v1/seller/documents', (r) {
        if (++attach == 2) return FakeResponse.networkError();
        return docs.attach(r);
      });
      await tapText(tester, 'Envoyer mes pièces');
      expect(find.textContaining('Pas de connexion internet'), findsOneWidget);
      expect(find.text('Vérifions votre identité'), findsOneWidget);
      // Pièce d'identité rattachée : « Ajoutée » reste (photo gardée).
      expect(find.text('Ajoutée'), findsNWidgets(2));

      await tapText(tester, 'Envoyer mes pièces');
      expect(server.calls('POST', '/v1/uploads'), hasLength(2));
      expect(docs.kinds, ['id_card', 'business_registration']);
      expect(
        find.text('Votre boutique est en cours de validation'),
        findsOneWidget,
      );
    });

    testWidgets('envoi du fichier coupé : renvoyé au nouvel essai', (
      tester,
    ) async {
      await createShop(tester);
      await addPhoto(tester, "Pièce d'identité");
      docs.failures['PUT /merchants'] = FakeResponse.networkError();
      await tapText(tester, 'Envoyer mes pièces');
      expect(find.textContaining('Pas de connexion internet'), findsOneWidget);
      expect(docs.kinds, isEmpty);

      await tapText(tester, 'Envoyer mes pièces');
      expect(docs.kinds, ['id_card']);
    });

    testWidgets('fichier refusé au rattachement : renvoyé au nouvel essai', (
      tester,
    ) async {
      await createShop(tester);
      await addPhoto(tester, "Pièce d'identité");
      docs.failures['POST /v1/seller/documents'] = FakeResponse.error(
        400,
        'validation_failed',
        'Certaines informations sont invalides.',
        fields: {'object_key': "Le fichier n'a pas été reçu. Renvoyez-le."},
      );
      await tapText(tester, 'Envoyer mes pièces');
      expect(
        find.text("Le fichier n'a pas été reçu. Renvoyez-le."),
        findsOneWidget,
      );

      await tapText(tester, 'Envoyer mes pièces');
      final keys = server
          .calls('POST', '/v1/seller/documents')
          .map((r) => (r.body! as Map)['object_key'])
          .toList();
      expect(server.calls('POST', '/v1/uploads'), hasLength(2));
      expect(keys, hasLength(2));
      expect(keys.last, isNot(keys.first));
      expect(docs.kinds, ['id_card']);
    });

    testWidgets('nouvelle photo après un échec : envoyée et rattachée', (
      tester,
    ) async {
      await createShop(tester);
      await addPhoto(tester, "Pièce d'identité");
      docs.failures['POST /v1/seller/documents'] = FakeResponse.networkError();
      await tapText(tester, 'Envoyer mes pièces');
      expect(find.textContaining('Pas de connexion internet'), findsOneWidget);

      picker.next = Uint8List.fromList([..._png, 0]);
      await addPhoto(tester, "Pièce d'identité");
      await tapText(tester, 'Envoyer mes pièces');
      final uploads = server.calls('POST', '/v1/uploads');
      expect(uploads, hasLength(2));
      expect((uploads.last.body! as Map)['size_bytes'], _png.length + 1);
      final attached = server.calls('POST', '/v1/seller/documents');
      expect((attached.last.body! as Map)['object_key'], docs.uploaded.last);
      expect(docs.kinds, ['id_card']);
    });

    testWidgets(
      'retour dans l\'app sur l\'écran des pièces : pas de relecture',
      (tester) async {
        await createShop(tester);
        server.on(
          'GET',
          '/v1/seller/shops',
          (_) => FakeResponse.networkError(),
        );
        for (final state in const [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pumpAndSettle();
        expect(server.calls('GET', '/v1/seller/shops'), isEmpty);
        expect(find.textContaining('statut non actualisé'), findsNothing);
      },
    );

    testWidgets('trop de pièces : message du serveur', (tester) async {
      docs.kinds.addAll(List.filled(10, 'other'));
      await createShop(tester);
      await addPhoto(tester, "Pièce d'identité");
      await tapText(tester, 'Envoyer mes pièces');
      expect(find.text('Nombre maximal de documents atteint.'), findsOneWidget);
      expect(find.text('Vérifions votre identité'), findsOneWidget);
    });

    testWidgets(
      'double appui : un seul envoi ; retour bloqué pendant l\'envoi',
      (tester) async {
        await createShop(tester);
        await addPhoto(tester, "Pièce d'identité");
        final reply = Completer<void>();
        server.on('POST', '/v1/seller/documents', (r) async {
          await reply.future;
          return docs.attach(r);
        });
        final submit = find.text('Envoyer mes pièces');
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        await tester.tap(submit);
        await tester.pump();
        await tester.tap(find.byType(FilledButton), warnIfMissed: false);
        await tester.tap(find.byTooltip('Retour'), warnIfMissed: false);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('Vérifions votre identité'), findsOneWidget);
        reply.complete();
        await tester.pumpAndSettle();
        expect(server.calls('POST', '/v1/uploads'), hasLength(1));
        expect(server.calls('POST', '/v1/seller/documents'), hasLength(1));
        expect(
          find.text('Votre boutique est en cours de validation'),
          findsOneWidget,
        );
      },
    );

    testWidgets('retour : écran en attente, rien d\'envoyé', (tester) async {
      await createShop(tester);
      await addPhoto(tester, "Pièce d'identité");
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(
        find.text('Votre boutique est en cours de validation'),
        findsOneWidget,
      );
      expect(server.calls('POST', '/v1/uploads'), isEmpty);
    });

    testWidgets('pièce d\'identité déjà déposée : écran en attente direct', (
      tester,
    ) async {
      server.on(
        'POST',
        '/v1/shops',
        (_) => FakeResponse.json(201, shopBody(documents: ['id_card'])),
      );
      await launchApp(tester);
      await fillShopForm(tester);
      await tapText(tester, 'Envoyer pour validation');
      expect(
        find.text('Votre boutique est en cours de validation'),
        findsOneWidget,
      );
      expect(find.text('Vérifions votre identité'), findsNothing);
    });

    testWidgets('police à 200 % sur 320 dp : rien n\'est masqué', (
      tester,
    ) async {
      await createShop(tester);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Envoyer mes pièces'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('relance avec une boutique', () {
    Future<void> withShop(
      String status, {
      List<String> documents = const ['id_card'],
    }) async {
      await signedInWith(_user(seller: true));
      server.on(
        'GET',
        '/v1/seller/shops',
        (_) => FakeResponse.json(200, {
          'items': [shopBody(status: status, documents: documents)],
        }),
      );
    }

    testWidgets('en attente sans pièce d\'identité : étape à faire, envoi', (
      tester,
    ) async {
      await withShop('pending_review', documents: []);
      final docs = FakeMerchantDocuments(server);
      await launchApp(tester);
      expect(find.text("Pièce d'identité"), findsOneWidget);
      expect(
        find.text(
          'À ajouter : sans elle, la boutique ne peut pas être publiée',
        ),
        findsOneWidget,
      );
      expect(find.text('En cours'), findsNothing);
      expect(find.text('Préparer mes produits'), findsOneWidget);

      await tapText(tester, "Ajouter ma pièce d'identité");
      expect(find.text('Vérifions votre identité'), findsOneWidget);
      await addPhoto(tester, "Pièce d'identité");
      await tapText(tester, 'Envoyer mes pièces');

      expect(docs.kinds, ['id_card']);
      expect(
        find.text('Votre boutique est en cours de validation'),
        findsOneWidget,
      );
      expect(find.text('Envoyée'), findsOneWidget);
      expect(find.text('En cours'), findsOneWidget);
      expect(find.text("Ajouter ma pièce d'identité"), findsNothing);
    });

    testWidgets('pièce déjà envoyée : étape faite, « Envoyée » sur l\'écran '
        'des pièces', (tester) async {
      await withShop('pending_review');
      await launchApp(tester);
      expect(find.text('Envoyée'), findsOneWidget);
      expect(find.text('En cours'), findsOneWidget);
      expect(find.text("Ajouter ma pièce d'identité"), findsNothing);

      ProviderScope.containerOf(tester.element(find.byType(SellerApp)))
          .read(routerProvider)
          .go(Routes.shopDocuments);
      await tester.pumpAndSettle();
      expect(find.text('Vérifions votre identité'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text("Pièce d'identité"),
            matching: find.byType(DocumentPhotoRow),
          ),
          matching: find.text('Envoyée'),
        ),
        findsOneWidget,
      );
      // Rien de nouveau à envoyer : retour à l'écran en attente.
      await tapText(tester, 'Envoyer mes pièces');
      expect(server.calls('POST', '/v1/uploads'), isEmpty);
      expect(
        find.text('Votre boutique est en cours de validation'),
        findsOneWidget,
      );
    });

    testWidgets('pièce déposée ailleurs : relue en tirant vers le bas', (
      tester,
    ) async {
      await withShop('pending_review', documents: []);
      await launchApp(tester);
      expect(find.text("Ajouter ma pièce d'identité"), findsOneWidget);
      server.on(
        'GET',
        '/v1/seller/shops',
        (_) => FakeResponse.json(200, {
          'items': [shopBody(status: 'pending_review')],
        }),
      );
      await tester.fling(find.text('Compte créé'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Envoyée'), findsOneWidget);
      expect(find.text("Ajouter ma pièce d'identité"), findsNothing);
    });

    testWidgets('boutique lue sans ses pièces : pas d\'étape', (tester) async {
      await signedInWith(_user(seller: true));
      server.on(
        'GET',
        '/v1/seller/shops',
        (_) => FakeResponse.json(200, {
          'items': [shopBody()..remove('merchant_documents')],
        }),
      );
      await launchApp(tester);
      expect(
        find.text('Votre boutique est en cours de validation'),
        findsOneWidget,
      );
      expect(find.text("Pièce d'identité"), findsNothing);
      expect(find.text('En cours'), findsOneWidget);
      expect(find.text('Préparer mes produits'), findsOneWidget);
    });

    for (final status in ['published', 'rejected', 'suspended']) {
      testWidgets('$status : écran des pièces jamais proposé', (tester) async {
        await withShop(status, documents: []);
        await launchApp(tester);
        ProviderScope.containerOf(tester.element(find.byType(SellerApp)))
            .read(routerProvider)
            .go(Routes.shopDocuments);
        await tester.pumpAndSettle();
        expect(find.text('Vérifions votre identité'), findsNothing);
        expect(find.text("Ajouter ma pièce d'identité"), findsNothing);
      });
    }

    testWidgets('relecture partie avant un dépôt : pièces gardées', (
      tester,
    ) async {
      await withShop('pending_review', documents: []);
      await launchApp(tester);
      final reply = Completer<FakeResponse>();
      server.on('GET', '/v1/seller/shops', (_) => reply.future);
      final shop = ProviderScope.containerOf(
        tester.element(find.byType(SellerApp)),
      ).read(sellerShopProvider.notifier);
      bool? refreshed;
      unawaited(shop.refresh().then((ok) => refreshed = ok));
      shop.documentsSent([MerchantDocumentKind.idCard]);
      reply.complete(
        FakeResponse.json(200, {
          'items': [shopBody(status: 'pending_review', documents: [])],
        }),
      );
      await tester.pumpAndSettle();
      expect(refreshed, isTrue);
      expect(find.text('Envoyée'), findsOneWidget);
      expect(find.text("Ajouter ma pièce d'identité"), findsNothing);
    });

    testWidgets('sans pièce, police à 200 % sur 320 dp : deux boutons', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await withShop('pending_review', documents: []);
      await launchApp(tester);
      await tester.ensureVisible(find.text('Préparer mes produits'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text("Ajouter ma pièce d'identité"), findsOneWidget);
    });

    testWidgets('en attente : étapes, actualisation, publiée', (tester) async {
      await withShop('pending_review');
      await launchApp(tester);
      expect(
        find.text('Votre boutique est en cours de validation'),
        findsOneWidget,
      );

      server.on(
        'GET',
        '/v1/seller/shops',
        (_) => FakeResponse.json(200, {
          'items': [shopBody(status: 'published')],
        }),
      );
      await tester.fling(find.text('Compte créé'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Ventes du jour'), findsOneWidget);
    });

    testWidgets('« Préparer mes produits » : catalogue sans barre, retour', (
      tester,
    ) async {
      await withShop('pending_review');
      FakeCatalog(server);
      await launchApp(tester);
      await tapText(tester, 'Préparer mes produits');
      expect(find.text('Produits'), findsOneWidget);
      expect(
        find.textContaining('dès que votre boutique sera'),
        findsOneWidget,
      );
      expect(find.byType(IviaBottomNav), findsNothing);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(
        find.text('Votre boutique est en cours de validation'),
        findsOneWidget,
      );
    });

    testWidgets('suspendue : motif et déconnexion possible', (tester) async {
      await withShop('suspended');
      await launchApp(tester);
      expect(find.text('Votre boutique est suspendue'), findsOneWidget);
      expect(find.text('Se déconnecter'), findsOneWidget);
    });

    testWidgets('actualisation sans réseau : message, écran gardé', (
      tester,
    ) async {
      await withShop('pending_review');
      await launchApp(tester);
      server.on('GET', '/v1/seller/shops', (_) => FakeResponse.networkError());
      await tester.fling(find.text('Compte créé'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.textContaining('statut non actualisé'), findsOneWidget);
      expect(
        find.text('Votre boutique est en cours de validation'),
        findsOneWidget,
      );
    });

    testWidgets('refusée : motif affiché', (tester) async {
      await withShop('rejected');
      await launchApp(tester);
      expect(find.text("Votre boutique n'a pas été validée"), findsOneWidget);
      expect(find.text('Motif : Photo du logo illisible.'), findsOneWidget);
    });

    testWidgets('serveur injoignable : hors ligne, puis « Réessayer »', (
      tester,
    ) async {
      await withShop('published');
      server.on('GET', '/v1/seller/shops', (_) => FakeResponse.networkError());
      await launchApp(tester);
      expect(find.text('Pas de connexion'), findsOneWidget);
      server.on(
        'GET',
        '/v1/seller/shops',
        (_) => FakeResponse.json(200, {
          'items': [shopBody(status: 'published')],
        }),
      );
      await tapText(tester, 'Réessayer');
      expect(find.text('Ventes du jour'), findsOneWidget);
    });
  });
}
