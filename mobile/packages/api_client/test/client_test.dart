import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';

void main() {
  late FakeApiServer server;
  late IviaApiClient client;
  var unauthorized = 0;

  setUp(() {
    server = FakeApiServer();
    unauthorized = 0;
    client = IviaApiClient(
      config: ApiConfig(baseUrl: Uri.parse('http://api.test')),
      adapter: server,
      onUnauthorized: () => unauthorized++,
    );
  });

  test('requestOtp : canal e-mail, adresse nettoyée, délais lus', () async {
    server.on('POST', '/v1/auth/otp', (_) => FakeResponse.json(202, otpBody));
    final otp = await client.requestOtp('  Awa.Mensah@Gmail.com ');
    expect(server.last.body, {
      'channel': 'email',
      'recipient': 'awa.mensah@gmail.com',
    });
    expect(otp.resendAfter, const Duration(seconds: 60));
    expect(otp.expiresIn, const Duration(minutes: 10));
  });

  test('verifyOtp : session, nouveau compte et profil', () async {
    server.on(
      'POST',
      '/v1/auth/verify',
      (_) => FakeResponse.json(200, sessionBody()),
    );
    final session = await client.verifyOtp('awa@test.tg', '481902');
    expect(server.last.body, {
      'channel': 'email',
      'recipient': 'awa@test.tg',
      'code': '481902',
    });
    expect(session.token, 'jeton-secret');
    expect(session.isNewUser, isTrue);
    expect(session.user.email, 'awa@test.tg');
    expect(session.user.profileComplete, isFalse);
    expect(server.last.headers['authorization'], isNull);
  });

  test('le jeton est envoyé une fois défini, puis retiré', () async {
    server.on('GET', '/v1/me', (_) => FakeResponse.json(200, userBody()));
    client.token = 'jeton-secret';
    await client.getMe();
    expect(server.last.headers['authorization'], 'Bearer jeton-secret');

    client.token = null;
    await client.getMe();
    expect(server.last.headers['authorization'], isNull);
  });

  test('updateMe : seuls les champs fournis sont envoyés', () async {
    server.on(
      'PATCH',
      '/v1/me',
      (_) => FakeResponse.json(200, userBody(complete: true)),
    );
    final user = await client.updateMe(
      firstName: 'Awa',
      lastName: 'Mensah',
      phone: '+22890123456',
      acceptPrivacyPolicy: true,
    );
    expect(server.last.body, {
      'first_name': 'Awa',
      'last_name': 'Mensah',
      'phone': '+22890123456',
      'accept_privacy_policy': true,
    });
    expect(user.profileComplete, isTrue);
    expect(user.privacyConsentAt, DateTime.utc(2026, 10, 31, 9));
  });

  test('erreur du serveur : code, message et champs', () async {
    server.on(
      'PATCH',
      '/v1/me',
      (_) => FakeResponse.error(
        400,
        'validation_failed',
        'Données invalides.',
        fields: {'phone': 'Numéro mobile togolais attendu.'},
      ),
    );
    await expectLater(
      client.updateMe(phone: '123'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'validation_failed')
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.fields['phone'], 'fields', isNotNull),
      ),
    );
  });

  test('401 avec un jeton : session refusée signalée', () async {
    server.on(
      'GET',
      '/v1/me',
      (_) => FakeResponse.error(401, 'unauthorized', 'Session expirée.'),
    );
    client.token = 'jeton-expire';
    await expectLater(client.getMe(), throwsA(isA<ApiException>()));
    expect(unauthorized, 1);
  });

  test('401 tardif d\'une ancienne session : pas de signalement', () async {
    final reply = Completer<FakeResponse>();
    server.on('GET', '/v1/me', (_) => reply.future);
    client.token = 'ancien-jeton';
    final call = client.getMe();
    await pumpEventQueue();
    client.token = 'nouveau-jeton';
    reply.complete(FakeResponse.error(401, 'unauthorized', 'Session expirée.'));
    await expectLater(call, throwsA(isA<ApiException>()));
    expect(unauthorized, 0);
  });

  test('401 sans jeton (code faux) : pas de signalement', () async {
    server.on(
      'POST',
      '/v1/auth/verify',
      (_) => FakeResponse.error(401, 'otp_invalid', 'Code incorrect.'),
    );
    await expectLater(
      client.verifyOtp('a@b.tg', '000000'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'otp_invalid')),
    );
    expect(unauthorized, 0);
  });

  test('réseau coupé : erreur réseau en français', () async {
    server.on('GET', '/v1/me', (_) => FakeResponse.networkError());
    await expectLater(
      client.getMe(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.isNetwork, 'isNetwork', isTrue)
            .having((e) => e.message, 'message', contains('connexion')),
      ),
    );
  });

  test('réponse illisible : erreur générique', () async {
    server.on('GET', '/v1/me', (_) => FakeResponse.json(500, 'oups'));
    await expectLater(
      client.getMe(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ApiException.unknownCode)
            .having((e) => e.statusCode, 'statusCode', 500),
      ),
    );
  });

  test('délais de connexion et de réponse', () {
    final dio = client.debugDio;
    expect(dio.options.connectTimeout, const Duration(seconds: 10));
    expect(dio.options.receiveTimeout, const Duration(seconds: 15));
    expect(dio.interceptors.whereType<LogInterceptor>(), isEmpty);
  });

  group('boutiques', () {
    test('catégories et quartiers', () async {
      server
        ..on(
          'GET',
          '/v1/shop-categories',
          (_) => FakeResponse.json(200, shopCategoriesBody),
        )
        ..on(
          'GET',
          '/v1/neighborhoods',
          (_) => FakeResponse.json(200, neighborhoodsBody),
        );
      final categories = await client.shopCategories();
      expect(categories.map((c) => c.name), ['Alimentation', 'Mode et beauté']);
      final hoods = await client.neighborhoods();
      expect(hoods.first.name, 'Tokoin');
    });

    test('création : champs envoyés, boutique en attente', () async {
      server.on('POST', '/v1/shops', (_) => FakeResponse.json(201, shopBody()));
      final shop = await client.createShop(
        const ShopDraft(
          name: 'Chez Afi',
          categoryId: 'cat-1',
          phone: '+22890123456',
          addressText: 'Rue 248',
          neighborhoodId: null,
          location: GeoPoint(lat: 6.1375, lng: 1.2123),
          logoKey: 'logos/abc.jpg',
        ),
      );
      expect(server.last.body, {
        'name': 'Chez Afi',
        'category_id': 'cat-1',
        'phone': '+22890123456',
        'address_text': 'Rue 248',
        'neighborhood_id': null,
        'location': {'lat': 6.1375, 'lng': 1.2123},
        'logo_key': 'logos/abc.jpg',
      });
      expect(shop.status, ShopStatus.pendingReview);
      expect(shop.neighborhoodName, 'Tokoin');
    });

    test('mes boutiques : statut et motif', () async {
      server.on(
        'GET',
        '/v1/seller/shops',
        (_) => FakeResponse.json(200, {
          'items': [shopBody(status: 'rejected')],
        }),
      );
      final shops = await client.myShops();
      expect(shops.single.status, ShopStatus.rejected);
      expect(shops.single.statusReason, isNotEmpty);
    });

    test('envoi de fichier : URL signée, sans jeton de session', () async {
      server
        ..on(
          'POST',
          '/v1/uploads',
          (_) => FakeResponse.json(201, {
            'object_key': 'shop_logo/u1/abc.jpg',
            'upload': {
              'method': 'PUT',
              'url': 'https://stockage.test/shop_logo/u1/abc.jpg?signature=x',
              'headers': {'Content-Type': 'image/jpeg'},
              'expires_at': '2026-10-31T10:05:00Z',
            },
          }),
        )
        ..on(
          'PUT',
          '/shop_logo/u1/abc.jpg',
          (_) => FakeResponse.json(200, null),
        );
      client.token = 'jeton-secret';

      final prepared = await client.prepareUpload(
        purpose: 'shop_logo',
        contentType: 'image/jpeg',
        sizeBytes: 3,
      );
      expect(server.last.body, {
        'purpose': 'shop_logo',
        'content_type': 'image/jpeg',
        'size_bytes': 3,
      });
      await client.upload(prepared, [1, 2, 3]);

      final put = server.last;
      expect(put.host, 'stockage.test');
      expect(put.headers['authorization'], isNull);
      expect(put.headers['content-type'], 'image/jpeg');
      expect(put.body, [1, 2, 3]);
      expect(prepared.objectKey, 'shop_logo/u1/abc.jpg');
    });

    test('envoi de fichier : coupure réseau traduite', () async {
      server.on('PUT', '/f.jpg', (_) => FakeResponse.networkError());
      await expectLater(
        client.upload(
          const PreparedUpload(
            objectKey: 'f.jpg',
            url: 'https://stockage.test/f.jpg',
            headers: {},
          ),
          [1],
        ),
        throwsA(
          isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue),
        ),
      );
    });
  });

  group('pièces du marchand', () {
    test('boutique : types des pièces, inconnus tolérés, absentes', () {
      final shop = Shop.fromJson({
        ...shopBody(documents: ['id_card', 'business_registration']),
      });
      expect(shop.merchantDocuments, [
        MerchantDocumentKind.idCard,
        MerchantDocumentKind.businessRegistration,
      ]);
      final unknown = Shop.fromJson(shopBody(documents: ['tax_card']));
      expect(unknown.merchantDocuments, [MerchantDocumentKind.unknown]);
      final none = Shop.fromJson(shopBody(documents: []));
      expect(none.merchantDocuments, isEmpty);
      final absent = Shop.fromJson(shopBody()..remove('merchant_documents'));
      expect(absent.merchantDocuments, isNull);
      final updated = none.withDocuments([MerchantDocumentKind.idCard]);
      expect(updated.merchantDocuments, [MerchantDocumentKind.idCard]);
      expect(updated.name, none.name);
      expect(updated.status, none.status);
    });

    test('dépôt : URL signée privée, puis rattachement', () async {
      final docs = FakeMerchantDocuments(server);
      final prepared = await client.prepareUpload(
        purpose: 'merchant_document',
        contentType: 'image/jpeg',
        sizeBytes: 3,
      );
      await client.upload(prepared, [1, 2, 3]);
      final kinds = await client.addMerchantDocument(
        MerchantDocumentKind.idCard,
        prepared.objectKey,
      );
      expect(server.last.body, {
        'kind': 'id_card',
        'object_key': prepared.objectKey,
      });
      expect(kinds, [MerchantDocumentKind.idCard]);
      expect(docs.kinds, ['id_card']);
      expect(server.calls('GET', '/v1/seller/documents'), isEmpty);
    });

    test('faux serveur : fichier non envoyé refusé', () async {
      FakeMerchantDocuments(server);
      await expectLater(
        client.addMerchantDocument(
          MerchantDocumentKind.idCard,
          'merchants/u1/inconnu.jpg',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.fields['object_key'],
            'object_key',
            isNotNull,
          ),
        ),
      );
    });

    test('dix pièces au plus : too_many_documents', () async {
      FakeMerchantDocuments(server, documents: List.filled(10, 'other'));
      final prepared = await client.prepareUpload(
        purpose: 'merchant_document',
        contentType: 'image/jpeg',
        sizeBytes: 3,
      );
      await client.upload(prepared, [1, 2, 3]);
      await expectLater(
        client.addMerchantDocument(
          MerchantDocumentKind.businessRegistration,
          prepared.objectKey,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'too_many_documents',
          ),
        ),
      );
    });
  });

  group('livreur', () {
    test('aucun dossier : null', () async {
      server.on(
        'GET',
        '/v1/driver/me',
        (_) =>
            FakeResponse.error(404, 'driver_not_found', 'Livreur introuvable.'),
      );
      expect(await client.driverMe(), isNull);
    });

    test('dossier : statut, véhicule, types de documents', () async {
      server.on(
        'GET',
        '/v1/driver/me',
        (_) => FakeResponse.json(200, driverBody(review: 'rejected')),
      );
      final dossier = await client.driverMe();
      expect(dossier?.review, DriverReview.rejected);
      expect(dossier?.reviewNote, isNotEmpty);
      expect(dossier?.vehicleType, VehicleType.motorbike);
      expect(dossier?.documents, hasLength(3));
    });

    test('candidature et document', () async {
      server
        ..on(
          'PUT',
          '/v1/driver/application',
          (_) => FakeResponse.json(200, driverBody(documents: [])),
        )
        ..on(
          'POST',
          '/v1/driver/application/documents',
          (_) => FakeResponse.json(201, driverBody(documents: ['id_card'])),
        );
      await client.applyAsDriver(
        vehicleType: VehicleType.car,
        vehiclePlate: 'TG 1 AB',
      );
      expect(server.last.body, {
        'vehicle_type': 'car',
        'vehicle_plate': 'TG 1 AB',
      });
      final dossier = await client.addDriverDocument(
        DriverDocumentKind.idCard,
        'k1',
      );
      expect(server.last.body, {'kind': 'id_card', 'object_key': 'k1'});
      expect(dossier.documents, [DriverDocumentKind.idCard]);
    });

    test('autre erreur du dossier : levée', () async {
      server.on('GET', '/v1/driver/me', (_) => FakeResponse.networkError());
      await expectLater(client.driverMe(), throwsA(isA<ApiException>()));
    });
  });

  group('catalogue', () {
    late FakeCatalog catalog;

    setUp(() => catalog = FakeCatalog(server));

    test('produit lu depuis le contrat : état, dates, stock, photos', () {
      final p = Product.fromJson(productBody(status: 'withdrawn', stock: 0));
      expect(p.status, ProductStatus.withdrawn);
      expect(p.publishedAt, DateTime.utc(2026, 10, 12, 9));
      expect(p.withdrawnAt, DateTime.utc(2026, 10, 24, 9));
      expect(p.priceXof, 4500);
      expect(p.parcelSize, ParcelSize.medium);
      expect(p.stockMode, StockMode.tracked);
      expect(p.soldOut, isTrue);
      expect(p.images.single.objectKey, startsWith('products/'));
      final untracked = Product.fromJson(
        productBody(status: 'draft', stockMode: 'untracked', images: 0),
      );
      expect(untracked.publishedAt, isNull);
      expect(untracked.stockQuantity, isNull);
      expect(untracked.soldOut, isFalse);
    });

    test(
      'liste : état, recherche nettoyée et pagination dans l\'URL',
      () async {
        catalog
          ..seed(name: 'Café moulu')
          ..seed(name: 'Riz', status: 'draft');
        final page = await client.sellerProducts(
          shopId,
          status: ProductStatus.active,
          query: '  cafe ',
          offset: 0,
          limit: 1,
        );
        expect(server.last.query, {
          'status': 'active',
          'q': 'cafe',
          'offset': '0',
          'limit': '1',
        });
        expect(page.items.single.name, 'Café moulu');
        expect(page.nextOffset, isNull);

        await client.sellerProducts(shopId);
        expect(server.last.query, {'offset': '0', 'limit': '20'});
      },
    );

    test('compteurs par état', () async {
      catalog
        ..seed(name: 'A')
        ..seed(name: 'B', status: 'draft')
        ..seed(name: 'C', status: 'withdrawn');
      final counts = await client.productCounts(shopId);
      expect((counts.active, counts.draft, counts.withdrawn), (1, 1, 1));
      expect(counts.total, 3);
      expect(counts.of(ProductStatus.draft), 1);
    });

    test('création : brouillon puis publication, champs envoyés', () async {
      const input = ProductInput(
        categoryId: 'c1',
        name: 'Riz parfumé 5 kg',
        description: '',
        priceXof: 4500,
        parcelSize: ParcelSize.medium,
        imageKeys: ['products/u1.jpg'],
        stockMode: StockMode.tracked,
        stockQuantity: 12,
        isActive: false,
      );
      final draft = await client.createProduct(shopId, input);
      expect(server.last.body, {
        'category_id': 'c1',
        'name': 'Riz parfumé 5 kg',
        'description': '',
        'price_xof': 4500,
        'parcel_size': 'medium',
        'image_keys': ['products/u1.jpg'],
        'stock_mode': 'tracked',
        'stock_quantity': 12,
        'is_active': false,
      });
      expect(draft.status, ProductStatus.draft);

      final published = await client.updateProduct(
        draft.id,
        const ProductInput(
          categoryId: 'c1',
          name: 'Riz parfumé 5 kg',
          description: '',
          priceXof: 4500,
          parcelSize: ParcelSize.medium,
          imageKeys: ['products/u1.jpg'],
          isActive: true,
        ),
      );
      expect(server.last.method, 'PATCH');
      expect((server.last.body! as Map).containsKey('stock_mode'), isFalse);
      expect(published.status, ProductStatus.active);
      expect(published.publishedAt, isNotNull);
    });

    test('stock et produit lu', () async {
      final id = catalog.seed(name: 'Riz')['id'] as String;
      final p = await client.setStock(id, 0);
      expect(server.last.body, {'quantity': 0, 'note': ''});
      expect(p.soldOut, isTrue);
      expect((await client.sellerProduct(id)).stockQuantity, 0);
    });

    test('catégories de produits avec leur parent', () async {
      final categories = await client.productCategories();
      expect(categories.map((c) => c.name), [
        'Alimentation',
        'Céréales',
        'Boissons',
      ]);
      expect(categories[1].parentId, categories[0].id);
    });
  });

  group('recherche', () {
    late FakeSearch search;
    const lome = GeoPoint(lat: 6.1375, lng: 1.2123);

    setUp(() {
      search = FakeSearch(server);
      final afi = search.shop('Chez Afi');
      final wax = search.shop(
        'Wax & Co',
        neighborhoodId: beId,
        location: const GeoPoint(lat: 6.1280, lng: 1.2200),
      );
      search
        ..product(afi, 'Riz parfumé 5 kg')
        ..product(afi, 'Café moulu', price: 1200, stock: 0)
        ..product(
          wax,
          'Riz brisé 25 kg',
          price: 14000,
          categoryId: 'c1000000-0000-4000-8000-000000000002',
        );
    });

    test('position : lat, lng, rayon et distance renvoyée', () async {
      final page = await client.searchProducts(
        const SearchQuery(
          text: ' riz ',
          point: lome,
          radiusM: 2000,
          sort: SearchSort.distance,
        ),
        limit: 10,
      );
      expect(server.last.query, {
        'q': 'riz',
        // Arrondie à 3 décimales (environ 110 m) : elle part dans l'URL.
        'lat': 6.1375.toStringAsFixed(3),
        'lng': '1.212',
        'radius_m': '2000',
        'sort': 'distance',
        'offset': '0',
        'limit': '10',
      });
      expect(page.items.map((p) => p.name), [
        'Riz parfumé 5 kg',
        'Riz brisé 25 kg',
      ]);
      // Position arrondie : à moins de 110 m près.
      expect(page.items.first.distanceM, lessThan(110));
      expect(page.items.last.distanceM, greaterThan(1000));
      expect(page.items.first.shopName, 'Chez Afi');
    });

    test(
      'quartier et filtres produits ; boutiques sans filtres produits',
      () async {
        const query = SearchQuery(
          neighborhoodId: tokoinId,
          categoryId: 'c1000000-0000-4000-8000-000000000001',
          minPrice: 1000,
          maxPrice: 5000,
          inStockOnly: true,
          sort: SearchSort.priceAsc,
        );
        final products = await client.searchProducts(query);
        expect(server.last.query, {
          'neighborhood_id': tokoinId,
          'category_id': 'c1000000-0000-4000-8000-000000000001',
          'min_price': '1000',
          'max_price': '5000',
          'in_stock': 'true',
          'sort': 'price_asc',
          'offset': '0',
          'limit': '20',
        });
        // Catégorie parente : ses sous-catégories comprises ; épuisé exclu.
        expect(products.items.map((p) => p.name), ['Riz parfumé 5 kg']);
        expect(products.items.single.distanceM, isNull);

        // Tri par prix demandé : les boutiques passent en pertinence.
        final shops = await client.searchShops(query);
        expect(server.last.path, '/v1/search/shops');
        expect(server.last.query, {
          'neighborhood_id': tokoinId,
          'sort': 'relevance',
          'offset': '0',
          'limit': '20',
        });
        expect(shops.items.single.name, 'Chez Afi');
      },
    );

    test('égalité de valeur des paramètres (clé des listes)', () {
      const a = SearchQuery(text: 'riz', point: lome, radiusM: 2000);
      expect(a, const SearchQuery(text: 'riz', point: lome, radiusM: 2000));
      expect(
        a.hashCode,
        const SearchQuery(text: 'riz', point: lome, radiusM: 2000).hashCode,
      );
      expect(a.copyWith(radiusM: () => null).radiusM, isNull);
      expect(a.copyWith(text: 'mil'), isNot(a));
    });

    test('fiches publiques produit et boutique', () async {
      final id = search.products.first['id'] as String;
      final (product, shop) = await client.publicProduct(id);
      expect(product.name, 'Riz parfumé 5 kg');
      expect(shop.name, 'Chez Afi');
      expect(shop.neighborhoodName, 'Tokoin');
      expect(shop.location, lome);
      final same = await client.publicShop(shop.id);
      expect(same.acceptingOrders, isTrue);
      await expectLater(
        client.publicProduct('inconnu'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'product_not_found',
          ),
        ),
      );
    });

    test('trop de recherches : message du serveur', () async {
      search.failures['GET /v1/search/products'] = FakeResponse.error(
        429,
        'rate_limited',
        'Trop de recherches. Patientez un instant.',
      );
      await expectLater(
        client.searchProducts(const SearchQuery()),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Trop de recherches. Patientez un instant.',
          ),
        ),
      );
    });

    test(
      'faux serveur fidèle : texte de plus de 100 caractères refusé',
      () async {
        await expectLater(
          client.searchProducts(SearchQuery(text: 'x' * 101)),
          throwsA(
            isA<ApiException>().having((e) => e.fields.keys, 'champs', ['q']),
          ),
        );
      },
    );
  });

  group('panier', () {
    late FakeSearch search;
    late FakeCart cart;
    late Map<String, dynamic> afi;
    late Map<String, dynamic> wax;
    late Map<String, dynamic> riz;
    late Map<String, dynamic> huile;
    late Map<String, dynamic> pagne;

    Matcher apiError(String code, [String? message]) => throwsA(
      isA<ApiException>()
          .having((e) => e.code, 'code', code)
          .having((e) => e.message, 'message', message ?? anything),
    );

    setUp(() {
      search = FakeSearch(server);
      cart = FakeCart(search);
      afi = search.shop('Chez Afi');
      wax = search.shop('Wax & Co', neighborhoodId: beId);
      riz = search.product(afi, 'Riz parfumé 5 kg', stock: 3);
      huile = search.product(
        afi,
        'Huile 1 L',
        price: 1500,
        stockMode: 'untracked',
      );
      pagne = search.product(wax, 'Pagne wax', price: 12000);
    });

    test('vide : pas de boutique, rien à commander', () async {
      final c = await client.cart();
      expect(server.last.method, 'GET');
      expect(server.last.path, '/v1/cart');
      expect(c.isEmpty, isTrue);
      expect(c.shop, isNull);
      expect(c.articleCount, 0);
      expect(c.orderable, isFalse);
    });

    test('quantité totale envoyée, lignes dans l’ordre d’ajout', () async {
      await client.setCartItem(riz['id'] as String, 2);
      expect(server.last.method, 'PUT');
      expect(server.last.path, '/v1/cart/items');
      expect(server.last.body, {
        'product_id': riz['id'],
        'quantity': 2,
        'replace_cart': false,
      });
      final c = await client.setCartItem(huile['id'] as String, 3);
      expect(c.shop!.name, 'Chez Afi');
      expect(c.items.map((i) => i.name), ['Riz parfumé 5 kg', 'Huile 1 L']);
      expect(c.items.first.unitPriceXof, 4500);
      expect(c.items.first.lineTotalXof, 9000);
      expect(c.items.first.parcelSize, ParcelSize.medium);
      expect(c.items.first.imageUrl, startsWith('https://cdn.test/'));
      expect(c.subtotalXof, 9000 + 4500);
      expect(c.articleCount, 5);
      expect(c.quantityOf(riz['id'] as String), 2);
      expect(c.quantityOf(pagne['id'] as String), 0);
      expect(c.orderable, isTrue);

      // Quantité 0 : la ligne est retirée ; plus de ligne : plus de panier.
      await client.setCartItem(riz['id'] as String, 0);
      final last = await client.setCartItem(huile['id'] as String, 0);
      expect(last.isEmpty, isTrue);
      expect(cart.shopId, isNull);
    });

    test('autre boutique : conflit, puis remplacement du panier', () async {
      await client.setCartItem(riz['id'] as String, 1);
      await expectLater(
        client.setCartItem(pagne['id'] as String, 1),
        apiError('cart_shop_conflict'),
      );
      expect(cart.quantityOf(riz), 1);
      final c = await client.setCartItem(
        pagne['id'] as String,
        1,
        replaceCart: true,
      );
      expect(server.last.body, containsPair('replace_cart', true));
      expect(c.shop!.name, 'Wax & Co');
      expect(c.items.map((i) => i.name), ['Pagne wax']);
    });

    test('stock, produit retiré, quantité hors limites', () async {
      await expectLater(
        client.setCartItem(riz['id'] as String, 4),
        apiError('insufficient_stock', 'Seulement 3 en stock.'),
      );
      await expectLater(
        client.setCartItem(riz['id'] as String, 100),
        apiError('validation_failed'),
      );
      // Stock non suivi : seule la limite de 99 compte.
      await client.setCartItem(huile['id'] as String, 99);
      riz['stock_quantity'] = 0;
      await expectLater(
        client.setCartItem(riz['id'] as String, 1),
        apiError('product_unavailable'),
      );
      riz['is_active'] = false;
      await expectLater(
        client.setCartItem(riz['id'] as String, 1),
        apiError('product_not_found'),
      );
    });

    test('lecture : lignes en erreur, boutique fermée, sous-total', () async {
      cart
        ..put(riz, 3)
        ..put(huile, 2);
      riz['stock_quantity'] = 2;
      var c = await client.cart();
      expect(c.items.first.issue, 'Plus que 2 en stock.');
      expect(c.items.first.hasIssue, isTrue);
      expect(c.items.first.issueCode, CartIssue.insufficientStock);
      expect(c.items.first.stockLeft, 2);
      expect(c.items.last.hasIssue, isFalse);
      expect(c.items.last.stockLeft, isNull);
      // Les lignes en erreur ne comptent pas dans le sous-total.
      expect(c.subtotalXof, 3000);
      expect(c.orderable, isFalse);

      riz['stock_quantity'] = 12;
      afi['accepting_orders'] = false;
      c = await client.cart();
      expect(c.items.every((i) => !i.hasIssue), isTrue);
      expect(c.shop!.acceptingOrders, isFalse);
      expect(c.orderable, isFalse);

      huile['is_active'] = false;
      c = await client.cart();
      expect(c.items.last.issue, "Ce produit n'est plus disponible.");
      expect(c.items.last.issueCode, CartIssue.unavailable);
      expect(c.items.last.stockLeft, isNull);
    });

    test('raison : le code fait foi, pas le texte', () {
      final item = CartItem.fromJson({
        'product_id': 'p',
        'name': 'Riz',
        'image_url': null,
        'unit_price_xof': 4500,
        'quantity': 3,
        'line_total_xof': 13500,
        'parcel_size': 'small',
        // Texte reformulé côté serveur : sans effet sur l'action proposée.
        'issue': 'Il ne reste que 2 articles.',
        'issue_code': 'insufficient_stock',
        'stock_left': 2,
      });
      expect(item.stockLeft, 2);
      expect(item.hasIssue, isTrue);
      expect(CartIssue.parse('on_hold'), CartIssue.unknown);
    });

    test('30 produits différents au plus : le panier ne change pas', () async {
      for (var i = 0; i < FakeCart.maxLines; i++) {
        cart.put(search.product(afi, 'Produit $i'), 1);
      }
      await expectLater(
        client.setCartItem(riz['id'] as String, 1),
        apiError('cart_full'),
      );
      expect(cart.lines, hasLength(FakeCart.maxLines));
      expect(cart.quantityOf(riz), 0);
    });

    test('un panier par compte, reconnu au jeton', () async {
      client.token = 'jeton-awa';
      await client.setCartItem(riz['id'] as String, 2);
      client.token = 'jeton-kofi';
      expect((await client.cart()).isEmpty, isTrue);
      await client.setCartItem(pagne['id'] as String, 1);
      expect(cart.linesOf('Bearer jeton-kofi'), {pagne['id']: 1});
      // Le panier du premier compte n'a pas bougé.
      expect(cart.lines, {riz['id']: 2});
      client.token = 'jeton-awa';
      expect((await client.cart()).items.single.name, 'Riz parfumé 5 kg');
    });

    test('vider : DELETE, puis panier vide', () async {
      cart.put(riz, 1);
      await client.clearCart();
      expect(server.last.method, 'DELETE');
      expect(server.last.path, '/v1/cart');
      expect((await client.cart()).isEmpty, isTrue);
    });
  });

  group('commandes', () {
    late FakeSearch search;
    late FakeCart cart;
    late FakeOrders orders;
    late Map<String, dynamic> afi;
    late Map<String, dynamic> riz;
    late Map<String, dynamic> huile;

    Matcher apiError(String code) =>
        throwsA(isA<ApiException>().having((e) => e.code, 'code', code));

    setUp(() {
      search = FakeSearch(server);
      cart = FakeCart(search);
      orders = FakeOrders(cart);
      afi = search.shop('Chez Afi');
      riz = search.product(afi, 'Riz parfumé 5 kg', stock: 5);
      huile = search.product(
        afi,
        'Huile 1 L',
        price: 1500,
        stockMode: 'untracked',
      );
      cart
        ..put(riz, 2)
        ..put(huile, 1);
    });

    test('identifiant de requête : UUID v4, jamais deux fois le même', () {
      final ids = {for (var i = 0; i < 100; i++) newRequestId()};
      expect(ids, hasLength(100));
      expect(
        ids.first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('récapitulatif du retrait', () async {
      final quote = await client.quoteOrder();
      expect(server.last.body, {'fulfillment': 'pickup'});
      expect(quote.shopId, afi['id']);
      expect(quote.items.map((i) => (i.name, i.quantity, i.lineTotalXof)), [
        ('Riz parfumé 5 kg', 2, 9000),
        ('Huile 1 L', 1, 1500),
      ]);
      expect(quote.totalXof, 10500);
      expect(quote.articleCount, 3);
      expect(quote.paymentTimeout, const Duration(minutes: 15));
    });

    test(
      'création : stock réservé, panier vidé, même requête rejouée',
      () async {
        final id = newRequestId();
        final order = await client.createOrder(clientRequestId: id);
        expect(server.last.body, {
          'fulfillment': 'pickup',
          'client_request_id': id,
        });
        expect(order.status, OrderStatus.pendingPayment);
        expect(order.status.isActive, isTrue);
        expect(order.number, 1042);
        expect(order.totalXof, 10500);
        expect(order.shop.name, 'Chez Afi');
        expect(order.handoverCode, isNull);
        expect(order.events.single.to, OrderStatus.pendingPayment);
        expect(
          order.paymentDeadlineAt.difference(order.createdAt),
          const Duration(minutes: 15),
        );
        expect(riz['stock_quantity'], 3);
        expect(cart.lines, isEmpty);

        final again = await client.createOrder(clientRequestId: id);
        expect(again.id, order.id);
        expect(orders.orders, hasLength(1));
        // Panier vide : une nouvelle requête est refusée.
        await expectLater(
          client.createOrder(clientRequestId: newRequestId()),
          apiError('cart_empty'),
        );
      },
    );

    test('refus : boutique fermée, stock, produit retiré, profil', () async {
      afi['accepting_orders'] = false;
      await expectLater(client.quoteOrder(), apiError('shop_closed'));
      afi['accepting_orders'] = true;
      riz['stock_quantity'] = 1;
      await expectLater(client.quoteOrder(), apiError('insufficient_stock'));
      riz['stock_quantity'] = 5;
      huile['is_active'] = false;
      await expectLater(
        client.createOrder(clientRequestId: newRequestId()),
        apiError('product_unavailable'),
      );
      huile['is_active'] = true;
      orders.profileComplete = false;
      await expectLater(
        client.createOrder(clientRequestId: newRequestId()),
        apiError('profile_incomplete'),
      );
      expect(orders.orders, isEmpty);
    });

    test('liste, suivi, code selon le statut, historique', () async {
      final old = orders.seed(afi, [(riz, 1)], status: 'completed');
      final current = await client.createOrder(clientRequestId: newRequestId());
      final page = await client.myOrders();
      expect(server.last.query, {'offset': '0', 'limit': '50'});
      expect(page.items.map((o) => o.id), [current.id, old['id']]);
      expect(page.items.last.status, OrderStatus.completed);
      expect(page.items.last.status.isActive, isFalse);
      expect(page.items.last.handoverCode, isNull);

      final placed = orders.orders.last;
      orders.advance(placed, 'awaiting_seller');
      var o = await client.myOrder(current.id);
      expect(o.handoverCode, FakeOrders.handoverCode);
      expect(o.reachedAt(OrderStatus.awaitingSeller), isNotNull);
      expect(o.reachedAt(OrderStatus.readyForPickup), isNull);
      orders.advance(placed, 'cancelled', reason: 'Refusée par la boutique');
      o = await client.myOrder(current.id);
      expect(o.status, OrderStatus.cancelled);
      expect(o.cancelReason, 'Refusée par la boutique');
      expect(o.handoverCode, isNull);
      expect(o.events.map((e) => e.to), [
        OrderStatus.pendingPayment,
        OrderStatus.awaitingSeller,
        OrderStatus.cancelled,
      ]);

      await expectLater(client.myOrder('inconnue'), apiError('not_found'));
      // Commande d'un autre compte : introuvable.
      client.token = 'jeton-kofi';
      await expectLater(
        client.myOrder(current.id),
        apiError('order_not_found'),
      );
      expect((await client.myOrders()).items, isEmpty);
    });

    test('réponse perdue après la création, puis limite de débit', () async {
      final id = newRequestId();
      orders.loseNextCreateResponse = true;
      await expectLater(
        client.createOrder(clientRequestId: id),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'réseau', true)),
      );
      // Créée malgré tout : le nouvel essai la rend, même limité.
      expect(orders.orders, hasLength(1));
      orders.rateLimited = true;
      final again = await client.createOrder(clientRequestId: id);
      expect(again.id, orders.orders.single['id']);
      cart.put(riz, 1);
      await expectLater(
        client.createOrder(clientRequestId: newRequestId()),
        apiError('rate_limited'),
      );
      expect(again.updatedAt, again.createdAt);
    });

    test('statut inconnu de cette version : en cours, sans planter', () {
      expect(OrderStatus.parse('on_hold'), OrderStatus.unknown);
      expect(OrderStatus.unknown.isActive, isTrue);
    });
  });

  group('paiements', () {
    late FakeOrders orders;
    late FakePayments payments;
    late Map<String, dynamic> order;

    Matcher apiError(String code) =>
        throwsA(isA<ApiException>().having((e) => e.code, 'code', code));

    setUp(() {
      final search = FakeSearch(server);
      orders = FakeOrders(FakeCart(search));
      payments = FakePayments(orders);
      final afi = search.shop('Chez Afi');
      order = orders.seed(afi, [(search.product(afi, 'Riz parfumé 5 kg'), 2)])
        ..['payment_deadline_at'] = DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String();
    });

    test('statuts : tous lus, inconnu toléré', () {
      for (final s in PaymentStatus.values.where((s) => s.code != 'unknown')) {
        expect(PaymentStatus.parse(s.code), s);
      }
      expect(PaymentStatus.parse('on_hold'), PaymentStatus.unknown);
      expect(PaymentStatus.pending.isPending, isTrue);
      expect(PaymentStatus.refunded.isPaid, isTrue);
      expect(PaymentStatus.failed.isPaid, isFalse);
      expect(PaymentOperator.parse('tmoney'), PaymentOperator.tmoney);
    });

    test(
      'demande : opérateur et numéro envoyés, numéro masqué rendu',
      () async {
        final p = await client.startPayment(
          order['id'] as String,
          operator: PaymentOperator.tmoney,
          phone: '+22870123456',
        );
        expect(server.last.method, 'POST');
        expect(server.last.path, '/v1/orders/${order['id']}/payments');
        expect(server.last.body, {
          'operator': 'tmoney',
          'phone': '+22870123456',
        });
        expect(p.status, PaymentStatus.pending);
        expect(p.operator, PaymentOperator.tmoney);
        expect(p.phoneMasked, '+22870••••56');
        expect(p.amountXof, order['total_xof']);
        expect(p.orderId, order['id']);
      },
    );

    test('une seule demande en attente : rendue telle quelle', () async {
      final id = order['id'] as String;
      final first = await client.startPayment(
        id,
        operator: PaymentOperator.flooz,
        phone: '96451278',
      );
      final again = await client.startPayment(
        id,
        operator: PaymentOperator.tmoney,
        phone: '70123456',
      );
      expect(again.id, first.id);
      expect(again.operator, PaymentOperator.flooz);
      expect((await client.orderPayments(id)).map((p) => p.id), [first.id]);
    });

    test('annulation : échec, idempotente, puis nouvelle demande', () async {
      final id = order['id'] as String;
      final first = await client.startPayment(
        id,
        operator: PaymentOperator.flooz,
        phone: '96451278',
      );
      final cancelled = await client.cancelPayment(first.id);
      expect(server.last.path, '/v1/payments/${first.id}/cancel');
      expect(cancelled.status, PaymentStatus.failed);
      expect(cancelled.failureReason, "Annulé par l'acheteur.");
      expect(
        (await client.cancelPayment(first.id)).status,
        PaymentStatus.failed,
      );
      final second = await client.startPayment(
        id,
        operator: PaymentOperator.tmoney,
        phone: '70123456',
      );
      expect(second.id, isNot(first.id));
      expect((await client.orderPayments(id)).map((p) => p.id), [
        second.id,
        first.id,
      ]);
    });

    test('simulation : la commande passe en attente de la boutique', () async {
      final id = order['id'] as String;
      final p = await client.startPayment(
        id,
        operator: PaymentOperator.flooz,
        phone: '96451278',
      );
      await client.devSimulatePayment(p.id, succeeded: true);
      expect(server.last.body, {'outcome': 'succeeded'});
      expect((await client.payment(p.id)).status, PaymentStatus.succeeded);
      final paid = await client.myOrder(id);
      expect(paid.status, OrderStatus.awaitingSeller);
      expect(paid.handoverCode, FakeOrders.handoverCode);
      await expectLater(
        client.cancelPayment(p.id),
        apiError('payment_not_cancellable'),
      );
    });

    test('refus du prestataire : raison donnée', () async {
      final p = await client.startPayment(
        order['id'] as String,
        operator: PaymentOperator.flooz,
        phone: '96451278',
      );
      await client.devSimulatePayment(p.id, succeeded: false);
      final failed = await client.payment(p.id);
      expect(failed.status, PaymentStatus.failed);
      expect(failed.failureReason, 'Paiement refusé ou annulé.');
    });

    test('demande annulée validée malgré tout : appliquée', () async {
      final p = await client.startPayment(
        order['id'] as String,
        operator: PaymentOperator.flooz,
        phone: '96451278',
      );
      await client.cancelPayment(p.id);
      payments.succeed(payments.payments.single);
      expect((await client.payment(p.id)).status, PaymentStatus.succeeded);
      expect(order['status'], 'awaiting_seller');
    });

    test('refus du serveur', () async {
      final id = order['id'] as String;
      await expectLater(
        client.startPayment(id, operator: PaymentOperator.flooz, phone: '123'),
        throwsA(
          isA<ApiException>().having((e) => e.fields.keys, 'champs', ['phone']),
        ),
      );
      payments.providerDown = true;
      await expectLater(
        client.startPayment(
          id,
          operator: PaymentOperator.flooz,
          phone: '96451278',
        ),
        apiError('payment_provider_unavailable'),
      );
      // Comme le serveur : la demande est enregistrée, close.
      expect(
        (await client.orderPayments(id)).single.failureReason,
        'Prestataire injoignable.',
      );
      payments
        ..providerDown = false
        ..rateLimited = true;
      await expectLater(
        client.startPayment(
          id,
          operator: PaymentOperator.flooz,
          phone: '96451278',
        ),
        apiError('rate_limited'),
      );
      order['payment_deadline_at'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      await expectLater(
        client.startPayment(
          id,
          operator: PaymentOperator.flooz,
          phone: '96451278',
        ),
        apiError('order_expired'),
      );
      orders.advance(order, 'expired');
      await expectLater(
        client.startPayment(
          id,
          operator: PaymentOperator.flooz,
          phone: '96451278',
        ),
        apiError('order_not_payable'),
      );
    });

    test("paiement d'un autre compte : 404", () async {
      final id = order['id'] as String;
      final p = await client.startPayment(
        id,
        operator: PaymentOperator.flooz,
        phone: '96451278',
      );
      client.token = 'jeton-kofi';
      await expectLater(client.payment(p.id), apiError('payment_not_found'));
      await expectLater(
        client.cancelPayment(p.id),
        apiError('payment_not_found'),
      );
      await expectLater(
        client.devSimulatePayment(p.id, succeeded: true),
        apiError('payment_not_found'),
      );
      await expectLater(client.orderPayments(id), apiError('order_not_found'));
      expect(payments.payments.single['status'], 'pending');
    });
  });

  group('heure du serveur', () {
    test('en-tête Date lu ; petit écart ignoré', () async {
      server.on('GET', '/v1/me', (_) => FakeResponse.json(200, userBody()));
      expect(
        parseHttpDate('Mon, 02 Nov 2026 06:56:01 GMT'),
        DateTime.utc(2026, 11, 2, 6, 56, 1),
      );
      expect(parseHttpDate('hier'), isNull);
      expect(parseHttpDate(null), isNull);

      server.clock = () => DateTime.now().add(const Duration(minutes: 12));
      await client.getMe();
      expect(
        client.now().difference(DateTime.now()).inMinutes,
        inInclusiveRange(11, 12),
      );
      server.clock = () => DateTime.now().add(const Duration(seconds: 5));
      await client.getMe();
      expect(client.now().difference(DateTime.now()).inSeconds.abs(), 0);
    });
  });

  group('paiement après expiration', () {
    late FakeOrders orders;
    late FakePayments payments;
    late FakeSearch search;
    late Map<String, dynamic> afi;

    setUp(() {
      search = FakeSearch(server);
      orders = FakeOrders(FakeCart(search));
      payments = FakePayments(orders);
      afi = search.shop('Chez Afi');
    });

    Future<Map<String, dynamic>> paidLate(
      Map<String, dynamic> product, {
      void Function()? afterExpiry,
    }) async {
      final order = orders.seed(afi, [(product, 1)])
        ..['payment_deadline_at'] = DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String();
      await client.startPayment(
        order['id'] as String,
        operator: PaymentOperator.flooz,
        phone: '96451278',
      );
      orders.advance(order, 'expired');
      afterExpiry?.call();
      payments.succeed(payments.payments.last);
      return order;
    }

    test('stock encore là : reprise ; épuisé : annulée', () async {
      final riz = search.product(afi, 'Riz', stock: 1);
      // La commande avait réservé le stock : l'expiration le rend.
      riz['stock_quantity'] = 0;
      final first = await paidLate(riz);
      expect(first['status'], 'awaiting_seller');
      expect(riz['stock_quantity'], 0);

      // Seconde commande : le stock rendu à l'expiration part ailleurs.
      final second = await paidLate(
        riz,
        afterExpiry: () => riz['stock_quantity'] = 0,
      );
      expect(second['status'], 'cancelled');
      expect(second['cancel_reason'], contains('stock épuisé'));
    });

    test(
      'commande annulée avant le paiement : inchangée, pas un doublon',
      () async {
        final order = orders.seed(afi, [(search.product(afi, 'Huile'), 1)])
          ..['payment_deadline_at'] = DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String();
        final p = await client.startPayment(
          order['id'] as String,
          operator: PaymentOperator.flooz,
          phone: '96451278',
        );
        orders.advance(order, 'cancelled', reason: 'Annulée par ivia.');
        payments.succeed(payments.payments.single);
        expect(order['status'], 'cancelled');
        expect((await client.payment(p.id)).status, PaymentStatus.succeeded);
        expect(payments.payments.single['is_duplicate'], isFalse);
      },
    );
  });
}
