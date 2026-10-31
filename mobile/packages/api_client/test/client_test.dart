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
}
