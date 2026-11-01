import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_seller/app/device_services.dart';
import 'package:ivia_seller/app/identity.dart';
import 'package:ivia_seller/features/catalog/catalog_screen.dart';
import 'package:ivia_seller/main.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Image PNG de 1 × 1 pixel.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _FakePicker implements PhotoPicker {
  Uint8List? next = _png;
  int? lastMaxSide;

  @override
  Future<Uint8List?> pick({
    PhotoSource source = PhotoSource.gallery,
    int maxSide = 1024,
  }) async {
    lastMaxSide = maxSide;
    return next;
  }
}

class _NoLocation implements LocationService {
  @override
  Future<LocationResult> current() async =>
      const LocationResult.found(GeoPoint(lat: 6.1375, lng: 1.2123));
}

/// Espaces typographiques remplacés par des espaces simples.
String plain(String s) => s.replaceAll(' ', ' ').replaceAll(' ', ' ');

/// Texte affiché, espaces typographiques compris (« 4 500 F »).
Finder textPlain(String text) => find.byWidgetPredicate(
  (w) => w is Text && plain(w.data ?? w.textSpan?.toPlainText() ?? '') == text,
);

void main() {
  late FakeApiServer server;
  late FakeCatalog catalog;
  late _FakePicker picker;

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
    picker = _FakePicker();
    server = FakeApiServer()
      ..on('GET', '/v1/me', (_) => FakeResponse.json(200, seller()))
      ..on('POST', '/v1/auth/logout', (_) => FakeResponse.json(204, null));
    withShop('published');
    catalog = FakeCatalog(server);
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
          photoPickerProvider.overrideWithValue(picker),
          locationServiceProvider.overrideWithValue(_NoLocation()),
          mapsEnabledProvider.overrideWithValue(false),
        ],
        child: const SellerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final target = find.text(text, skipOffstage: false).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Ouvre l'onglet Catalogue de la barre du bas.
  Future<void> openCatalog(WidgetTester tester) async {
    await launch(tester);
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(IviaFieldLabel, label),
    matching: find.byType(TextField),
  );

  Future<void> chooseCategory(WidgetTester tester, String item) async {
    final select = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(select);
    await tester.pumpAndSettle();
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  Future<void> addPhoto(WidgetTester tester) async {
    final add = find.bySemanticsLabel('Ajouter une photo').first;
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choisir une photo'));
    await tester.pumpAndSettle();
  }

  /// Étape 1 remplie, puis « Continuer ».
  Future<void> fillDetails(
    WidgetTester tester, {
    bool photo = true,
    String name = 'Riz parfumé 5 kg',
  }) async {
    if (photo) await addPhoto(tester);
    await tester.enterText(field('Nom du produit'), name);
    await tester.enterText(field('Prix'), '4500');
    await chooseCategory(tester, 'Alimentation');
    await tapText(tester, 'Continuer');
  }

  /// Dernière lecture de la liste.
  RecordedRequest lastList() =>
      server.calls('GET', '/v1/seller/shops/$shopId/products').last;

  Iterable<RecordedRequest> creates() =>
      server.calls('POST', '/v1/seller/shops/$shopId/products');

  group('catalogue', () {
    testWidgets('onglets, compteurs, lignes et barre du bas', (tester) async {
      catalog
        ..seed(name: 'Riz parfumé 5 kg')
        ..seed(name: 'Sucre 1 kg', stockMode: 'untracked', price: 800)
        ..seed(name: 'Lait en poudre', stock: 0, price: 2750)
        ..seed(name: 'Huile 1 L', status: 'draft')
        ..seed(name: 'Bissap', status: 'withdrawn');
      await openCatalog(tester);

      expect(find.text('Chez Afi · 5 produits'), findsOneWidget);
      expect(find.bySemanticsLabel('En vente, 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Brouillons, 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Retirés, 1'), findsOneWidget);
      expect(textPlain('4 500 F'), findsOneWidget);
      expect(find.text('Alimentation · Stock 12'), findsOneWidget);
      expect(find.text('Stock non suivi'), findsOneWidget);
      expect(find.text('Épuisé · à réapprovisionner'), findsOneWidget);
      expect(find.text('Huile 1 L'), findsNothing);
      // Catalogue choisi dans la barre du bas.
      expect(find.byType(IviaBottomNav), findsOneWidget);
      expect(lastList().query['status'], 'active');

      await tester.tap(find.textContaining('Brouillons'));
      await tester.pumpAndSettle();
      expect(find.text('Huile 1 L'), findsOneWidget);
      expect(find.text('Riz parfumé 5 kg'), findsNothing);
      expect(lastList().query['status'], 'draft');
    });

    testWidgets('recherche envoyée au serveur après le délai de frappe', (
      tester,
    ) async {
      catalog
        ..seed(name: 'Café moulu')
        ..seed(name: 'Riz parfumé 5 kg');
      await openCatalog(tester);
      await tester.enterText(find.byType(TextField), 'cafe');
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        server.requests.where((r) => r.query['q'] != null),
        isEmpty,
        reason: 'pas de requête pendant la frappe',
      );
      await tester.pump(searchDelay);
      await tester.pumpAndSettle();
      expect(lastList().query['q'], 'cafe');
      expect(find.text('Café moulu'), findsOneWidget);
      expect(find.text('Riz parfumé 5 kg'), findsNothing);

      await tester.enterText(find.byType(TextField), 'tomate');
      await tester.pump(searchDelay);
      await tester.pumpAndSettle();
      expect(
        find.text('Aucun produit ne correspond à « tomate ».'),
        findsOneWidget,
      );
      // Effacer : liste complète tout de suite.
      await tester.tap(find.byTooltip('Effacer la recherche'));
      await tester.pumpAndSettle();
      expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
    });

    testWidgets('listes vides : un message par onglet', (tester) async {
      await openCatalog(tester);
      expect(
        find.text('Aucun produit en vente. Ajoutez votre premier produit.'),
        findsOneWidget,
      );
      expect(find.text('Ajouter un produit'), findsOneWidget);
      await tester.tap(find.textContaining('Brouillons'));
      await tester.pumpAndSettle();
      expect(find.text('Aucun brouillon.'), findsOneWidget);
      await tester.tap(find.textContaining('Retirés'));
      await tester.pumpAndSettle();
      expect(find.text('Aucun produit retiré.'), findsOneWidget);
    });

    testWidgets('réseau coupé : message et « Réessayer » sans quitter', (
      tester,
    ) async {
      catalog.seed(name: 'Riz parfumé 5 kg');
      catalog.failures['GET /v1/seller/shops/$shopId/products'] =
          FakeResponse.networkError();
      await openCatalog(tester);
      expect(
        find.text(
          'Impossible de charger vos produits. Vérifiez votre connexion.',
        ),
        findsOneWidget,
      );
      await tapText(tester, 'Réessayer');
      expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
    });

    testWidgets('défilement : la page suivante se charge', (tester) async {
      for (var i = 0; i < 25; i++) {
        catalog.seed(name: 'Produit ${i.toString().padLeft(2, '0')}');
      }
      await openCatalog(tester);
      expect(lastList().query['offset'], '0');
      await tester.scrollUntilVisible(
        find.text('Produit 00'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        server.requests.where((r) => r.query['offset'] == '20'),
        hasLength(1),
      );
      expect(find.text('Produit 00'), findsOneWidget);
    });

    testWidgets('retrait confirmé, onglet Retirés, puis « Annuler »', (
      tester,
    ) async {
      catalog.seed(name: 'Riz parfumé 5 kg');
      await openCatalog(tester);
      await tester.tap(find.byTooltip('Actions pour Riz parfumé 5 kg'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer de la vente'));
      await tester.pumpAndSettle();
      expect(find.text('Retirer ce produit de la vente ?'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Retirer de la vente'),
      );
      await tester.pumpAndSettle();

      final patch = server.calls(
        'PATCH',
        '/v1/seller/products/${catalog.products.single['id']}',
      );
      expect((patch.single.body! as Map)['is_active'], isFalse);
      expect(find.bySemanticsLabel('Retirés, 1'), findsOneWidget);
      expect(find.textContaining('Retiré '), findsOneWidget);
      expect(find.text('Riz parfumé 5 kg retiré de la vente'), findsOneWidget);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(catalog.products.single['status'], 'active');
      expect(find.bySemanticsLabel('En vente, 1'), findsOneWidget);
    });

    testWidgets('« Remettre » : en vente ; sans photo : refusé', (
      tester,
    ) async {
      catalog
        ..seed(name: 'Bissap', status: 'withdrawn')
        ..seed(name: 'Tomate', status: 'withdrawn', images: 0);
      await openCatalog(tester);
      await tester.tap(find.textContaining('Retirés'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Remettre Tomate en vente'));
      await tester.pumpAndSettle();
      expect(find.text('Ajoutez au moins une photo.'), findsOneWidget);
      expect(catalog.byName('Tomate')['status'], 'withdrawn');

      await tester.tap(find.bySemanticsLabel('Remettre Bissap en vente'));
      await tester.pumpAndSettle();
      expect(catalog.byName('Bissap')['status'], 'active');
      expect(find.text('Bissap remis en vente'), findsOneWidget);
      expect(find.text('Bissap'), findsNothing);
    });

    testWidgets('ajuster le stock depuis le menu', (tester) async {
      final id = catalog.seed(name: 'Riz parfumé 5 kg')['id'];
      await openCatalog(tester);
      await tester.tap(find.byTooltip('Actions pour Riz parfumé 5 kg'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajuster le stock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ajouter 1'));
      await tester.pump();
      await tapText(tester, 'Valider');
      expect(server.calls('PUT', '/v1/seller/products/$id/stock').single.body, {
        'quantity': 13,
        'note': '',
      });
      expect(find.text('Alimentation · Stock 13'), findsOneWidget);
    });

    testWidgets('police à 200 % sur 320 dp : catalogue sans débordement', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      catalog
        ..seed(name: 'Riz parfumé long grain de Thaïlande, sac de 5 kg')
        ..seed(name: 'Bissap', status: 'withdrawn');
      await openCatalog(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.textContaining('Retirés'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('nouveau produit', () {
    testWidgets('deux étapes, aperçu, publication avec photo', (tester) async {
      await openCatalog(tester);
      await tester.tap(find.bySemanticsLabel('Ajouter un produit').first);
      await tester.pumpAndSettle();
      expect(find.text('Nouveau produit'), findsOneWidget);
      expect(find.text('1 sur 2'), findsOneWidget);

      await fillDetails(tester);
      expect(picker.lastMaxSide, 1600);
      expect(find.text('Livraison et stock'), findsOneWidget);
      await tapText(tester, 'Moyen');
      await tester.tap(find.byTooltip('Ajouter 1'));
      await tester.pump();
      await tapText(tester, "Voir l'aperçu");

      expect(find.text('Aperçu'), findsOneWidget);
      expect(find.text('1 photo'), findsOneWidget);
      expect(find.text('Prix et catégorie'), findsOneWidget);
      expect(find.text('Stock suivi : 2'), findsOneWidget);
      expect(find.text('Colis moyen'), findsOneWidget);
      expect(find.textContaining('Chez Afi · Tokoin'), findsOneWidget);
      expect(server.calls('POST', '/v1/uploads'), isEmpty);

      await tapText(tester, 'Publier');
      expect(server.calls('POST', '/v1/uploads').single.body, {
        'purpose': 'product_image',
        'content_type': 'image/jpeg',
        'size_bytes': _png.length,
      });
      expect(server.calls('PUT', '/products/u1.jpg'), hasLength(1));
      expect(creates().single.body, {
        'category_id': 'c1000000-0000-4000-8000-000000000001',
        'name': 'Riz parfumé 5 kg',
        'description': '',
        'price_xof': 4500,
        'parcel_size': 'medium',
        'image_keys': ['products/u1.jpg'],
        'stock_mode': 'tracked',
        'stock_quantity': 2,
        'is_active': true,
      });
      expect(find.text('Produit publié'), findsOneWidget);
      expect(
        find.text(
          'Il est visible maintenant par les acheteurs autour de Tokoin.',
        ),
        findsOneWidget,
      );

      await tapText(tester, 'Retour au catalogue');
      expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
      expect(find.bySemanticsLabel('En vente, 1'), findsOneWidget);
    });

    testWidgets('validations des deux étapes', (tester) async {
      await openCatalog(tester);
      await tester.tap(find.bySemanticsLabel('Ajouter un produit').first);
      await tester.pumpAndSettle();
      await tapText(tester, 'Continuer');
      expect(find.text('Le nom compte de 2 à 150 caractères.'), findsOneWidget);
      expect(find.text('Prix entre 1 et 100 000 000 FCFA.'), findsOneWidget);
      expect(find.text('Choisissez une catégorie.'), findsOneWidget);
      expect(find.text('Livraison et stock'), findsNothing);

      await fillDetails(tester, photo: false);
      await tapText(tester, "Voir l'aperçu");
      expect(find.text('Choisissez la taille du colis.'), findsOneWidget);
      await tapText(tester, 'Petit');
      await tapText(tester, "Voir l'aperçu");
      expect(find.text('Ajoutez au moins une photo.'), findsOneWidget);
      expect(find.text('Aperçu'), findsNothing);
    });

    testWidgets('brouillon sans photo, puis reprise et publication', (
      tester,
    ) async {
      await openCatalog(tester);
      await tester.tap(find.bySemanticsLabel('Ajouter un produit').first);
      await tester.pumpAndSettle();
      await fillDetails(tester, photo: false);
      await tapText(tester, 'Grand');
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tapText(tester, 'Brouillon');

      final body = creates().single.body! as Map;
      expect(body['is_active'], isFalse);
      expect(body['stock_mode'], 'untracked');
      expect(body['image_keys'], isEmpty);
      expect(
        find.text('Brouillon enregistré : Riz parfumé 5 kg'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Brouillons, 1'), findsOneWidget);

      await tapText(tester, 'Riz parfumé 5 kg');
      expect(find.text('Brouillon'), findsWidgets);
      expect(
        tester.widget<TextField>(field('Nom du produit')).controller!.text,
        'Riz parfumé 5 kg',
      );
      await addPhoto(tester);
      await tapText(tester, 'Continuer');
      // Mode de stock figé après l'enregistrement.
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      await tapText(tester, "Voir l'aperçu");
      await tapText(tester, 'Publier');

      expect(creates(), hasLength(1), reason: 'pas de second produit');
      final id = catalog.products.single['id'];
      final patch = server.calls('PATCH', '/v1/seller/products/$id').single;
      expect((patch.body! as Map)['is_active'], isTrue);
      expect((patch.body! as Map).containsKey('stock_mode'), isFalse);
      expect(catalog.products.single['status'], 'active');
      expect(find.text('Produit publié'), findsOneWidget);
    });

    testWidgets('échec réseau : nouvel essai sans renvoyer la photo', (
      tester,
    ) async {
      await openCatalog(tester);
      await tester.tap(find.bySemanticsLabel('Ajouter un produit').first);
      await tester.pumpAndSettle();
      await fillDetails(tester);
      await tapText(tester, 'Moyen');
      await tapText(tester, "Voir l'aperçu");
      catalog.failures['POST /v1/seller/shops'] = FakeResponse.networkError();
      await tapText(tester, 'Publier');
      expect(find.text('Produit publié'), findsNothing);
      expect(find.textContaining('connexion'), findsOneWidget);
      expect(catalog.products, isEmpty);

      await tapText(tester, 'Publier');
      expect(server.calls('POST', '/v1/uploads'), hasLength(1));
      expect(catalog.products, hasLength(1));
      expect(find.text('Produit publié'), findsOneWidget);
    });

    testWidgets('double appui sur « Publier » : un seul produit', (
      tester,
    ) async {
      await openCatalog(tester);
      await tester.tap(find.bySemanticsLabel('Ajouter un produit').first);
      await tester.pumpAndSettle();
      await fillDetails(tester);
      await tapText(tester, 'Moyen');
      await tapText(tester, "Voir l'aperçu");
      final publish = find.widgetWithText(FilledButton, 'Publier');
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.tap(publish, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(creates(), hasLength(1));
    });

    testWidgets('boutique en validation : visible dès la validation', (
      tester,
    ) async {
      withShop('pending_review');
      await launch(tester);
      await tapText(tester, 'Préparer mes produits');
      await tester.tap(find.bySemanticsLabel('Ajouter un produit').first);
      await tester.pumpAndSettle();
      await fillDetails(tester);
      await tapText(tester, 'Petit');
      await tapText(tester, "Voir l'aperçu");
      await tapText(tester, 'Publier');
      expect(
        find.text('Il sera visible dès que votre boutique sera validée.'),
        findsOneWidget,
      );
    });

    testWidgets('quitter avec une saisie : confirmation', (tester) async {
      await openCatalog(tester);
      await tester.tap(find.bySemanticsLabel('Ajouter un produit').first);
      await tester.pumpAndSettle();
      await tester.enterText(field('Nom du produit'), 'Riz');
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(find.text('Abandonner ce produit ?'), findsOneWidget);
      await tester.tap(find.text('Continuer').last);
      await tester.pumpAndSettle();
      expect(find.text('Nouveau produit'), findsOneWidget);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(find.text('Catalogue'), findsWidgets);
      expect(creates(), isEmpty);
    });

    testWidgets('photos : principale changée, suppression', (tester) async {
      await openCatalog(tester);
      await tester.tap(find.bySemanticsLabel('Ajouter un produit').first);
      await tester.pumpAndSettle();
      await addPhoto(tester);
      await addPhoto(tester);
      expect(find.bySemanticsLabel('Photo 2 sur 2'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Photo 2 sur 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mettre en principale'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Photo principale'));
      await tester.pumpAndSettle();
      expect(find.text('Mettre en principale'), findsNothing);
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^Photo ')), findsOneWidget);
    });

    testWidgets('police à 200 % sur 320 dp : formulaire sans débordement', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openCatalog(tester);
      await tester.tap(find.bySemanticsLabel('Ajouter un produit').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await fillDetails(tester);
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Moyen');
      await tapText(tester, "Voir l'aperçu");
      expect(tester.takeException(), isNull);
    });
  });

  group('modifier', () {
    testWidgets('prix modifié et enregistré', (tester) async {
      final id = catalog.seed(name: 'Riz parfumé 5 kg')['id'];
      await openCatalog(tester);
      await tapText(tester, 'Riz parfumé 5 kg');
      expect(find.text('Modifier'), findsOneWidget);
      expect(
        find.textContaining('Visible par les acheteurs depuis'),
        findsOneWidget,
      );
      await tester.enterText(field('Prix'), '4250');
      await tapText(tester, 'Enregistrer les modifications');
      final patch = server.calls('PATCH', '/v1/seller/products/$id').single;
      expect((patch.body! as Map)['price_xof'], 4250);
      expect((patch.body! as Map)['is_active'], isTrue);
      expect(find.text('Modifications enregistrées'), findsOneWidget);
      expect(textPlain('4 250 F'), findsOneWidget);
    });

    testWidgets('stock ajusté, enregistré avec le produit', (tester) async {
      final id = catalog.seed(name: 'Riz parfumé 5 kg')['id'];
      await openCatalog(tester);
      await tapText(tester, 'Riz parfumé 5 kg');
      await tapText(tester, 'Suivi · 12');
      await tester.tap(find.byTooltip('Retirer 1'));
      await tester.pump();
      await tapText(tester, 'Valider');
      expect(find.text('Suivi · 11'), findsOneWidget);
      expect(server.calls('PUT', '/v1/seller/products/$id/stock'), isEmpty);
      await tapText(tester, 'Enregistrer les modifications');
      expect(server.calls('PUT', '/v1/seller/products/$id/stock').single.body, {
        'quantity': 11,
        'note': '',
      });
    });

    testWidgets('catégorie refusée par le serveur : message sous le champ', (
      tester,
    ) async {
      catalog.seed(name: 'Riz parfumé 5 kg');
      await openCatalog(tester);
      await tapText(tester, 'Riz parfumé 5 kg');
      catalog.failures['PATCH /v1/seller/products'] = FakeResponse.error(
        400,
        'validation_failed',
        'Données invalides.',
        fields: {'category_id': 'Catégorie inconnue.'},
      );
      await tapText(tester, 'Enregistrer les modifications');
      expect(find.text('Catégorie inconnue.'), findsOneWidget);
      expect(find.text('Modifier'), findsOneWidget);
    });

    testWidgets('« Retirer de la vente » : confirmation, onglet Retirés', (
      tester,
    ) async {
      catalog.seed(name: 'Riz parfumé 5 kg');
      await openCatalog(tester);
      await tapText(tester, 'Riz parfumé 5 kg');
      await tapText(tester, 'Retirer de la vente');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Retirer de la vente'),
      );
      await tester.pumpAndSettle();
      expect(catalog.products.single['status'], 'withdrawn');
      expect(find.bySemanticsLabel('Retirés, 1'), findsOneWidget);
      expect(find.byType(IviaBottomNav), findsOneWidget);
    });

    testWidgets('produit retiré remis en vente par l\'interrupteur', (
      tester,
    ) async {
      final id = catalog.seed(name: 'Bissap', status: 'withdrawn')['id'];
      await openCatalog(tester);
      await tester.tap(find.textContaining('Retirés'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Bissap');
      expect(find.textContaining('Non visible depuis'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tapText(tester, 'Enregistrer les modifications');
      final patch = server.calls('PATCH', '/v1/seller/products/$id').single;
      expect((patch.body! as Map)['is_active'], isTrue);
      expect(catalog.byName('Bissap')['status'], 'active');
    });
  });

  testWidgets('police à 200 % sur 320 dp : « Modifier » sans débordement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    catalog.seed(name: 'Riz parfumé 5 kg', images: 3);
    await openCatalog(tester);
    await tapText(tester, 'Riz parfumé 5 kg');
    expect(find.text('Enregistrer les modifications'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compte : déconnexion', (tester) async {
    await launch(tester);
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Awa Mensah'), findsOneWidget);
    await tapText(tester, 'Se déconnecter');
    expect(server.calls('POST', '/v1/auth/logout'), hasLength(1));
    expect(find.text('Espace marchand'), findsOneWidget);
  });
}
