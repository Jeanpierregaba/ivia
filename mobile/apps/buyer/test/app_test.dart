import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_buyer/app/identity.dart';
import 'package:ivia_buyer/features/onboarding/onboarding_screen.dart';
import 'package:ivia_buyer/main.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _firstTitle = "Trouvez ce qu'il vous faut, tout près.";
const _email = 'awa@test.tg';

void main() {
  late FakeApiServer server;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    server = FakeApiServer()
      ..on('POST', '/v1/auth/otp', (_) => FakeResponse.json(202, otpBody))
      ..on(
        'POST',
        '/v1/auth/verify',
        (_) => FakeResponse.json(200, sessionBody()),
      )
      ..on(
        'PATCH',
        '/v1/me',
        (_) => FakeResponse.json(200, userBody(complete: true)),
      )
      ..on('POST', '/v1/auth/logout', (_) => FakeResponse.json(204, null));
  });

  /// Lance l'app comme main(), avec le stockage tel qu'il est.
  Future<void> launchApp(
    WidgetTester tester, {
    Duration minSplash = Duration.zero,
    bool settle = true,
  }) async {
    final store = await OnboardingStore.open();
    // Nouvel arbre : simule un redémarrage de l'app.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(store),
          appIdentityProvider.overrideWithValue(buyerIdentity),
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
        ],
        child: const BuyerApp(),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    // Fait défiler jusqu'au bouton, comme l'utilisateur (petit écran).
    final target = find.text(text, skipOffstage: false);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<bool?> seenFlag() async =>
      (await SharedPreferences.getInstance()).getBool('onboarding_seen');

  /// Présentation déjà vue : l'app s'ouvre sur la connexion.
  void onboardingSeen() =>
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});

  Future<void> enterEmail(WidgetTester tester, [String email = _email]) async {
    await tester.enterText(find.byType(TextField), email);
    await tapText(tester, 'Recevoir le code');
  }

  Future<void> enterCode(WidgetTester tester, [String code = '481902']) async {
    await tester.enterText(find.byType(TextField), code);
    await tester.pump();
    await tapText(tester, 'Vérifier le code');
  }

  /// L'écran du code a un compte à rebours : on le laisse finir.
  Future<void> finishCountdown(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 61));

  group('démarrage et présentation', () {
    testWidgets("l'app utilise le thème ivia", (tester) async {
      await launchApp(tester);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.title, 'ivia');
      expect(app.theme?.colorScheme.primary, IviaColors.primary);
    });

    testWidgets('splash de chargement au moins 800 ms', (tester) async {
      await launchApp(
        tester,
        minSplash: const Duration(milliseconds: 800),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Tout, près de chez vous.'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text(_firstTitle), findsOneWidget);
    });

    testWidgets('premier lancement : la présentation de l\'acheteur', (
      tester,
    ) async {
      await launchApp(tester);
      expect(find.text(_firstTitle), findsOneWidget);
      final onboarding = tester.widget<IviaOnboarding>(
        find.byType(IviaOnboarding),
      );
      expect(onboarding.brand, IviaAppBrand.buyer);
      expect(onboarding.slides, hasLength(3));
    });

    testWidgets('« Passer » depuis la page 2 : connexion, puis plus jamais', (
      tester,
    ) async {
      await launchApp(tester);
      await tapText(tester, 'Suivant');
      await tapText(tester, 'Passer');
      expect(find.text('Bienvenue sur ivia'), findsOneWidget);
      expect(await seenFlag(), isTrue);

      await launchApp(tester);
      expect(find.text('Bienvenue sur ivia'), findsOneWidget);
      expect(find.byType(IviaOnboarding), findsNothing);
    });

    testWidgets('« Commencer » : connexion et présentation mémorisée', (
      tester,
    ) async {
      await launchApp(tester);
      await tapText(tester, 'Suivant');
      await tapText(tester, 'Suivant');
      await tapText(tester, 'Commencer');
      expect(find.text('Bienvenue sur ivia'), findsOneWidget);
      expect(await seenFlag(), isTrue);
    });

    testWidgets('app fermée pendant la présentation : reprise à la page 1', (
      tester,
    ) async {
      await launchApp(tester);
      await tapText(tester, 'Suivant');
      await launchApp(tester);
      expect(find.text(_firstTitle), findsOneWidget);
    });

    testWidgets('retour Android : page précédente, puis sortie de l\'app', (
      tester,
    ) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      await launchApp(tester);
      await tapText(tester, 'Suivant');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(_firstTitle), findsOneWidget);
      expect(calls, isNot(contains('SystemNavigator.pop')));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(calls, contains('SystemNavigator.pop'));
    });

    testWidgets('titres : aucun mot coupé sur 320 dp, police agrandie', (
      tester,
    ) async {
      // Vraie police (les tests utilisent sinon une police de substitution).
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

  group('connexion', () {
    setUp(onboardingSeen);

    testWidgets('nouveau compte : e-mail, code, profil, accueil', (
      tester,
    ) async {
      await launchApp(tester);
      await enterEmail(tester, '  Awa@Test.tg ');
      expect(find.text('Vérifiez vos e-mails'), findsOneWidget);
      expect(find.textContaining(_email, findRichText: true), findsOneWidget);
      expect(server.last.body, {'channel': 'email', 'recipient': _email});

      await enterCode(tester);
      expect(find.text('Faisons connaissance'), findsOneWidget);
      expect(find.text('Dernière étape'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), ' Awa ');
      await tester.enterText(fields.at(1), 'Mensah');
      await tester.enterText(fields.at(2), '+228 90 12 34 56');
      await tester.pump();
      expect(
        tester.widget<TextField>(fields.at(2)).controller!.text,
        '90 12 34 56',
      );
      await tester.tap(find.byType(Checkbox));
      await tapText(tester, 'Créer mon compte');

      expect(server.calls('PATCH', '/v1/me').single.body, {
        'first_name': 'Awa',
        'last_name': 'Mensah',
        'phone': '+22890123456',
        'accept_privacy_policy': true,
      });
      expect(find.text('Bonjour Awa'), findsOneWidget);
      final stored = await SessionStore().read();
      expect(stored?.token, 'jeton-secret');
      expect(stored?.user?.profileComplete, isTrue);
    });

    testWidgets('compte déjà complet : accueil directement', (tester) async {
      server.on(
        'POST',
        '/v1/auth/verify',
        (_) => FakeResponse.json(200, sessionBody(complete: true)),
      );
      await launchApp(tester);
      await enterEmail(tester);
      await enterCode(tester);
      expect(find.text('Bonjour Awa'), findsOneWidget);
    });

    testWidgets('relance avec une session : accueil sans connexion', (
      tester,
    ) async {
      await SessionStore().save(
        'jeton-secret',
        User.fromJson(userBody(complete: true)),
      );
      server.on(
        'GET',
        '/v1/me',
        (_) => FakeResponse.json(200, userBody(complete: true)),
      );
      await launchApp(tester);
      expect(find.text('Bonjour Awa'), findsOneWidget);
    });

    testWidgets('adresse invalide : aucune requête', (tester) async {
      await launchApp(tester);
      await enterEmail(tester, 'awa@');
      expect(find.text('Saisissez une adresse e-mail valide.'), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('réseau coupé : message, bouton de nouveau actif', (
      tester,
    ) async {
      server.on('POST', '/v1/auth/otp', (_) => FakeResponse.networkError());
      await launchApp(tester);
      await enterEmail(tester);
      expect(find.textContaining('Pas de connexion internet'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('trop de demandes : message du serveur', (tester) async {
      server.on(
        'POST',
        '/v1/auth/otp',
        (_) => FakeResponse.error(
          429,
          'otp_rate_limited',
          'Patientez une minute avant de demander un nouveau code.',
        ),
      );
      await launchApp(tester);
      await enterEmail(tester);
      expect(find.textContaining('Patientez une minute'), findsOneWidget);
      expect(find.text('Bienvenue sur ivia'), findsOneWidget);
    });

    testWidgets('code faux : message, cases vidées', (tester) async {
      server.on(
        'POST',
        '/v1/auth/verify',
        (_) => FakeResponse.error(401, 'otp_invalid', 'Code incorrect.'),
      );
      await launchApp(tester);
      await enterEmail(tester);
      await enterCode(tester, '000000');
      expect(find.text('Code incorrect.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(find.text('Vérifiez vos e-mails'), findsOneWidget);
      await finishCountdown(tester);
    });

    testWidgets('« Vérifier le code » inactif tant que le code est incomplet', (
      tester,
    ) async {
      await launchApp(tester);
      await enterEmail(tester);
      await tester.enterText(find.byType(TextField), '4819');
      await tester.pump();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      await finishCountdown(tester);
    });

    testWidgets('renvoi du code après le compte à rebours', (tester) async {
      await launchApp(tester);
      await enterEmail(tester);
      expect(find.textContaining('Renvoyer le code dans'), findsOneWidget);
      expect(find.textContaining('1:00', findRichText: true), findsOneWidget);

      await tester.pump(const Duration(seconds: 18));
      expect(find.textContaining('0:42', findRichText: true), findsOneWidget);

      await finishCountdown(tester);
      await tapText(tester, 'Renvoyer le code');
      expect(server.calls('POST', '/v1/auth/otp'), hasLength(2));
      expect(find.textContaining('1:00', findRichText: true), findsOneWidget);
      await finishCountdown(tester);
    });

    testWidgets(
      '« Modifier l\'adresse » : retour à l\'e-mail, adresse gardée',
      (tester) async {
        await launchApp(tester);
        await enterEmail(tester);
        await tapText(tester, "Modifier l'adresse");
        expect(find.text('Bienvenue sur ivia'), findsOneWidget);
        expect(find.text(_email), findsOneWidget);
      },
    );
  });

  group('connexion : cas limites', () {
    setUp(onboardingSeen);

    for (final (code, message) in [
      ('otp_expired', 'Ce code a expiré. Demandez-en un nouveau.'),
      ('otp_too_many_attempts', 'Trop d\'essais. Demandez un nouveau code.'),
    ]) {
      testWidgets('$code : message, cases vidées, focus sur le code', (
        tester,
      ) async {
        server.on(
          'POST',
          '/v1/auth/verify',
          (_) => FakeResponse.error(400, code, message),
        );
        await launchApp(tester);
        await enterEmail(tester);
        await enterCode(tester);
        expect(find.text(message), findsOneWidget);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, '');
        expect(field.focusNode!.hasFocus, isTrue);
        await finishCountdown(tester);
      });
    }

    testWidgets('code collé avec des espaces : accepté', (tester) async {
      await launchApp(tester);
      await enterEmail(tester);
      await tester.enterText(find.byType(TextField), '481 902');
      await tester.pump();
      await tapText(tester, 'Vérifier le code');
      expect(server.calls('POST', '/v1/auth/verify').single.body, {
        'channel': 'email',
        'recipient': _email,
        'code': '481902',
      });
    });

    testWidgets('double appui : une seule demande de code', (tester) async {
      final reply = Completer<FakeResponse>();
      server.on('POST', '/v1/auth/otp', (_) => reply.future);
      await launchApp(tester);
      await tester.enterText(find.byType(TextField), _email);
      await tester.tap(find.text('Recevoir le code'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      reply.complete(FakeResponse.json(202, otpBody));
      await tester.pumpAndSettle();
      expect(server.calls('POST', '/v1/auth/otp'), hasLength(1));
      expect(find.text('Vérifiez vos e-mails'), findsOneWidget);
      await finishCountdown(tester);
    });

    testWidgets('double appui : une seule vérification du code', (
      tester,
    ) async {
      final reply = Completer<FakeResponse>();
      server.on('POST', '/v1/auth/verify', (_) => reply.future);
      await launchApp(tester);
      await enterEmail(tester);
      await tester.enterText(find.byType(TextField), '481902');
      await tester.pump();
      await tester.tap(find.text('Vérifier le code'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      reply.complete(FakeResponse.json(200, sessionBody()));
      await tester.pumpAndSettle();
      expect(server.calls('POST', '/v1/auth/verify'), hasLength(1));
      expect(find.text('Faisons connaissance'), findsOneWidget);
    });

    testWidgets(
      'session refusée pendant l\'utilisation : retour à la connexion',
      (tester) async {
        await SessionStore().save(
          'jeton-secret',
          User.fromJson(userBody(complete: true)),
        );
        server.on(
          'GET',
          '/v1/me',
          (_) => FakeResponse.json(200, userBody(complete: true)),
        );
        await launchApp(tester);
        expect(find.text('Bonjour Awa'), findsOneWidget);

        server.on(
          'GET',
          '/v1/me',
          (_) => FakeResponse.error(401, 'unauthorized', 'Session expirée.'),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(BuyerApp)),
        );
        await tester.runAsync(
          () => container
              .read(apiClientProvider)
              .getMe()
              .catchError((_) => User.fromJson(userBody())),
        );
        await tester.pumpAndSettle();
        expect(find.text('Bienvenue sur ivia'), findsOneWidget);
        expect(await SessionStore().read(), isNull);
      },
    );

    testWidgets('serveur injoignable sans profil gardé : « Réessayer »', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({
        'session_token': 'jeton-secret',
      });
      server.on('GET', '/v1/me', (_) => FakeResponse.networkError());
      await launchApp(tester);
      expect(find.text('Pas de connexion'), findsOneWidget);

      server.on(
        'GET',
        '/v1/me',
        (_) => FakeResponse.json(200, userBody(complete: true)),
      );
      await tapText(tester, 'Réessayer');
      expect(find.text('Bonjour Awa'), findsOneWidget);
    });

    for (final screen in ['e-mail', 'code']) {
      testWidgets('écran $screen, police à 200 % sur 320 dp', (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await launchApp(tester);
        if (screen == 'code') {
          await enterEmail(tester);
          expect(find.text('Vérifiez vos e-mails'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        if (screen == 'code') await finishCountdown(tester);
      });
    }
  });

  testWidgets('illustrations ignorées par le lecteur d\'écran', (tester) async {
    final semantics = tester.ensureSemantics();
    await launchApp(tester);
    expect(find.text('Riz parfumé 5 kg'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Riz parfumé')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('tout près')), findsOneWidget);
    semantics.dispose();
  });

  group('profil', () {
    setUp(onboardingSeen);

    Future<void> reachProfile(WidgetTester tester) async {
      await launchApp(tester);
      await enterEmail(tester);
      await enterCode(tester);
    }

    Future<void> fillProfile(
      WidgetTester tester, {
      String phone = '90123456',
    }) async {
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Awa');
      await tester.enterText(fields.at(1), 'Mensah');
      await tester.enterText(fields.at(2), phone);
      await tester.pump();
    }

    testWidgets('consentement manquant : aucun envoi, message', (tester) async {
      await reachProfile(tester);
      await fillProfile(tester);
      await tester.ensureVisible(find.text('Créer mon compte'));
      await tapText(tester, 'Créer mon compte');
      expect(find.textContaining('Cochez la case'), findsOneWidget);
      expect(server.calls('PATCH', '/v1/me'), isEmpty);
    });

    testWidgets('champs vides et numéro invalide : messages', (tester) async {
      await reachProfile(tester);
      await fillProfile(tester, phone: '123');
      await tester.enterText(find.byType(TextField).at(0), '  ');
      await tester.tap(find.byType(Checkbox));
      await tapText(tester, 'Créer mon compte');
      expect(find.text('Saisissez votre prénom.'), findsOneWidget);
      expect(find.textContaining('Numéro mobile togolais'), findsOneWidget);
      expect(server.calls('PATCH', '/v1/me'), isEmpty);
    });

    testWidgets('numéro déjà utilisé : message sous le téléphone', (
      tester,
    ) async {
      server.on(
        'PATCH',
        '/v1/me',
        (_) => FakeResponse.error(
          409,
          'phone_taken',
          'Ce numéro est déjà utilisé par un autre compte.',
        ),
      );
      await reachProfile(tester);
      await fillProfile(tester);
      await tester.tap(find.byType(Checkbox));
      await tapText(tester, 'Créer mon compte');
      expect(
        find.text('Ce numéro est déjà utilisé par un autre compte.'),
        findsOneWidget,
      );
      expect(find.text('Faisons connaissance'), findsOneWidget);
    });

    testWidgets('retour : déconnexion, écran de connexion', (tester) async {
      await reachProfile(tester);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(server.calls('POST', '/v1/auth/logout'), hasLength(1));
      expect(find.text('Bienvenue sur ivia'), findsOneWidget);
      expect(await SessionStore().read(), isNull);
    });

    testWidgets('téléphone refusé par le serveur : message sous le champ', (
      tester,
    ) async {
      server.on(
        'PATCH',
        '/v1/me',
        (_) => FakeResponse.error(
          400,
          'validation_failed',
          'Données invalides.',
          fields: {'phone': 'Ce numéro n\'est pas un mobile togolais.'},
        ),
      );
      await reachProfile(tester);
      await fillProfile(tester);
      await tester.tap(find.byType(Checkbox));
      await tapText(tester, 'Créer mon compte');
      expect(
        find.text('Ce numéro n\'est pas un mobile togolais.'),
        findsOneWidget,
      );
    });

    testWidgets('prénom de plus de 100 caractères : refusé', (tester) async {
      await reachProfile(tester);
      await fillProfile(tester);
      await tester.enterText(find.byType(TextField).at(0), 'A' * 101);
      await tester.tap(find.byType(Checkbox));
      await tapText(tester, 'Créer mon compte');
      expect(find.text('100 caractères au plus.'), findsOneWidget);
      expect(server.calls('PATCH', '/v1/me'), isEmpty);
    });

    testWidgets('envoi en cours : un seul envoi, retour bloqué', (
      tester,
    ) async {
      final reply = Completer<FakeResponse>();
      server.on('PATCH', '/v1/me', (_) => reply.future);
      await reachProfile(tester);
      await fillProfile(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.ensureVisible(
        find.text('Créer mon compte', skipOffstage: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer mon compte'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.tap(find.byTooltip('Retour'), warnIfMissed: false);
      await tester.binding.handlePopRoute();
      await tester.pump();
      reply.complete(FakeResponse.json(200, userBody(complete: true)));
      await tester.pumpAndSettle();
      expect(server.calls('PATCH', '/v1/me'), hasLength(1));
      expect(server.calls('POST', '/v1/auth/logout'), isEmpty);
      expect(find.text('Bonjour Awa'), findsOneWidget);
    });

    testWidgets('police à 200 % sur 320 dp : pas de débordement', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await reachProfile(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Faisons connaissance'), findsOneWidget);
    });
  });

  testWidgets('accueil : « Se déconnecter » révoque et efface la session', (
    tester,
  ) async {
    onboardingSeen();
    await SessionStore().save(
      'jeton-secret',
      User.fromJson(userBody(complete: true)),
    );
    server.on(
      'GET',
      '/v1/me',
      (_) => FakeResponse.json(200, userBody(complete: true)),
    );
    await launchApp(tester);
    await tapText(tester, 'Se déconnecter');
    expect(
      server.calls('POST', '/v1/auth/logout').single.headers['authorization'],
      'Bearer jeton-secret',
    );
    expect(find.text('Bienvenue sur ivia'), findsOneWidget);
    expect(await SessionStore().read(), isNull);
  });
}
