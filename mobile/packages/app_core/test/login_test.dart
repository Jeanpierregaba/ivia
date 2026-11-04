import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_app_core/testing.dart';
import 'package:ivia_ui/ivia_ui.dart';

const _identity = AppIdentity(
  brand: IviaAppBrand.buyer,
  loginTitle: 'Bienvenue sur ivia',
  loginBody: 'Connectez-vous avec votre e-mail et votre mot de passe.',
  codeHint: _hint,
);

String _hint(Duration d) => 'Le code est valable ${d.inMinutes} minutes.';

const _goodPassword = 'pagne-wax-2026';

void main() {
  late FakeApiServer server;
  late FakeAuth auth;
  late FakeGoogleAuth google;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    server = FakeApiServer();
    auth = FakeAuth(server);
    google = FakeGoogleAuth(available: false);
    // Profil lu après l'ouverture de session (comme le serveur).
    server.on(
      'GET',
      '/v1/me',
      (_) => FakeResponse.json(200, userBody(complete: true)),
    );
  });

  /// App minimale : routes de connexion communes, accueil et profil ; la
  /// redirection suit l'état de session, comme dans les apps.
  Future<void> launch(WidgetTester tester, {String? at}) async {
    final container = ProviderContainer(
      overrides: [
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
        appIdentityProvider.overrideWithValue(_identity),
        googleAuthProvider.overrideWithValue(google),
      ],
    );
    addTearDown(container.dispose);
    final refresh = ValueNotifier(0);
    container.listen(authControllerProvider, (_, _) => refresh.value++);
    final router = GoRouter(
      initialLocation: at ?? AuthRoutes.login,
      refreshListenable: refresh,
      redirect: (context, state) {
        final location = state.matchedLocation;
        return switch (container.read(authControllerProvider)) {
          AuthStarting() => null,
          AuthSignedOut() || AuthOffline() =>
            location.startsWith(AuthRoutes.login) ? null : AuthRoutes.login,
          AuthNeedsProfile() => location == '/profile' ? null : '/profile',
          AuthSignedIn() =>
            location.startsWith(AuthRoutes.login) ? '/home' : null,
        };
      },
      routes: [
        ...authRoutes(),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Accueil')),
          routes: [
            GoRoute(
              path: 'password',
              builder: (_, _) => const ChangePasswordScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/profile',
          builder: (_, _) => const Scaffold(body: Text('Faisons connaissance')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: IviaTheme.light(IviaAppBrand.buyer),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(IviaFieldLabel, label),
    matching: find.byType(TextField),
  );

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester, String email, String password) async {
    await tester.enterText(field('Adresse e-mail'), email);
    await tester.enterText(field('Mot de passe'), password);
    await tapText(tester, 'Se connecter');
  }

  Iterable<RecordedRequest> posts(String path) => server.calls('POST', path);

  group('champ mot de passe', () {
    testWidgets('masqué, œil lu, pas de suggestions', (tester) async {
      final semantics = tester.ensureSemantics();
      await launch(tester);
      TextField input() => tester.widget<TextField>(field('Mot de passe'));
      expect(input().obscureText, isTrue);
      expect(input().enableSuggestions, isFalse);
      expect(input().autocorrect, isFalse);
      await tester.tap(find.byTooltip('Afficher le mot de passe'));
      await tester.pump();
      expect(input().obscureText, isFalse);
      expect(find.byTooltip('Masquer le mot de passe'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('connexion', () {
    testWidgets('e-mail et mot de passe ⇒ accueil', (tester) async {
      auth.addAccount('awa@test.tg', password: _goodPassword);
      await launch(tester);
      await login(tester, ' Awa@Test.tg ', _goodPassword);
      expect(posts('/v1/auth/login').single.body, {
        'email': 'awa@test.tg',
        'password': _goodPassword,
      });
      expect(find.text('Accueil'), findsOneWidget);
      expect(await tester.runAsync(() => SessionStore().read()), isNotNull);
    });

    testWidgets('refusée : message, mot de passe vidé, aide « code »', (
      tester,
    ) async {
      auth.addAccount('awa@test.tg');
      await launch(tester);
      await login(tester, 'awa@test.tg', 'mauvais-mot-de-passe');
      expect(find.text('E-mail ou mot de passe incorrect.'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('Mot de passe')).controller!.text,
        isEmpty,
      );
      expect(
        find.textContaining('Vous vous connectiez avec un code'),
        findsOneWidget,
      );
      await tapText(tester, 'Créer mon mot de passe');
      expect(find.text('Créer un compte'), findsWidgets);
      expect(
        tester.widget<TextField>(field('Adresse e-mail')).controller!.text,
        'awa@test.tg',
      );
    });

    testWidgets('compte bloqué : message du serveur', (tester) async {
      auth.addAccount('awa@test.tg', password: _goodPassword);
      await launch(tester);
      for (var i = 0; i < 10; i++) {
        await login(tester, 'awa@test.tg', 'mauvais-$i-xxxxxx');
      }
      expect(find.textContaining('compte bloqué 15 min'), findsOneWidget);
    });

    testWidgets('adresse invalide ou mot de passe vide : rien n\'est envoyé', (
      tester,
    ) async {
      await launch(tester);
      await login(tester, 'awa', _goodPassword);
      expect(find.text('Saisissez une adresse e-mail valide.'), findsOneWidget);
      await login(tester, 'awa@test.tg', '');
      expect(find.text('Saisissez votre mot de passe.'), findsOneWidget);
      expect(posts('/v1/auth/login'), isEmpty);
    });

    testWidgets('réseau coupé : message, saisie gardée', (tester) async {
      auth
        ..addAccount('awa@test.tg', password: _goodPassword)
        ..failures['POST /v1/auth/login'] = FakeResponse.networkError();
      await launch(tester);
      await login(tester, 'awa@test.tg', _goodPassword);
      expect(find.textContaining('connexion'), findsWidgets);
      expect(
        tester.widget<TextField>(field('Adresse e-mail')).controller!.text,
        'awa@test.tg',
      );
      expect(find.text('Accueil'), findsNothing);
    });

    testWidgets('double appui : une seule connexion', (tester) async {
      auth.addAccount('awa@test.tg', password: _goodPassword);
      final release = Completer<void>();
      auth.beforeRequest = (_) => release.future;
      await launch(tester);
      await tester.enterText(field('Adresse e-mail'), 'awa@test.tg');
      await tester.enterText(field('Mot de passe'), _goodPassword);
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      release.complete();
      await tester.pumpAndSettle();
      expect(posts('/v1/auth/login'), hasLength(1));
    });
  });

  group('Google', () {
    testWidgets('masqué sans identifiants ou si le serveur ne l\'ouvre pas', (
      tester,
    ) async {
      auth.google = true;
      await launch(tester);
      expect(find.text('Continuer avec Google'), findsNothing);
    });

    testWidgets('masqué si le serveur ne l\'ouvre pas', (tester) async {
      google.available = true;
      await launch(tester);
      expect(find.text('Continuer avec Google'), findsNothing);
    });

    testWidgets('fenêtre fermée : rien ne se passe', (tester) async {
      auth.google = true;
      google
        ..available = true
        ..token = null;
      await launch(tester);
      await tapText(tester, 'Continuer avec Google');
      expect(google.calls, 1);
      expect(posts('/v1/auth/google'), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('impossible'), findsNothing);
    });

    testWidgets('jeton refusé : message', (tester) async {
      auth.google = true;
      google.available = true;
      await launch(tester);
      await tapText(tester, 'Continuer avec Google');
      expect(
        find.text('Connexion avec Google impossible. Réessayez.'),
        findsOneWidget,
      );
    });

    testWidgets('échec du téléphone : message', (tester) async {
      auth.google = true;
      google
        ..available = true
        ..error = const GoogleAuthException();
      await launch(tester);
      await tapText(tester, 'Continuer avec Google');
      expect(
        find.text('Connexion avec Google impossible. Réessayez.'),
        findsOneWidget,
      );
    });

    testWidgets('nouveau compte : « Faisons connaissance »', (tester) async {
      auth
        ..google = true
        ..addGoogleToken(
          'jeton-google',
          subject: 'g1',
          email: 'kofi@gmail.com',
        );
      google.available = true;
      server.on(
        'GET',
        '/v1/me',
        (_) => FakeResponse.json(200, userBody(email: 'kofi@gmail.com')),
      );
      await launch(tester);
      await tapText(tester, 'Continuer avec Google');
      expect(posts('/v1/auth/google').single.body, {
        'id_token': 'jeton-google',
      });
      expect(find.text('Faisons connaissance'), findsOneWidget);
    });
  });

  group('création de compte', () {
    Future<void> toCode(WidgetTester tester, String email) async {
      await tapText(tester, 'Créer un compte');
      await tester.enterText(field('Adresse e-mail'), email);
      await tapText(tester, 'Recevoir le code');
    }

    Future<void> enterCode(WidgetTester tester, String code) async {
      await tester.enterText(
        find.descendant(
          of: find.byType(IviaCodeInput),
          matching: find.byType(TextField),
        ),
        code,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('code, puis mot de passe ⇒ nouveau compte, profil', (
      tester,
    ) async {
      server.on(
        'GET',
        '/v1/me',
        (_) => FakeResponse.json(200, userBody(email: 'ama@test.tg')),
      );
      await launch(tester);
      await toCode(tester, 'ama@test.tg');
      expect(find.text('Vérifiez vos e-mails'), findsOneWidget);
      expect(
        find.textContaining('ama@test.tg', findRichText: true),
        findsOneWidget,
      );
      await enterCode(tester, auth.lastCode('ama@test.tg', 'signup')!);
      expect(find.text('Choisissez un mot de passe'), findsOneWidget);
      await tester.enterText(field('Mot de passe'), _goodPassword);
      await tapText(tester, 'Créer mon compte');
      expect(posts('/v1/auth/signup').single.body, {
        'email': 'ama@test.tg',
        'code': auth.lastCode('ama@test.tg', 'signup'),
        'password': _goodPassword,
      });
      expect(find.text('Faisons connaissance'), findsOneWidget);
      expect(auth.passwordOf('ama@test.tg'), _goodPassword);
    });

    testWidgets('mot de passe refusé : message, sans nouveau code', (
      tester,
    ) async {
      await launch(tester);
      await toCode(tester, 'ama@test.tg');
      await enterCode(tester, auth.lastCode('ama@test.tg', 'signup')!);
      await tester.enterText(field('Mot de passe'), 'azertyuiop');
      await tapText(tester, 'Créer mon compte');
      expect(
        find.text(
          'Ce mot de passe est trop facile à deviner. Choisissez-en un autre.',
        ),
        findsOneWidget,
      );
      expect(find.text('Choisissez un mot de passe'), findsOneWidget);
      await tester.enterText(field('Mot de passe'), _goodPassword);
      await tapText(tester, 'Créer mon compte');
      expect(posts('/v1/auth/signup/code'), hasLength(1));
      expect(auth.passwordOf('ama@test.tg'), _goodPassword);
    });

    testWidgets('code faux : retour aux 6 cases avec le message', (
      tester,
    ) async {
      await launch(tester);
      await toCode(tester, 'ama@test.tg');
      await enterCode(tester, '000000');
      await tester.enterText(field('Mot de passe'), _goodPassword);
      await tapText(tester, 'Créer mon compte');
      expect(find.text('Vérifiez vos e-mails'), findsOneWidget);
      expect(find.text('Code incorrect ou expiré.'), findsOneWidget);
    });

    testWidgets('compte qui a déjà un mot de passe : « Se connecter »', (
      tester,
    ) async {
      auth.addAccount('awa@test.tg', password: 'ancien-pagne-2026');
      await launch(tester);
      await toCode(tester, 'awa@test.tg');
      await enterCode(tester, auth.lastCode('awa@test.tg', 'signup')!);
      await tester.enterText(field('Mot de passe'), _goodPassword);
      await tapText(tester, 'Créer mon compte');
      expect(find.textContaining('Un compte existe déjà'), findsOneWidget);
      await tapText(tester, 'Se connecter');
      expect(
        tester.widget<TextField>(field('Adresse e-mail')).controller!.text,
        'awa@test.tg',
      );
    });

    testWidgets('ancien compte par code : mot de passe ajouté, accueil', (
      tester,
    ) async {
      auth.addAccount('awa@test.tg');
      await launch(tester);
      await toCode(tester, 'awa@test.tg');
      await enterCode(tester, auth.lastCode('awa@test.tg', 'signup')!);
      await tester.enterText(field('Mot de passe'), _goodPassword);
      await tapText(tester, 'Créer mon compte');
      expect(find.text('Accueil'), findsOneWidget);
    });

    testWidgets('trop de codes : message du serveur', (tester) async {
      await launch(tester);
      await toCode(tester, 'ama@test.tg');
      await tester.tap(find.byType(IviaBackButton));
      await tester.pumpAndSettle();
      await tapText(tester, 'Recevoir le code');
      expect(find.textContaining('Patientez une minute'), findsOneWidget);
    });
  });

  group('mot de passe oublié', () {
    testWidgets('code, nouveau mot de passe ⇒ accueil, anciennes sessions', (
      tester,
    ) async {
      auth.addAccount('awa@test.tg', password: 'ancien-pagne-2026');
      await launch(tester);
      await tester.enterText(field('Adresse e-mail'), 'awa@test.tg');
      await tapText(tester, 'Mot de passe oublié ?');
      expect(find.text('Mot de passe oublié'), findsOneWidget);
      // Adresse reprise de la connexion.
      await tapText(tester, 'Recevoir le code');
      await tester.enterText(
        find.descendant(
          of: find.byType(IviaCodeInput),
          matching: find.byType(TextField),
        ),
        auth.lastCode('awa@test.tg', 'reset')!,
      );
      await tester.pumpAndSettle();
      expect(find.text('Nouveau mot de passe'), findsWidgets);
      await tester.enterText(field('Nouveau mot de passe'), _goodPassword);
      await tapText(tester, 'Changer le mot de passe');
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Mot de passe changé.'), findsOneWidget);
      expect(auth.passwordOf('awa@test.tg'), _goodPassword);
      expect(auth.sessionsOf('awa@test.tg'), hasLength(1));
    });
  });

  group('changer de mot de passe', () {
    Future<String> signedIn(String email, {String? password}) async {
      auth.addAccount(email, password: password);
      // Session ouverte comme après une connexion.
      final client = IviaApiClient(
        config: ApiConfig(baseUrl: Uri.parse('http://api.test')),
        adapter: server,
      );
      final session = password != null
          ? await client.login(email, password)
          : null;
      final token = session?.token ?? 'aucun';
      await SessionStore().save(token, User.fromJson(userBody(complete: true)));
      return token;
    }

    testWidgets('actuel puis nouveau : changé, autres appareils', (
      tester,
    ) async {
      await tester.runAsync(
        () => signedIn('awa@test.tg', password: 'ancien-pagne-2026'),
      );
      await launch(tester, at: '/home/password');
      expect(find.text('Changer le mot de passe'), findsOneWidget);
      await tester.enterText(field('Mot de passe actuel'), 'faux-pagne-2026');
      await tester.enterText(field('Nouveau mot de passe'), _goodPassword);
      await tapText(tester, 'Enregistrer');
      expect(find.text('Mot de passe actuel incorrect.'), findsOneWidget);
      await tester.enterText(field('Mot de passe actuel'), 'ancien-pagne-2026');
      await tester.enterText(field('Nouveau mot de passe'), _goodPassword);
      await tapText(tester, 'Enregistrer');
      expect(
        find.text(
          'Mot de passe changé. Vos autres appareils sont déconnectés.',
        ),
        findsOneWidget,
      );
      expect(auth.passwordOf('awa@test.tg'), _goodPassword);
    });
  });

  group('police à 200 % sur 320 dp et lecteur d\'écran', () {
    void large(WidgetTester tester) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('connexion avec Google, erreur et aide : rien ne déborde', (
      tester,
    ) async {
      large(tester);
      auth
        ..google = true
        ..addAccount('awa@test.tg');
      google.available = true;
      await launch(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Continuer avec Google'), findsOneWidget);
      await tester.enterText(field('Adresse e-mail'), 'awa@test.tg');
      await tester.enterText(field('Mot de passe'), 'mauvais-mot-de-passe');
      await tapText(tester, 'Se connecter');
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Vous vous connectiez'), findsOneWidget);
    });

    testWidgets('création : e-mail, code, mot de passe refusé', (tester) async {
      large(tester);
      await launch(tester);
      await tapText(tester, 'Créer un compte');
      expect(tester.takeException(), isNull);
      await tester.enterText(field('Adresse e-mail'), 'ama@test.tg');
      await tapText(tester, 'Recevoir le code');
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.descendant(
          of: find.byType(IviaCodeInput),
          matching: find.byType(TextField),
        ),
        auth.lastCode('ama@test.tg', 'signup')!,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(field('Mot de passe'), 'court');
      await tapText(tester, 'Créer mon compte');
      expect(tester.takeException(), isNull);
      expect(
        find.text('Le mot de passe doit faire au moins 10 caractères.'),
        findsOneWidget,
      );
    });

    testWidgets('lecteur d\'écran : champs étiquetés, erreur annoncée', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      auth.addAccount('awa@test.tg');
      await launch(tester);
      expect(
        tester.getSemantics(find.byTooltip('Afficher le mot de passe')),
        isSemantics(isButton: true),
      );
      await tester.enterText(field('Adresse e-mail'), 'awa@test.tg');
      await tester.enterText(field('Mot de passe'), 'mauvais-mot-de-passe');
      await tapText(tester, 'Se connecter');
      expect(
        tester.getSemantics(find.text('E-mail ou mot de passe incorrect.')),
        isSemantics(isLiveRegion: true),
      );
      semantics.dispose();
    });
  });
}
