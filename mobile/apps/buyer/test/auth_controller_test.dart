import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_buyer/app/auth_controller.dart';
import 'package:ivia_buyer/app/providers.dart';
import 'package:ivia_buyer/app/router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeApiServer server;
  late IviaApiClient client;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    server = FakeApiServer();
    client = IviaApiClient(
      config: ApiConfig(baseUrl: Uri.parse('http://api.test')),
      adapter: server,
    );
  });

  /// Démarre le contrôleur et attend la fin du démarrage.
  Future<ProviderContainer> start() async {
    final container = ProviderContainer.test(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        authTimingsProvider.overrideWithValue(
          const AuthTimings(
            minSplash: Duration.zero,
            meTimeout: Duration(milliseconds: 200),
          ),
        ),
      ],
    );
    final done = Completer<void>();
    container.listen<AuthState>(authControllerProvider, (_, next) {
      if (next is! AuthStarting && !done.isCompleted) done.complete();
    }, fireImmediately: true);
    await done.future;
    return container;
  }

  Future<void> storeSession({
    bool complete = true,
    bool withUser = true,
  }) async {
    if (withUser) {
      await SessionStore().save(
        'jeton-secret',
        User.fromJson(userBody(complete: complete)),
      );
    } else {
      FlutterSecureStorage.setMockInitialValues({
        'session_token': 'jeton-secret',
      });
    }
  }

  AuthState state(ProviderContainer c) => c.read(authControllerProvider);

  group('démarrage', () {
    test('aucune session : déconnecté', () async {
      final c = await start();
      expect(state(c), isA<AuthSignedOut>());
      expect(server.requests, isEmpty);
    });

    test('session et profil complet : connecté, profil mis à jour', () async {
      await storeSession(complete: false);
      server.on(
        'GET',
        '/v1/me',
        (_) => FakeResponse.json(200, userBody(complete: true)),
      );
      final c = await start();
      expect(state(c), isA<AuthSignedIn>());
      expect(server.last.headers['authorization'], 'Bearer jeton-secret');
      expect((await SessionStore().read())?.user?.profileComplete, isTrue);
    });

    test('profil incomplet : « Faisons connaissance »', () async {
      await storeSession();
      server.on('GET', '/v1/me', (_) => FakeResponse.json(200, userBody()));
      expect(state(await start()), isA<AuthNeedsProfile>());
    });

    test('session refusée (401) : déconnecté, session effacée', () async {
      await storeSession();
      server.on(
        'GET',
        '/v1/me',
        (_) => FakeResponse.error(401, 'unauthorized', 'Session expirée.'),
      );
      final c = await start();
      expect(state(c), isA<AuthSignedOut>());
      expect(await SessionStore().read(), isNull);
      expect(client.token, isNull);
    });

    test('serveur injoignable, profil gardé : connecté hors ligne', () async {
      await storeSession();
      server.on('GET', '/v1/me', (_) => FakeResponse.networkError());
      expect(state(await start()), isA<AuthSignedIn>());
    });

    test('serveur trop lent : profil gardé utilisé', () async {
      await storeSession();
      server.on('GET', '/v1/me', (_) => Completer<FakeResponse>().future);
      expect(state(await start()), isA<AuthSignedIn>());
    });

    test(
      'injoignable sans profil gardé : hors ligne, puis « Réessayer »',
      () async {
        await storeSession(withUser: false);
        server.on('GET', '/v1/me', (_) => FakeResponse.networkError());
        final c = await start();
        expect(state(c), isA<AuthOffline>());

        server.on(
          'GET',
          '/v1/me',
          (_) => FakeResponse.json(200, userBody(complete: true)),
        );
        await c.read(authControllerProvider.notifier).retry();
        expect(state(c), isA<AuthSignedIn>());
      },
    );
  });

  group('en cours d\'utilisation', () {
    test('connexion : session enregistrée, jeton utilisé', () async {
      final c = await start();
      await c
          .read(authControllerProvider.notifier)
          .signedIn(Session.fromJson(sessionBody()));
      expect(state(c), isA<AuthNeedsProfile>());
      expect(client.token, 'jeton-secret');
      expect((await SessionStore().read())?.token, 'jeton-secret');
    });

    test('profil complété : connecté', () async {
      final c = await start();
      final auth = c.read(authControllerProvider.notifier);
      await auth.signedIn(Session.fromJson(sessionBody()));
      await auth.profileUpdated(User.fromJson(userBody(complete: true)));
      expect(state(c), isA<AuthSignedIn>());
    });

    test('déconnexion : révoquée, effacée, même hors ligne', () async {
      await storeSession();
      server.on(
        'GET',
        '/v1/me',
        (_) => FakeResponse.json(200, userBody(complete: true)),
      );
      server.on('POST', '/v1/auth/logout', (_) => FakeResponse.networkError());
      final c = await start();
      await c.read(authControllerProvider.notifier).signOut();
      expect(server.calls('POST', '/v1/auth/logout'), hasLength(1));
      expect(state(c), isA<AuthSignedOut>());
      expect(await SessionStore().read(), isNull);
      expect(client.token, isNull);
    });

    test('401 sur un appel : déconnecté', () async {
      await storeSession();
      server.on(
        'GET',
        '/v1/me',
        (_) => FakeResponse.json(200, userBody(complete: true)),
      );
      final c = await start();
      server.on(
        'GET',
        '/v1/me',
        (_) => FakeResponse.error(401, 'unauthorized', 'Session expirée.'),
      );
      await expectLater(client.getMe(), throwsA(isA<ApiException>()));
      await pumpEventQueue();
      expect(state(c), isA<AuthSignedOut>());
      expect(await SessionStore().read(), isNull);
    });
  });

  group('redirections', () {
    final user = User.fromJson(userBody(complete: true));
    String? go(AuthState s, String location, {bool seen = true}) =>
        redirectFor(s, onboardingSeen: seen, location: location);

    test('chaque état mène à son écran', () {
      expect(go(const AuthStarting(), Routes.home), Routes.splash);
      expect(
        go(const AuthSignedOut(), Routes.splash, seen: false),
        Routes.onboarding,
      );
      expect(go(const AuthSignedOut(), Routes.splash), Routes.login);
      expect(go(const AuthSignedOut(), Routes.home), Routes.login);
      expect(go(AuthNeedsProfile(user), Routes.login), Routes.profile);
      expect(go(AuthSignedIn(user), Routes.code), Routes.home);
      expect(go(const AuthOffline(), Routes.home), Routes.offline);
    });

    test('écrans permis : pas de redirection', () {
      expect(go(const AuthStarting(), Routes.splash), isNull);
      expect(go(const AuthSignedOut(), Routes.onboarding, seen: false), isNull);
      expect(go(const AuthSignedOut(), Routes.login), isNull);
      expect(go(const AuthSignedOut(), Routes.code), isNull);
      expect(go(AuthNeedsProfile(user), Routes.profile), isNull);
      expect(go(AuthSignedIn(user), Routes.home), isNull);
    });
  });
}
