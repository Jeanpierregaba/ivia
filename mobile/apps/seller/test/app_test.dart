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
import 'package:ivia_seller/app/device_services.dart';
import 'package:ivia_seller/app/identity.dart';
import 'package:ivia_seller/features/onboarding/onboarding_screen.dart';
import 'package:ivia_seller/main.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _email = 'afi@test.tg';
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

class _FakeLocation implements LocationService {
  var settingsOpened = 0;

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }

  LocationResult next = const LocationResult.found(_lome);
  Exception? error;

  @override
  Future<LocationResult> current() async {
    if (error case final e?) throw e;
    return next;
  }
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
      ..on('POST', '/v1/auth/otp', (_) => FakeResponse.json(202, otpBody))
      ..on(
        'POST',
        '/v1/auth/verify',
        (_) => FakeResponse.json(200, {
          ...sessionBody(),
          'user': _user(consent: false),
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
      ..on('POST', '/v1/shops', (_) => FakeResponse.json(201, shopBody()))
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
  });

  Future<void> launchApp(
    WidgetTester tester, {
    Duration minSplash = Duration.zero,
    bool settle = true,
    bool devCode = false,
  }) async {
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
    await tester.enterText(find.byType(TextField), _email);
    await tapText(tester, 'Recevoir le code');
    await tester.enterText(find.byType(TextField), '481902');
    await tester.pump();
    await tapText(tester, 'Vérifier le code');
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
    testWidgets('thème Berkeley et splash avec tuile', (tester) async {
      await launchApp(
        tester,
        minSplash: const Duration(milliseconds: 800),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Marchand'), findsOneWidget);
      expect(find.text('Vendez dans votre quartier.'), findsOneWidget);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.title, 'ivia Marchand');
      expect(app.theme?.colorScheme.primary, IviaColors.berkeleyBlue);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(
        find.text('Votre boutique en ligne, sans site web.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'présentation : « Marchand » en tête, puis « Espace marchand »',
      (tester) async {
        await launchApp(tester);
        final onboarding = tester.widget<IviaOnboarding>(
          find.byType(IviaOnboarding),
        );
        expect(onboarding.appName, 'Marchand');
        expect(onboarding.brand, IviaAppBrand.seller);
        await tapText(tester, 'Passer');
        expect(find.text('Espace marchand'), findsOneWidget);
        expect(find.text('Marchand'), findsOneWidget);
      },
    );

    testWidgets('titres : aucun mot coupé sur 320 dp, police agrandie', (
      tester,
    ) async {
      final loader = FontLoader(
        'packages/ivia_ui/Parkinsans',
      )..addFont(rootBundle.load('packages/ivia_ui/fonts/Parkinsans-Bold.ttf'));
      await loader.load();
      const width = 320 - 2 * IviaSpacing.screen;
      final style = IviaTheme.light().textTheme.headlineMedium!;
      for (final slide in onboardingSlides) {
        for (final word in slide.title.split(' ')) {
          final painter = TextPainter(
            text: TextSpan(text: word, style: style),
            textDirection: TextDirection.ltr,
            textScaler: const TextScaler.linear(
              IviaOnboarding.titleMaxTextScale,
            ),
          )..layout();
          expect(painter.width, lessThanOrEqualTo(width), reason: word);
          painter.dispose();
        }
      }
    });
  });

  group('connexion et boutique', () {
    setUp(onboardingSeen);

    testWidgets('nouveau marchand : code, boutique, validation', (
      tester,
    ) async {
      await launchApp(tester);
      await tester.enterText(find.byType(TextField), _email);
      await tapText(tester, 'Recevoir le code');
      expect(
        find.textContaining('Même compte sur toutes les apps ivia'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '481902');
      await tester.pump();
      await tapText(tester, 'Vérifier le code');

      expect(find.text('Créez votre boutique'), findsOneWidget);
      expect(find.text('Étape 1 sur 2'), findsOneWidget);
      // Pas de rôle seller : aucune boutique demandée au serveur.
      expect(server.calls('GET', '/v1/seller/shops'), isEmpty);

      await fillShopForm(tester);
      await tapText(tester, 'Envoyer pour validation');

      expect(server.calls('PATCH', '/v1/me').single.body, {
        'accept_privacy_policy': true,
      });
      // Consentement daté avant la création de la boutique.
      final paths = server.requests
          .map((r) => '${r.method} ${r.path}')
          .toList();
      expect(
        paths.indexOf('PATCH /v1/me'),
        lessThan(paths.indexOf('POST /v1/shops')),
      );
      expect(server.calls('POST', '/v1/shops').single.body, {
        'name': 'Chez Afi',
        'category_id': '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d',
        'phone': '+22890123456',
        'address_text': 'Rue 248',
        'neighborhood_id': '5f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b',
        'location': {'lat': 6.1375, 'lng': 1.2123},
      });
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
        '/v1/auth/verify',
        (_) => FakeResponse.json(200, {...sessionBody(), 'user': _user()}),
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
      expect(
        find.textContaining('Cochez la case', skipOffstage: false),
        findsOneWidget,
      );
      expect(server.calls('POST', '/v1/shops'), isEmpty);
      expect(server.calls('PATCH', '/v1/me'), isEmpty);
    });

    testWidgets('échec puis nouvel essai : logo et consentement non renvoyés', (
      tester,
    ) async {
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
      expect(server.calls('PATCH', '/v1/me'), hasLength(1));
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
      await tester.enterText(find.byType(TextField), _email);
      await tapText(tester, 'Recevoir le code');
      await tester.pumpAndSettle();
      expect(server.calls('POST', '/v1/dev/otp').single.body, {
        'recipient': _email,
      });
      expect(
        (server.calls('POST', '/v1/auth/verify').single.body! as Map)['code'],
        '481902',
      );
      expect(find.text('Créez votre boutique'), findsOneWidget);
    });

    testWidgets('sans le drapeau de développement : code demandé', (
      tester,
    ) async {
      onboardingSeen();
      await launchApp(tester);
      await tester.enterText(find.byType(TextField), _email);
      await tapText(tester, 'Recevoir le code');
      expect(server.calls('POST', '/v1/dev/otp'), isEmpty);
      expect(find.text('Vérifiez vos e-mails'), findsOneWidget);
    });

    testWidgets('retour sur le formulaire : déconnexion', (tester) async {
      await launchApp(tester);
      await login(tester);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(server.calls('POST', '/v1/auth/logout'), hasLength(1));
      expect(find.text('Espace marchand'), findsOneWidget);
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

  group('relance avec une boutique', () {
    Future<void> withShop(String status) async {
      await signedInWith(_user(seller: true));
      server.on(
        'GET',
        '/v1/seller/shops',
        (_) => FakeResponse.json(200, {
          'items': [shopBody(status: status)],
        }),
      );
    }

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
      expect(find.textContaining('Votre boutique est publiée'), findsOneWidget);
    });

    testWidgets('« Préparer mes produits » : catalogue sans barre, retour', (
      tester,
    ) async {
      await withShop('pending_review');
      FakeCatalog(server);
      await launchApp(tester);
      await tapText(tester, 'Préparer mes produits');
      expect(find.text('Catalogue'), findsOneWidget);
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
      expect(find.textContaining('Votre boutique est publiée'), findsOneWidget);
    });
  });
}
