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
}
