import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_app_core/testing.dart';
import 'package:ivia_buyer/app/buyer_area.dart';
import 'package:ivia_buyer/app/identity.dart';
import 'package:ivia_buyer/features/search/search_state.dart';
import 'package:ivia_buyer/features/onboarding/onboarding_screen.dart';
import 'package:ivia_buyer/main.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _firstTitle = "Trouvez ce qu'il vous faut, tout près.";
const _phone = '+22890123456';

/// Numéro nouveau : inscription à terminer.
const _signupRequired = {
  'status': 'signup_required',
  'signup_token': 'jeton-inscription',
  'signup_expires_at': '2026-11-05T10:15:00Z',
};

class _DeniedLocation extends FakeLocationService {
  _DeniedLocation()
    : super(next: const LocationResult.failed(LocationFailure.denied));
}

void main() {
  late FakeApiServer server;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    server = FakeApiServer()
      ..on(
        'POST',
        '/v1/auth/phone/code',
        (_) => FakeResponse.json(202, phoneOtpBody),
      )
      ..on(
        'POST',
        '/v1/auth/phone/verify',
        (_) => FakeResponse.json(200, _signupRequired),
      )
      ..on(
        'POST',
        '/v1/auth/phone/signup',
        (_) => FakeResponse.json(201, phoneSessionBody(newUser: true)),
      )
      ..on(
        'PATCH',
        '/v1/me',
        (_) => FakeResponse.json(200, userBody(complete: true)),
      )
      ..on('POST', '/v1/auth/logout', (_) => FakeResponse.json(204, null));
  });

  /// Position du dernier lancement (jamais le GPS du poste de test).
  late FakeLocationService location;

  /// Lance l'app comme main(), avec le stockage tel qu'il est ; position
  /// autorisée sauf [access] contraire.
  Future<void> launchApp(
    WidgetTester tester, {
    Duration minSplash = Duration.zero,
    bool settle = true,
    LocationAccess access = LocationAccess.granted,
  }) async {
    final store = await OnboardingStore.open();
    final area = await AreaStore.open();
    location = _DeniedLocation()..state = access;
    final locationPrompt = await LocationPromptStore.open(location);
    // Nouvel arbre : simule un redémarrage de l'app.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(store),
          areaStoreProvider.overrideWithValue(area),
          locationServiceProvider.overrideWithValue(location),
          locationPromptStoreProvider.overrideWithValue(locationPrompt),
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
    // Listes longues (profil) : l'élément n'est construit qu'en s'en approchant.
    for (var i = 0; i < 12 && target.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
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

  Future<void> enterPhone(
    WidgetTester tester, [
    String phone = '90 12 34 56',
  ]) async {
    await tester.enterText(find.byType(TextField), phone);
    await tapText(tester, 'Recevoir le code sur WhatsApp');
  }

  /// Le 6e chiffre lance la vérification, sans appui.
  Future<void> enterCode(WidgetTester tester, [String code = '481902']) async {
    await tester.enterText(find.byType(TextField), code);
    await tester.pumpAndSettle();
  }

  /// Numéro connu : la vérification ouvre la session.
  void signedInOnVerify([Map<String, dynamic>? session]) => server.on(
    'POST',
    '/v1/auth/phone/verify',
    (_) => FakeResponse.json(200, {
      'status': 'signed_in',
      'session': session ?? phoneSessionBody(),
    }),
  );

  Future<void> reachSignup(WidgetTester tester) async {
    await launchApp(tester);
    await enterPhone(tester);
    await enterCode(tester);
  }

  Future<void> fillSignup(WidgetTester tester) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Awa');
    await tester.enterText(fields.at(1), 'Mensah');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
  }

  /// L'écran du code a un compte à rebours : on le laisse finir.
  Future<void> finishCountdown(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 61));

  group('autorisation de la localisation (030)', () {
    const title = "Tout ce qu'il vous faut, près de vous";

    testWidgets('premier lancement : écran après le splash, « Plus tard »', (
      tester,
    ) async {
      await launchApp(tester, access: LocationAccess.askable);
      expect(find.text(title, findRichText: true), findsOneWidget);
      expect(find.byType(IviaOnboarding), findsNothing);
      await tapText(tester, 'Plus tard');
      expect(find.text(_firstTitle), findsOneWidget);
      expect(location.requests, 0);
      expect(
        (await SharedPreferences.getInstance()).getBool('location_prompt_done'),
        isTrue,
      );

      // Relancée : plus d'écran, même sans autorisation.
      await launchApp(tester, access: LocationAccess.askable);
      expect(find.text(title, findRichText: true), findsNothing);
      expect(find.text(_firstTitle), findsOneWidget);
    });

    testWidgets('« Autoriser » : fenêtre du système, puis présentation', (
      tester,
    ) async {
      await launchApp(tester, access: LocationAccess.askable);
      await tapText(tester, 'Autoriser la localisation');
      expect(location.requests, 1);
      expect(find.text(_firstTitle), findsOneWidget);
    });

    testWidgets('refus définitif : « Autoriser » ouvre les réglages', (
      tester,
    ) async {
      await launchApp(tester, access: LocationAccess.deniedForever);
      await tapText(tester, 'Autoriser la localisation');
      expect(location.settingsOpened, 1);
      expect(location.requests, 0);
      expect(find.text(_firstTitle), findsOneWidget);
    });

    testWidgets('position déjà autorisée : pas d\'écran', (tester) async {
      await launchApp(tester);
      expect(find.text(title, findRichText: true), findsNothing);
      expect(find.text(_firstTitle), findsOneWidget);
    });
  });

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

  group('connexion par numéro', () {
    setUp(onboardingSeen);

    testWidgets('nouveau numéro : numéro, code, nom, accueil', (tester) async {
      await launchApp(tester);
      expect(find.text('Bienvenue sur ivia'), findsOneWidget);
      await enterPhone(tester, '+228 90 12 34 56');
      expect(find.text('Saisissez le code'), findsOneWidget);
      expect(
        find.textContaining('WhatsApp au +228 90 12 34 56', findRichText: true),
        findsOneWidget,
      );
      final sent =
          server.calls('POST', '/v1/auth/phone/code').single.body
              as Map<String, dynamic>;
      expect(sent['phone'], _phone);
      expect(sent['channel'], 'whatsapp');
      expect(sent['app'], 'buyer');
      expect((sent['device_id'] as String).length, greaterThanOrEqualTo(16));

      await enterCode(tester);
      expect(
        (server.calls('POST', '/v1/auth/phone/verify').single.body
            as Map)['code'],
        '481902',
      );
      expect(find.text('Faisons connaissance'), findsOneWidget);
      expect(find.text('Dernière étape'), findsOneWidget);

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2)); // pas de téléphone : il est vérifié
      await tester.enterText(fields.at(0), ' Awa ');
      await tester.enterText(fields.at(1), 'Mensah');
      await tester.tap(find.byType(Checkbox));
      await tapText(tester, 'Créer mon compte');

      final signup =
          server.calls('POST', '/v1/auth/phone/signup').single.body
              as Map<String, dynamic>;
      expect(signup['signup_token'], 'jeton-inscription');
      expect(signup['first_name'], 'Awa');
      expect(signup['last_name'], 'Mensah');
      expect(signup['accept_privacy_policy'], isTrue);
      expect(signup['device_id'], sent['device_id']);
      expect(find.textContaining('Bonjour Awa'), findsOneWidget);
      final stored = await SessionStore().read();
      expect(stored?.token, 'jeton-acces');
      expect(stored?.refreshToken, 'jeton-rafraichissement');
    });

    testWidgets('numéro connu : accueil directement après le code', (
      tester,
    ) async {
      signedInOnVerify();
      await launchApp(tester);
      await enterPhone(tester);
      await enterCode(tester);
      expect(find.textContaining('Bonjour Awa'), findsOneWidget);
      expect(server.calls('POST', '/v1/auth/phone/signup'), isEmpty);
    });

    testWidgets('« Recevoir par SMS » : code demandé par SMS', (tester) async {
      server.on(
        'POST',
        '/v1/auth/phone/code',
        (_) => FakeResponse.json(202, {...phoneOtpBody, 'channel': 'sms'}),
      );
      await launchApp(tester);
      await tester.enterText(find.byType(TextField), '90123456');
      await tapText(tester, 'Recevoir par SMS');
      expect((server.last.body as Map)['channel'], 'sms');
      expect(
        find.textContaining('envoyé par SMS au', findRichText: true),
        findsOneWidget,
      );
      await finishCountdown(tester);
    });

    testWidgets(
      'WhatsApp en échec : l\'écran dit que le code est parti par SMS',
      (tester) async {
        server.on(
          'POST',
          '/v1/auth/phone/code',
          (_) => FakeResponse.json(202, {...phoneOtpBody, 'channel': 'sms'}),
        );
        await launchApp(tester);
        await enterPhone(tester);
        expect(find.textContaining('il est parti par SMS'), findsOneWidget);
        await finishCountdown(tester);
      },
    );

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
      expect(find.textContaining('Bonjour Awa'), findsOneWidget);
    });

    testWidgets('jeton d\'accès expiré au démarrage : renouvelé sans rien '
        'demander', (tester) async {
      await SessionStore().save(
        'ancien-acces',
        User.fromJson(userBody(complete: true)),
        refreshToken: 'ancien-refresh',
      );
      server
        ..on('GET', '/v1/me', (r) {
          if (r.headers['authorization'] == 'Bearer ancien-acces') {
            return FakeResponse.error(
              401,
              'access_token_expired',
              'Session à renouveler.',
            );
          }
          return FakeResponse.json(200, userBody(complete: true));
        })
        ..on(
          'POST',
          '/v1/auth/refresh',
          (_) => FakeResponse.json(
            200,
            phoneSessionBody(token: 'nouvel-acces', refresh: 'nouveau-refresh'),
          ),
        );
      await launchApp(tester);
      expect(find.textContaining('Bonjour Awa'), findsOneWidget);
      final stored = await SessionStore().read();
      expect(stored?.token, 'nouvel-acces');
      expect(stored?.refreshToken, 'nouveau-refresh');
    });

    testWidgets('numéro invalide : aucune requête', (tester) async {
      await launchApp(tester);
      await enterPhone(tester, '123');
      expect(find.textContaining('Numéro mobile togolais'), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('réseau coupé : message, bouton de nouveau actif', (
      tester,
    ) async {
      server.on(
        'POST',
        '/v1/auth/phone/code',
        (_) => FakeResponse.networkError(),
      );
      await launchApp(tester);
      await enterPhone(tester);
      expect(find.textContaining('Pas de connexion internet'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Recevoir le code sur WhatsApp'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    for (final (code, status, message) in [
      (
        'otp_rate_limited',
        429,
        'Un code vient d\'être envoyé. Patientez une minute.',
      ),
      (
        'phone_locked',
        429,
        'Trop de codes incorrects. Ce numéro est bloqué pendant 15 minutes.',
      ),
      (
        'otp_service_busy',
        503,
        'Le service est très demandé. Réessayez dans quelques minutes.',
      ),
    ]) {
      testWidgets('$code : message du serveur, pas de changement d\'écran', (
        tester,
      ) async {
        server.on(
          'POST',
          '/v1/auth/phone/code',
          (_) => FakeResponse.error(status, code, message),
        );
        await launchApp(tester);
        await enterPhone(tester);
        expect(find.text(message), findsOneWidget);
        expect(find.text('Bienvenue sur ivia'), findsOneWidget);
      });
    }

    testWidgets('code faux : message, cases vidées', (tester) async {
      server.on(
        'POST',
        '/v1/auth/phone/verify',
        (_) =>
            FakeResponse.error(401, 'otp_invalid', 'Code incorrect ou expiré.'),
      );
      await launchApp(tester);
      await enterPhone(tester);
      await enterCode(tester, '000000');
      expect(find.text('Code incorrect ou expiré.'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(find.text('Saisissez le code'), findsOneWidget);
      await finishCountdown(tester);
    });

    testWidgets('« Vérifier le code » inactif tant que le code est incomplet', (
      tester,
    ) async {
      await launchApp(tester);
      await enterPhone(tester);
      await tester.enterText(find.byType(TextField), '4819');
      await tester.pump();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(server.calls('POST', '/v1/auth/phone/verify'), isEmpty);
      await finishCountdown(tester);
    });

    testWidgets('renvoi après le compte à rebours, puis passage au SMS', (
      tester,
    ) async {
      await launchApp(tester);
      await enterPhone(tester);
      expect(find.textContaining('1:00', findRichText: true), findsOneWidget);
      await tester.pump(const Duration(seconds: 18));
      expect(find.textContaining('0:42', findRichText: true), findsOneWidget);

      await finishCountdown(tester);
      await tapText(tester, 'Renvoyer le code');
      expect(server.calls('POST', '/v1/auth/phone/code'), hasLength(2));
      expect(find.text('Nouveau code envoyé sur WhatsApp.'), findsOneWidget);

      await finishCountdown(tester);
      server.on(
        'POST',
        '/v1/auth/phone/code',
        (_) => FakeResponse.json(202, {...phoneOtpBody, 'channel': 'sms'}),
      );
      // Bouton de l'écran du code (celui du numéro est caché dessous).
      await tester.tap(find.text('Recevoir par SMS'));
      await tester.pumpAndSettle();
      expect((server.last.body as Map)['channel'], 'sms');
      expect(find.text('Nouveau code envoyé par SMS.'), findsOneWidget);
      await finishCountdown(tester);
    });

    testWidgets('« Modifier le numéro » : retour, numéro gardé', (
      tester,
    ) async {
      await launchApp(tester);
      await enterPhone(tester);
      await tapText(tester, 'Modifier le numéro');
      expect(find.text('Bienvenue sur ivia'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '90 12 34 56',
      );
    });
  });

  group('connexion par numéro : cas limites', () {
    setUp(onboardingSeen);

    testWidgets('code collé avec des espaces : accepté', (tester) async {
      await launchApp(tester);
      await enterPhone(tester);
      await enterCode(tester, '481 902');
      expect(
        (server.calls('POST', '/v1/auth/phone/verify').single.body
            as Map)['code'],
        '481902',
      );
    });

    testWidgets('double appui : une seule demande de code', (tester) async {
      final reply = Completer<FakeResponse>();
      server.on('POST', '/v1/auth/phone/code', (_) => reply.future);
      await launchApp(tester);
      await tester.enterText(find.byType(TextField), '90123456');
      await tester.tap(find.text('Recevoir le code sur WhatsApp'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
      await tester.pump();
      reply.complete(FakeResponse.json(202, phoneOtpBody));
      await tester.pumpAndSettle();
      expect(server.calls('POST', '/v1/auth/phone/code'), hasLength(1));
      expect(find.text('Saisissez le code'), findsOneWidget);
      await finishCountdown(tester);
    });

    testWidgets('vérification en cours : une seule vérification', (
      tester,
    ) async {
      final reply = Completer<FakeResponse>();
      server.on('POST', '/v1/auth/phone/verify', (_) => reply.future);
      await launchApp(tester);
      await enterPhone(tester);
      await tester.enterText(find.byType(TextField), '481902');
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      reply.complete(FakeResponse.json(200, _signupRequired));
      await tester.pumpAndSettle();
      expect(server.calls('POST', '/v1/auth/phone/verify'), hasLength(1));
      expect(find.text('Faisons connaissance'), findsOneWidget);
    });

    testWidgets('inscription expirée : retour au numéro avec un message', (
      tester,
    ) async {
      server.on(
        'POST',
        '/v1/auth/phone/signup',
        (_) => FakeResponse.error(
          401,
          'signup_expired',
          'Votre inscription a expiré. Recommencez avec un nouveau code.',
        ),
      );
      await reachSignup(tester);
      await fillSignup(tester);
      await tapText(tester, 'Créer mon compte');
      expect(find.text('Bienvenue sur ivia'), findsOneWidget);
      expect(find.textContaining('Votre inscription a expiré'), findsOneWidget);
    });

    testWidgets('inscription : consentement et noms obligatoires', (
      tester,
    ) async {
      await reachSignup(tester);
      await tester.enterText(find.byType(TextField).at(0), '  ');
      await tapText(tester, 'Créer mon compte');
      expect(find.text('Saisissez votre prénom.'), findsOneWidget);
      expect(find.text('Saisissez votre nom.'), findsOneWidget);
      expect(find.textContaining('Cochez la case'), findsOneWidget);
      expect(server.calls('POST', '/v1/auth/phone/signup'), isEmpty);
    });

    testWidgets('inscription : retour au numéro, inscription abandonnée', (
      tester,
    ) async {
      await reachSignup(tester);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(find.text('Bienvenue sur ivia'), findsOneWidget);
      expect(server.calls('POST', '/v1/auth/phone/signup'), isEmpty);
      expect(await SessionStore().read(), isNull);
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
        expect(find.textContaining('Bonjour Awa'), findsOneWidget);

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
      expect(find.textContaining('Bonjour Awa'), findsOneWidget);
    });

    for (final screen in ['numéro', 'code', 'inscription']) {
      testWidgets('écran $screen, police à 200 % sur 320 dp', (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        if (screen == 'inscription') {
          await reachSignup(tester);
          expect(find.text('Faisons connaissance'), findsOneWidget);
        } else {
          await launchApp(tester);
          if (screen == 'code') {
            await enterPhone(tester);
            expect(find.text('Saisissez le code'), findsOneWidget);
          }
        }
        expect(tester.takeException(), isNull);
        if (screen == 'code') await finishCountdown(tester);
      });
    }
  });

  testWidgets('illustrations ignorées par le lecteur d\'écran', (tester) async {
    final semantics = tester.ensureSemantics();
    await launchApp(tester);
    expect(find.text('Coffret de 12 macarons'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('macarons')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('tout près')), findsOneWidget);
    semantics.dispose();
  });

  group('profil', () {
    setUp(onboardingSeen);

    /// Compte existant au profil incomplet (créé avant la connexion par
    /// numéro) : « Faisons connaissance » avec le téléphone à saisir.
    Future<void> reachProfile(WidgetTester tester) async {
      signedInOnVerify(sessionBody());
      await launchApp(tester);
      await enterPhone(tester);
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
      expect(find.textContaining('Bonjour Awa'), findsOneWidget);
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

  testWidgets("profil : appareils connectés, déconnexion d'un autre appareil", (
    tester,
  ) async {
    onboardingSeen();
    await SessionStore().save(
      'jeton-secret',
      User.fromJson(userBody(complete: true)),
    );
    var revoked = false;
    server
      ..on(
        'GET',
        '/v1/me',
        (_) => FakeResponse.json(200, userBody(complete: true)),
      )
      ..on(
        'GET',
        '/v1/me/sessions',
        (_) => FakeResponse.json(200, {
          'items': [
            {
              'id': 's1',
              'device_name': 'Téléphone Android',
              'user_agent': 'Dart',
              'app': 'buyer',
              'created_at': '2026-11-05T08:00:00Z',
              'last_used_at': '2026-11-05T09:00:00Z',
              'current': true,
            },
            if (!revoked)
              {
                'id': 's2',
                'device_name': 'iPhone',
                'user_agent': 'Dart',
                'app': 'buyer',
                'created_at': '2026-11-01T08:00:00Z',
                'last_used_at': '2026-11-02T09:00:00Z',
                'current': false,
              },
          ],
        }),
      )
      ..onPattern('DELETE', '/v1/me/sessions/s2', (_) {
        revoked = true;
        return FakeResponse.json(204, null);
      });
    await launchApp(tester);
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('+228 90 12 34 56'), findsOneWidget);
    await tapText(tester, 'Appareils connectés');
    expect(find.text('Cet appareil'), findsOneWidget);
    expect(find.text('iPhone'), findsOneWidget);
    await tapText(tester, 'Déconnecter');
    expect(revoked, isTrue);
    expect(find.text('iPhone'), findsNothing);
    expect(find.text('iPhone déconnecté.'), findsOneWidget);
  });

  testWidgets('profil : « Se déconnecter » révoque et efface la session', (
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
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tapText(tester, 'Se déconnecter');
    expect(
      server.calls('POST', '/v1/auth/logout').single.headers['authorization'],
      'Bearer jeton-secret',
    );
    expect(find.text('Bienvenue sur ivia'), findsOneWidget);
    expect(await SessionStore().read(), isNull);
  });

  testWidgets('barre du bas : Accueil, Recherche, Commandes, Profil', (
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
    expect(find.byType(IviaBottomNav), findsOneWidget);
    for (final label in ['Accueil', 'Recherche', 'Commandes', 'Profil']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    server.on(
      'GET',
      '/v1/orders',
      (_) => FakeResponse.json(200, {'items': <Object>[], 'next_offset': null}),
    );
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Aucune commande en cours.'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Awa Mensah'), findsOneWidget);
    expect(find.text('+228 90 12 34 56'), findsOneWidget);
    await tapText(tester, 'Ouvrir une boutique');
    expect(find.textContaining('Ivia Business'), findsWidgets);
  });

  testWidgets('autre compte : filtres de recherche remis à zéro', (
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    container
        .read(searchFiltersProvider.notifier)
        .update((f) => f.copyWith(text: 'riz', inStockOnly: true));
    container.read(searchFocusRequestProvider.notifier).request();
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tapText(tester, 'Se déconnecter');
    expect(container.read(searchFiltersProvider).text, isEmpty);
    expect(container.read(searchFiltersProvider).inStockOnly, isFalse);
    expect(container.read(searchFocusRequestProvider), 0);
  });
}
