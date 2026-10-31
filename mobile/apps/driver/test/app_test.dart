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
import 'package:ivia_driver/app/identity.dart';
import 'package:ivia_driver/features/onboarding/onboarding_screen.dart';
import 'package:ivia_driver/main.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _email = 'kossi@test.tg';

/// Image PNG de 1 × 1 pixel.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _FakePicker implements PhotoPicker {
  Uint8List? next = _png;
  final requests = <(PhotoSource, int)>[];

  @override
  Future<Uint8List?> pick({
    PhotoSource source = PhotoSource.gallery,
    int maxSide = 1024,
  }) async {
    requests.add((source, maxSide));
    return next;
  }
}

Map<String, dynamic> _user({bool complete = true}) =>
    userBody(complete: complete);

void main() {
  late FakeApiServer server;
  late _FakePicker picker;
  late List<Map<String, dynamic>> documentsSent;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    picker = _FakePicker();
    documentsSent = [];
    var upload = 0;
    server = FakeApiServer()
      ..on('POST', '/v1/auth/otp', (_) => FakeResponse.json(202, otpBody))
      ..on(
        'POST',
        '/v1/auth/verify',
        (_) => FakeResponse.json(200, {
          ...sessionBody(),
          'user': _user(complete: false),
        }),
      )
      ..on('POST', '/v1/auth/logout', (_) => FakeResponse.json(204, null))
      ..on(
        'GET',
        '/v1/driver/me',
        (_) =>
            FakeResponse.error(404, 'driver_not_found', 'Livreur introuvable.'),
      )
      ..on('PATCH', '/v1/me', (_) => FakeResponse.json(200, _user()))
      ..on('POST', '/v1/uploads', (_) {
        upload++;
        return FakeResponse.json(201, {
          'object_key': 'driver_document/u1/doc$upload.jpg',
          'upload': {
            'method': 'PUT',
            'url': 'https://prive.test/driver_document/u1/doc$upload.jpg?sig=x',
            'headers': {'Content-Type': 'image/jpeg'},
            'expires_at': '2026-10-31T10:05:00Z',
          },
        });
      })
      ..on(
        'PUT',
        '/v1/driver/application',
        (_) => FakeResponse.json(200, driverBody(documents: [])),
      )
      ..on('POST', '/v1/driver/application/documents', (request) {
        documentsSent.add(request.body! as Map<String, dynamic>);
        return FakeResponse.json(
          201,
          driverBody(
            documents: [for (final d in documentsSent) d['kind'] as String],
          ),
        );
      });
    for (var i = 1; i <= 6; i++) {
      server.on(
        'PUT',
        '/driver_document/u1/doc$i.jpg',
        (_) => FakeResponse.json(200, null),
      );
    }
  });

  Future<void> launchApp(
    WidgetTester tester, {
    Duration minSplash = Duration.zero,
    bool settle = true,
  }) async {
    final store = await OnboardingStore.open();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(store),
          appIdentityProvider.overrideWithValue(driverIdentity),
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
        ],
        child: const DriverApp(),
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

  Future<void> login(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), _email);
    await tapText(tester, 'Recevoir le code');
    await tester.enterText(find.byType(TextField), '481902');
    await tester.pump();
    await tapText(tester, 'Vérifier le code');
  }

  Future<void> signedInWith(Map<String, dynamic> user) async {
    onboardingSeen();
    await SessionStore().save('jeton-secret', User.fromJson(user));
    server.on('GET', '/v1/me', (_) => FakeResponse.json(200, user));
  }

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(IviaFieldLabel, label),
    matching: find.byType(TextField),
  );

  /// Ajoute une photo à chaque document, depuis la galerie.
  Future<void> addDocuments(WidgetTester tester) async {
    for (final label in [
      "Pièce d'identité",
      'Permis de conduire',
      'Carte grise',
    ]) {
      await tapText(tester, label);
      await tester.tap(find.text('Choisir une photo'));
      await tester.pumpAndSettle();
    }
  }

  /// Profil (s'il est demandé), immatriculation et documents.
  Future<void> fillDossier(WidgetTester tester) async {
    if (field('Prénom').evaluate().isNotEmpty) {
      await tester.enterText(field('Prénom'), 'Kossi');
      await tester.enterText(field('Nom'), 'Adjo');
      await tester.enterText(field('Téléphone'), '90123456');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
    }
    await tester.enterText(field("Numéro d'immatriculation"), 'TG 4521 AB');
    await addDocuments(tester);
  }

  group('lancement et présentation', () {
    testWidgets('thème Cobalt et splash avec tuile', (tester) async {
      await launchApp(
        tester,
        minSplash: const Duration(milliseconds: 800),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Livreur'), findsOneWidget);
      expect(find.text('Livrez près de chez vous.'), findsOneWidget);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.title, 'ivia Livreur');
      expect(app.theme?.colorScheme.primary, IviaColors.cobaltBlue);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Des missions près de vous.'), findsOneWidget);
    });

    testWidgets('présentation, puis « Espace livreur »', (tester) async {
      await launchApp(tester);
      final onboarding = tester.widget<IviaOnboarding>(
        find.byType(IviaOnboarding),
      );
      expect(onboarding.appName, 'Livreur');
      await tapText(tester, 'Passer');
      expect(find.text('Espace livreur'), findsOneWidget);
      expect(
        find.textContaining('validation de votre dossier'),
        findsOneWidget,
      );
    });

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

  group('dossier', () {
    setUp(onboardingSeen);

    testWidgets('nouveau livreur : profil, véhicule, documents, vérification', (
      tester,
    ) async {
      await launchApp(tester);
      await login(tester);
      expect(find.text('Devenez livreur ivia'), findsOneWidget);
      expect(find.text('Votre dossier'), findsOneWidget);
      // Bouton inactif tant que le dossier n'est pas complet.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Envoyer mon dossier'),
            )
            .onPressed,
        isNull,
      );

      await fillDossier(tester);
      await tapText(tester, 'Voiture');
      await tapText(tester, 'Envoyer mon dossier');

      expect(server.calls('PATCH', '/v1/me').single.body, {
        'first_name': 'Kossi',
        'last_name': 'Adjo',
        'phone': '+22890123456',
        'accept_privacy_policy': true,
      });
      expect(server.calls('PUT', '/v1/driver/application').single.body, {
        'vehicle_type': 'car',
        'vehicle_plate': 'TG 4521 AB',
      });
      expect(documentsSent.map((d) => d['kind']), [
        'id_card',
        'driving_license',
        'vehicle_registration',
      ]);
      // Profil, puis fichiers, puis candidature, puis documents.
      final paths = server.requests
          .map((r) => '${r.method} ${r.path}')
          .toList();
      expect(
        paths.indexOf('PATCH /v1/me'),
        lessThan(paths.indexOf('POST /v1/uploads')),
      );
      expect(
        paths.lastIndexOf('POST /v1/uploads'),
        lessThan(paths.indexOf('PUT /v1/driver/application')),
      );
      expect(
        paths.indexOf('PUT /v1/driver/application'),
        lessThan(paths.indexOf('POST /v1/driver/application/documents')),
      );
      // Aucun jeton vers le stockage ; documents lisibles (2048 px).
      for (final put in server.requests.where((r) => r.host == 'prive.test')) {
        expect(put.headers['authorization'], isNull);
      }
      expect(picker.requests.map((r) => r.$2).toSet(), {2048});

      expect(
        find.text('Votre dossier est en cours de vérification'),
        findsOneWidget,
      );
      expect(find.text('Moto · 3 documents'), findsOneWidget);
    });

    testWidgets('profil complet : aucun champ de profil', (tester) async {
      server.on(
        'POST',
        '/v1/auth/verify',
        (_) => FakeResponse.json(200, {...sessionBody(), 'user': _user()}),
      );
      await launchApp(tester);
      await login(tester);
      expect(field('Prénom'), findsNothing);
      await fillDossier(tester);
      await tapText(tester, 'Envoyer mon dossier');
      expect(server.calls('PATCH', '/v1/me'), isEmpty);
    });

    testWidgets('photo prise : appareil photo demandé', (tester) async {
      await launchApp(tester);
      await login(tester);
      await tapText(tester, "Pièce d'identité");
      await tester.tap(find.text('Prendre une photo'));
      await tester.pumpAndSettle();
      expect(picker.requests.single.$1, PhotoSource.camera);
      expect(find.text('Ajouté'), findsOneWidget);
    });

    testWidgets('échec d\'un document puis nouvel essai : rien en double', (
      tester,
    ) async {
      var failures = 1;
      server.on('POST', '/v1/driver/application/documents', (request) {
        final body = request.body! as Map<String, dynamic>;
        if (body['kind'] == 'driving_license' && failures-- > 0) {
          return FakeResponse.networkError();
        }
        documentsSent.add(body);
        return FakeResponse.json(201, driverBody());
      });
      await launchApp(tester);
      await login(tester);
      await fillDossier(tester);
      await tapText(tester, 'Envoyer mon dossier');
      expect(find.textContaining('Pas de connexion internet'), findsOneWidget);

      await tapText(tester, 'Envoyer mon dossier');
      expect(
        find.text('Votre dossier est en cours de vérification'),
        findsOneWidget,
      );
      expect(server.calls('POST', '/v1/uploads'), hasLength(3));
      expect(server.calls('PATCH', '/v1/me'), hasLength(1));
      expect(documentsSent.map((d) => d['kind']), [
        'id_card',
        'driving_license',
        'vehicle_registration',
      ]);
    });

    testWidgets('double appui : une seule candidature', (tester) async {
      final reply = Completer<FakeResponse>();
      server.on('PUT', '/v1/driver/application', (_) => reply.future);
      await launchApp(tester);
      await login(tester);
      await fillDossier(tester);
      final submit = find.text('Envoyer mon dossier');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      reply.complete(FakeResponse.json(200, driverBody(documents: [])));
      await tester.pumpAndSettle();
      expect(server.calls('PUT', '/v1/driver/application'), hasLength(1));
      expect(documentsSent, hasLength(3));
    });

    testWidgets('immatriculation invalide : message, rien n\'est envoyé', (
      tester,
    ) async {
      await launchApp(tester);
      await login(tester);
      await fillDossier(tester);
      await tester.enterText(field("Numéro d'immatriculation"), 'T');
      await tapText(tester, 'Envoyer mon dossier');
      expect(
        find.text('Immatriculation de 2 à 20 caractères.'),
        findsOneWidget,
      );
      expect(server.calls('PATCH', '/v1/me'), isEmpty);
      expect(server.calls('POST', '/v1/uploads'), isEmpty);
    });

    testWidgets('numéro déjà utilisé : message, rien d\'autre envoyé', (
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
      await launchApp(tester);
      await login(tester);
      await fillDossier(tester);
      await tapText(tester, 'Envoyer mon dossier');
      expect(
        find.text('Ce numéro est déjà utilisé par un autre compte.'),
        findsOneWidget,
      );
      expect(server.calls('POST', '/v1/uploads'), isEmpty);
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
      await tester.ensureVisible(find.text('Envoyer mon dossier'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('relance avec un dossier', () {
    Future<void> withDossier({
      String review = 'pending_review',
      String? status,
    }) async {
      await signedInWith(_user());
      server.on(
        'GET',
        '/v1/driver/me',
        (_) => FakeResponse.json(
          200,
          driverBody(review: review, status: status ?? review),
        ),
      );
    }

    testWidgets('en vérification : récapitulatif, puis validé', (tester) async {
      await withDossier();
      await launchApp(tester);
      expect(
        find.text('Votre dossier est en cours de vérification'),
        findsOneWidget,
      );
      await tapText(tester, 'Voir mon dossier');
      expect(find.text('TG 4521 AB'), findsOneWidget);
      expect(
        find.text("Pièce d'identité, Permis de conduire, Carte grise"),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();

      server.on(
        'GET',
        '/v1/driver/me',
        (_) => FakeResponse.json(
          200,
          driverBody(review: 'approved', status: 'offline'),
        ),
      );
      await tester.fling(find.text('Compte créé'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Vous êtes livreur ivia'), findsOneWidget);
    });

    testWidgets('refusé : motif, correction préremplie, renvoi', (
      tester,
    ) async {
      await withDossier(review: 'rejected');
      await launchApp(tester);
      expect(find.text("Votre dossier n'a pas été validé"), findsOneWidget);
      expect(find.text('Motif : Carte grise illisible.'), findsOneWidget);

      await tapText(tester, 'Corriger mon dossier');
      expect(find.text('Corrigez votre dossier'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(field("Numéro d'immatriculation"))
            .controller!
            .text,
        'TG 4521 AB',
      );
      expect(find.text('Envoyé'), findsNWidgets(3));
      // Nouvelle photo de la carte grise seulement.
      await tapText(tester, 'Carte grise');
      await tester.tap(find.text('Choisir une photo'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Envoyer mon dossier');
      expect(documentsSent.map((d) => d['kind']), ['vehicle_registration']);
      expect(
        find.text('Votre dossier est en cours de vérification'),
        findsOneWidget,
      );
    });

    testWidgets('suspendu : motif, pas de correction', (tester) async {
      await withDossier(review: 'approved', status: 'suspended');
      await launchApp(tester);
      expect(find.text('Votre compte livreur est suspendu'), findsOneWidget);
      expect(find.text('Motif : Plaintes répétées.'), findsOneWidget);
      expect(find.text('Corriger mon dossier'), findsNothing);
    });

    testWidgets('serveur injoignable : hors ligne, puis « Réessayer »', (
      tester,
    ) async {
      await withDossier();
      server.on('GET', '/v1/driver/me', (_) => FakeResponse.networkError());
      await launchApp(tester);
      expect(find.text('Pas de connexion'), findsOneWidget);
      server.on(
        'GET',
        '/v1/driver/me',
        (_) => FakeResponse.json(200, driverBody()),
      );
      await tapText(tester, 'Réessayer');
      expect(
        find.text('Votre dossier est en cours de vérification'),
        findsOneWidget,
      );
    });
  });
}
