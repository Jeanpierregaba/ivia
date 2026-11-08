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
import 'package:ivia_app_core/testing.dart';
import 'package:ivia_driver/app/identity.dart';
import 'package:ivia_driver/common/ui.dart';
import 'package:ivia_driver/features/mission/navigation.dart';
import 'package:ivia_driver/features/onboarding/onboarding_screen.dart';
import 'package:ivia_driver/main.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Appareil photo refusé (permission) ; la galerie fonctionne.
class _ThrowingPicker implements PhotoPicker {
  _ThrowingPicker(this.gallery);

  final PhotoPicker gallery;

  @override
  Future<Uint8List?> pick({
    PhotoSource source = PhotoSource.gallery,
    int maxSide = 1024,
  }) {
    if (source == PhotoSource.camera) {
      throw PlatformException(code: 'camera_access_denied');
    }
    return gallery.pick(source: source, maxSide: maxSide);
  }
}

Map<String, dynamic> _user({bool complete = true}) =>
    userBody(complete: complete);

void main() {
  late FakeApiServer server;
  late _FakePicker picker;
  late FakeLocationService location;
  late List<Uri> launched;
  late List<Map<String, dynamic>> documentsSent;

  /// Dossier côté serveur : comme le backend, une pièce envoyée s'ajoute aux
  /// précédentes, sans les remplacer.
  late List<String> serverDocuments;
  late String serverVehicle;
  late String serverReview;
  late bool serverPayout;

  /// Dossier du serveur, tel que les routes du dossier partenaire le rendent.
  Map<String, dynamic> serverDossier({String? status}) => driverBody(
    review: serverReview,
    status: status ?? serverReview,
    vehicleType: serverVehicle,
    documents: serverDocuments,
    payout: serverPayout,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    picker = _FakePicker();
    location = FakeLocationService();
    launched = [];
    documentsSent = [];
    serverDocuments = [];
    serverVehicle = 'motorbike';
    serverReview = 'draft';
    serverPayout = false;
    var upload = 0;
    server = FakeApiServer()
      ..on(
        'POST',
        '/v1/auth/phone/code',
        (_) => FakeResponse.json(202, phoneOtpBody),
      )
      ..on(
        'POST',
        '/v1/auth/phone/verify',
        (_) => FakeResponse.json(200, {
          'status': 'signed_in',
          'session': {...phoneSessionBody(), 'user': _user(complete: false)},
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
        'GET',
        '/v1/driver/options',
        (_) => FakeResponse.json(200, driverOptionsBody()),
      )
      ..on('PUT', '/v1/driver/activities/delivery', (request) {
        serverVehicle =
            (request.body! as Map<String, dynamic>)['vehicle_type'] as String;
        return FakeResponse.json(200, serverDossier());
      })
      ..on('POST', '/v1/driver/application/documents', (request) {
        final body = request.body! as Map<String, dynamic>;
        documentsSent.add(body);
        serverDocuments = [...serverDocuments, body['kind'] as String];
        return FakeResponse.json(201, serverDossier());
      })
      ..on('PUT', '/v1/driver/payout', (_) {
        serverPayout = true;
        return FakeResponse.json(200, serverDossier());
      })
      ..on('POST', '/v1/driver/activities/delivery/submit', (_) {
        serverReview = 'pending_review';
        return FakeResponse.json(200, serverDossier());
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
    PhotoPicker? photoPicker,
  }) async {
    final store = await OnboardingStore.open();
    final locationPrompt = await LocationPromptStore.open(location);
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
          photoPickerProvider.overrideWithValue(photoPicker ?? picker),
          // Jamais le GPS du poste de test.
          locationServiceProvider.overrideWithValue(location),
          locationPromptStoreProvider.overrideWithValue(locationPrompt),
          linkLauncherProvider.overrideWithValue((uri) async {
            launched.add(uri);
            return true;
          }),
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
    await tester.enterText(find.byType(TextField), '90 12 34 56');
    await tapText(tester, 'Recevoir le code');
    await tester.enterText(find.byType(TextField), '481902');
    await tester.pumpAndSettle();
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
  /// Pièces exigées pour une moto ou une voiture (serveur).
  const motorDocuments = [
    "Pièce d'identité",
    'Permis de conduire',
    'Carte grise',
    'Assurance du véhicule',
  ];

  Future<void> addDocuments(
    WidgetTester tester, [
    List<String> labels = motorDocuments,
  ]) async {
    for (final label in labels) {
      await tapText(tester, label);
      await tester.tap(find.text('Choisir une photo'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> chooseZone(WidgetTester tester, [String zone = 'Tokoin']) async {
    await tapText(tester, 'Choisissez votre quartier');
    await tester.tap(find.text(zone).last);
    await tester.pumpAndSettle();
  }

  Future<void> fillPayout(WidgetTester tester) async {
    await tester.ensureVisible(field('Numéro Mobile Money'));
    await tester.enterText(field('Numéro Mobile Money'), '90556677');
    await tester.enterText(field('Titulaire du compte'), 'Kossi Adjo');
    await tester.pump();
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
    await chooseZone(tester);
    await addDocuments(tester);
    await fillPayout(tester);
  }

  /// Bouton « Envoyer mon dossier » actif ?
  bool canSubmit(WidgetTester tester) =>
      tester
          .widget<DButton>(find.widgetWithText(DButton, 'Envoyer mon dossier'))
          .onTap !=
      null;

  group('lancement et présentation', () {
    testWidgets('localisation (030) : écran après le splash, « Plus tard »', (
      tester,
    ) async {
      location.state = LocationAccess.askable;
      await launchApp(tester);
      expect(find.text('Driver'), findsWidgets);
      expect(
        find.text('Des missions près de vous', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(OnboardingScreen), findsNothing);
      await tapText(tester, 'Plus tard');
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(location.requests, 0);
    });

    testWidgets('thème Cobalt et splash avec tuile', (tester) async {
      await launchApp(
        tester,
        minSplash: const Duration(milliseconds: 800),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Driver'), findsOneWidget);
      expect(find.text('Livrez près de chez vous.'), findsOneWidget);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.title, 'Ivia Driver');
      expect(app.theme?.colorScheme.primary, IviaColors.cobaltBlue);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Des missions près de vous.'), findsOneWidget);
    });

    testWidgets('présentation, puis « Espace livreur »', (tester) async {
      await launchApp(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Driver'), findsOneWidget);
      await tapText(tester, 'Passer');
      expect(find.text('Espace livreur'), findsOneWidget);
      expect(
        find.textContaining('validation de votre dossier'),
        findsOneWidget,
      );
    });

    testWidgets('présentation : pages, retour, « Commencer » (D01 à D03)', (
      tester,
    ) async {
      await launchApp(tester);
      expect(
        find.text('Des missions près de vous.', findRichText: true),
        findsOneWidget,
      );
      await tapText(tester, 'Suivant');
      expect(
        find.text('Guidé à chaque étape.', findRichText: true),
        findsOneWidget,
      );
      // Retour : page précédente, logo et « Driver » revenus.
      await tester.tap(find.bySemanticsLabel('Retour'));
      await tester.pumpAndSettle();
      expect(find.text('Driver'), findsOneWidget);
      await tapText(tester, 'Suivant');
      await tapText(tester, 'Suivant');
      expect(
        find.text('Le code du client valide la livraison.', findRichText: true),
        findsOneWidget,
      );
      // Dernière page : plus de « Passer ».
      expect(find.text('Passer').hitTestable(), findsNothing);
      await tapText(tester, 'Commencer');
      expect(find.text('Espace livreur'), findsOneWidget);
    });

    testWidgets('présentation : police à 200 % sur 320 dp, sans débordement', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await launchApp(tester);
      for (var i = 0; i < 3; i++) {
        expect(tester.takeException(), isNull);
        if (i < 2) await tapText(tester, 'Suivant');
      }
      expect(find.text('Commencer'), findsOneWidget);
    });

    testWidgets('titres : aucun mot coupé sur 320 dp, police agrandie', (
      tester,
    ) async {
      final loader = FontLoader(
        'packages/ivia_ui/Parkinsans',
      )..addFont(rootBundle.load('packages/ivia_ui/fonts/Parkinsans-Bold.ttf'));
      await loader.load();
      const width = 320 - 2 * D.gutter;
      final style = DText.hero;
      for (final slide in onboardingSlides) {
        for (final word in slide.title.split(' ')) {
          final painter = TextPainter(
            text: TextSpan(text: word, style: style),
            textDirection: TextDirection.ltr,
            textScaler: const TextScaler.linear(
              OnboardingScreen.titleMaxTextScale,
            ),
          )..layout();
          expect(painter.width, lessThanOrEqualTo(width), reason: word);
          painter.dispose();
        }
      }
    });
  });

  group('connexion (D04, D05)', () {
    setUp(onboardingSeen);

    testWidgets('par numéro, sans e-mail ; « Modifier » dans la phrase', (
      tester,
    ) async {
      await launchApp(tester);
      expect(find.text('Espace livreur'), findsOneWidget);
      expect(find.text('Driver'), findsOneWidget);
      expect(find.textContaining('e-mail'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '90 12 34 56');
      await tapText(tester, 'Recevoir le code');
      expect(find.text('Vérifiez WhatsApp'), findsOneWidget);
      // Numéro jamais coupé en fin de ligne.
      expect(
        find.textContaining(
          '+228\u00A090\u00A012\u00A034\u00A056',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Même compte sur toutes les apps ivia'),
        findsOneWidget,
      );
      await tester.tapOnText(find.textRange.ofSubstring('Modifier'));
      await tester.pumpAndSettle();
      expect(find.text('Espace livreur'), findsOneWidget);
    });

    testWidgets('police à 200 % sur 320 dp : connexion et code tiennent', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await launchApp(tester);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), '90 12 34 56');
      await tapText(tester, 'Recevoir le code');
      expect(tester.takeException(), isNull);
      expect(find.text('Vérifiez WhatsApp'), findsOneWidget);
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
      expect(canSubmit(tester), isFalse);

      await fillDossier(tester);
      expect(canSubmit(tester), isTrue);
      await tapText(tester, 'Voiture');
      await tapText(tester, 'Envoyer mon dossier');

      expect(server.calls('PATCH', '/v1/me').single.body, {
        'first_name': 'Kossi',
        'last_name': 'Adjo',
        'phone': '+22890123456',
        'accept_privacy_policy': true,
      });
      expect(
        server.calls('PUT', '/v1/driver/activities/delivery').single.body,
        {
          'vehicle_type': 'car',
          'plate': 'TG 4521 AB',
          'brand': '',
          'model': '',
          'work_zone_id': workZoneTokoin,
        },
      );
      expect(documentsSent.map((d) => d['kind']), [
        'id_card',
        'driving_license',
        'vehicle_registration',
        'vehicle_insurance',
      ]);
      expect(server.calls('PUT', '/v1/driver/payout').single.body, {
        'operator': 'flooz',
        'phone': '+22890556677',
        'holder': 'Kossi Adjo',
      });
      // Profil, fichiers, activité, pièces, compte, puis envoi.
      final paths = server.requests
          .map((r) => '${r.method} ${r.path}')
          .toList();
      final order = [
        paths.indexOf('PATCH /v1/me'),
        paths.lastIndexOf('POST /v1/uploads'),
        paths.indexOf('PUT /v1/driver/activities/delivery'),
        paths.lastIndexOf('POST /v1/driver/application/documents'),
        paths.indexOf('PUT /v1/driver/payout'),
        paths.indexOf('POST /v1/driver/activities/delivery/submit'),
      ];
      expect(order, [...order]..sort());
      expect(order.contains(-1), isFalse);
      // Aucun jeton vers le stockage ; documents lisibles (2048 px).
      final stored = server.requests.where((r) => r.host == 'prive.test');
      expect(stored, hasLength(4));
      for (final put in stored) {
        expect(put.headers['authorization'], isNull);
      }
      expect(picker.requests.map((r) => r.$2).toSet(), {2048});

      expect(
        find.text('Votre dossier est en cours de vérification'),
        findsOneWidget,
      );
      expect(find.text('Voiture · 4 documents'), findsOneWidget);
    });

    testWidgets('vélo : sans plaque, pièce d\'identité seule', (tester) async {
      await launchApp(tester);
      await login(tester);
      await tapText(tester, 'Vélo');
      expect(field("Numéro d'immatriculation"), findsNothing);
      expect(find.text('Permis de conduire'), findsNothing);
      if (field('Prénom').evaluate().isNotEmpty) {
        await tester.enterText(field('Prénom'), 'Kossi');
        await tester.enterText(field('Nom'), 'Adjo');
        await tester.enterText(field('Téléphone'), '90123456');
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
      }
      await chooseZone(tester, 'Bè');
      await addDocuments(tester, ["Pièce d'identité"]);
      await fillPayout(tester);
      await tapText(tester, 'Envoyer mon dossier');
      final body =
          server.calls('PUT', '/v1/driver/activities/delivery').single.body
              as Map;
      expect(body['vehicle_type'], 'bicycle');
      expect(body['plate'], '');
      expect(body['work_zone_id'], '5a1b2c3d-0000-4000-8000-00000000a002');
      expect(documentsSent.map((d) => d['kind']), ['id_card']);
    });

    testWidgets('sans zone ou sans compte : envoi impossible', (tester) async {
      await launchApp(tester);
      await login(tester);
      if (field('Prénom').evaluate().isNotEmpty) {
        await tester.enterText(field('Prénom'), 'Kossi');
        await tester.enterText(field('Nom'), 'Adjo');
        await tester.enterText(field('Téléphone'), '90123456');
      }
      await tester.enterText(field("Numéro d'immatriculation"), 'TG 4521 AB');
      await addDocuments(tester);
      await fillPayout(tester);
      expect(canSubmit(tester), isFalse, reason: 'zone manquante');
      await chooseZone(tester);
      expect(canSubmit(tester), isTrue);
      await tester.enterText(field('Titulaire du compte'), '');
      await tester.pump();
      expect(canSubmit(tester), isFalse, reason: 'titulaire manquant');
    });

    testWidgets('compte refusé par le serveur : sous son champ', (
      tester,
    ) async {
      server.on(
        'PUT',
        '/v1/driver/payout',
        (_) => FakeResponse.error(
          400,
          'validation_failed',
          'Données invalides.',
          fields: {'phone': 'Numéro attendu : +228 suivi de 8 chiffres.'},
        ),
      );
      await launchApp(tester);
      await login(tester);
      await fillDossier(tester);
      await tapText(tester, 'Envoyer mon dossier');
      expect(
        find.text('Numéro attendu : +228 suivi de 8 chiffres.'),
        findsOneWidget,
      );
      // Pas sous le téléphone du profil, et rien d'envoyé au back-office.
      expect(
        server.calls('POST', '/v1/driver/activities/delivery/submit'),
        isEmpty,
      );
    });

    testWidgets('profil complet : aucun champ de profil', (tester) async {
      server.on(
        'POST',
        '/v1/auth/phone/verify',
        (_) => FakeResponse.json(200, {
          'status': 'signed_in',
          'session': {...phoneSessionBody(), 'user': _user()},
        }),
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
        serverDocuments = [...serverDocuments, body['kind'] as String];
        return FakeResponse.json(201, serverDossier());
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
      expect(server.calls('POST', '/v1/uploads'), hasLength(4));
      expect(server.calls('PATCH', '/v1/me'), hasLength(1));
      expect(documentsSent.map((d) => d['kind']), [
        'id_card',
        'driving_license',
        'vehicle_registration',
        'vehicle_insurance',
      ]);
    });

    testWidgets('fichier refusé à la transmission : renvoyé au nouvel essai', (
      tester,
    ) async {
      var failures = 1;
      server.on('POST', '/v1/driver/application/documents', (request) {
        final body = request.body! as Map<String, dynamic>;
        if (body['kind'] == 'driving_license' && failures-- > 0) {
          return FakeResponse.error(
            400,
            'validation_failed',
            'Certaines informations sont invalides.',
            fields: {'object_key': "Le fichier n'a pas été reçu. Renvoyez-le."},
          );
        }
        documentsSent.add(body);
        serverDocuments = [...serverDocuments, body['kind'] as String];
        return FakeResponse.json(201, serverDossier());
      });
      await launchApp(tester);
      await login(tester);
      await fillDossier(tester);
      await tapText(tester, 'Envoyer mon dossier');
      expect(
        find.text("Le fichier n'a pas été reçu. Renvoyez-le."),
        findsOneWidget,
      );

      await tapText(tester, 'Envoyer mon dossier');
      expect(
        find.text('Votre dossier est en cours de vérification'),
        findsOneWidget,
      );
      // Seul le permis refusé est renvoyé, avec une nouvelle clé.
      expect(server.calls('POST', '/v1/uploads'), hasLength(5));
      expect(documentsSent.map((d) => d['kind']), [
        'id_card',
        'vehicle_registration',
        'vehicle_insurance',
        'driving_license',
      ]);
      expect(documentsSent.last['object_key'], 'driver_document/u1/doc5.jpg');
    });

    testWidgets('double appui : une seule candidature', (tester) async {
      final reply = Completer<FakeResponse>();
      server.on('PUT', '/v1/driver/activities/delivery', (_) => reply.future);
      await launchApp(tester);
      await login(tester);
      await fillDossier(tester);
      final submit = find.text('Envoyer mon dossier');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();
      await tester.tap(find.byType(DButton), warnIfMissed: false);
      reply.complete(FakeResponse.json(200, serverDossier()));
      await tester.pumpAndSettle();
      expect(
        server.calls('PUT', '/v1/driver/activities/delivery'),
        hasLength(1),
      );
      expect(documentsSent, hasLength(4));
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

    testWidgets('photo trop lourde : refusée, ligne à « Ajouter »', (
      tester,
    ) async {
      picker.next = Uint8List(5 * 1024 * 1024 + 1);
      await launchApp(tester);
      await login(tester);
      await tapText(tester, "Pièce d'identité");
      await tester.tap(find.text('Choisir une photo'));
      await tester.pumpAndSettle();
      expect(find.text('Photo trop lourde (5 Mo au plus).'), findsOneWidget);
      expect(find.text('Ajouté'), findsNothing);
    });

    testWidgets('appareil photo refusé : message, la galerie reste possible', (
      tester,
    ) async {
      final failing = _ThrowingPicker(picker);
      await launchApp(tester, photoPicker: failing);
      await login(tester);
      await tapText(tester, "Pièce d'identité");
      await tester.tap(find.text('Prendre une photo'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Photo impossible à utiliser'),
        findsOneWidget,
      );
      await tapText(tester, "Pièce d'identité");
      await tester.tap(find.text('Choisir une photo'));
      await tester.pumpAndSettle();
      expect(find.text('Ajouté'), findsOneWidget);
    });

    testWidgets('immatriculation refusée par le serveur : sous le champ', (
      tester,
    ) async {
      server.on(
        'PUT',
        '/v1/driver/activities/delivery',
        (_) => FakeResponse.error(
          400,
          'validation_failed',
          'Données invalides.',
          fields: {'plate': 'Immatriculation invalide.'},
        ),
      );
      await launchApp(tester);
      await login(tester);
      await fillDossier(tester);
      await tapText(tester, 'Envoyer mon dossier');
      expect(find.text('Immatriculation invalide.'), findsOneWidget);
    });

    testWidgets('retour depuis le dossier : déconnexion', (tester) async {
      await launchApp(tester);
      await login(tester);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(server.calls('POST', '/v1/auth/logout'), hasLength(1));
      expect(find.text('Espace livreur'), findsOneWidget);
    });

    testWidgets('ligne de document : bouton activable au lecteur d\'écran', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await launchApp(tester);
      await login(tester);
      expect(
        tester.getSemantics(find.bySemanticsLabel("Pièce d'identité, Ajouter")),
        isSemantics(
          label: "Pièce d'identité, Ajouter",
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      semantics.dispose();
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
      List<String> documents = const [
        'id_card',
        'driving_license',
        'vehicle_registration',
        'vehicle_insurance',
      ],
    }) async {
      await signedInWith(_user());
      serverDocuments = documents;
      serverReview = review;
      serverPayout = true;
      server.on(
        'GET',
        '/v1/driver/me',
        (_) => FakeResponse.json(200, serverDossier(status: status)),
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
        find.text(
          "Pièce d'identité, Permis de conduire, Carte grise, "
          'Assurance du véhicule',
        ),
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
      // Validé : l'app de travail, barre du bas et accueil hors ligne.
      expect(find.byKey(const Key('bottom-nav')), findsOneWidget);
      expect(find.text('Vous êtes hors ligne'), findsOneWidget);
    });

    /// Livreur validé, hors ligne ; [delivered] : missions livrées (heure).
    void approvedHome({List<DateTime> delivered = const []}) {
      server
        ..on(
          'GET',
          '/v1/driver/missions/current',
          (_) => FakeResponse.json(200, {'mission': null}),
        )
        ..on(
          'GET',
          '/v1/driver/pharmacy-missions/current',
          (_) => FakeResponse.json(200, {'mission': null}),
        )
        ..on(
          'GET',
          '/v1/driver/missions',
          (_) => FakeResponse.json(200, {
            'items': [
              for (final (i, at) in delivered.indexed)
                {
                  'id': 'm$i',
                  'order_reference': '#10$i',
                  'status': 'delivered',
                  'fee_xof': 1200,
                  'items_count': 1,
                  'parcel_size': 'small',
                  'shop': {'name': 'Chez Afi'},
                  'customer': null,
                  'assigned_at': at.toIso8601String(),
                  'delivered_at': at.toIso8601String(),
                },
            ],
            'next_offset': null,
          }),
        )
        ..on(
          'GET',
          '/v1/driver/pharmacy-missions',
          (_) => FakeResponse.json(200, {'items': [], 'next_offset': null}),
        );
    }

    testWidgets('accueil hors ligne (D08) : nom, jour calculé, glissière', (
      tester,
    ) async {
      await withDossier(review: 'approved', status: 'offline');
      final now = DateTime.now().toUtc();
      approvedHome(
        delivered: [now, now, now.subtract(const Duration(days: 40))],
      );
      await launchApp(tester);
      expect(find.text('Awa Mensah'), findsOneWidget);
      expect(
        find.text('Bonjour').evaluate().length +
            find.text('Bonsoir').evaluate().length,
        1,
      );
      // Deux livraisons aujourd'hui (la troisième est ancienne) : 2 400 F.
      expect(find.text('2'), findsOneWidget);
      expect(find.text(formatXof(2400)), findsOneWidget);
      expect(find.text('Vous êtes hors ligne'), findsOneWidget);
      // Glissement incomplet : rien ne part.
      await tester.drag(
        find.byKey(const Key('slide-knob')),
        const Offset(80, 0),
      );
      await tester.pumpAndSettle();
      expect(server.calls('PUT', '/v1/driver/availability'), isEmpty);
      // Masqués : objectif, km, temps en ligne, demande par quartier.
      expect(find.textContaining('km'), findsNothing);
      expect(find.text('Demande autour de vous'), findsNothing);
    });

    testWidgets('barre du bas : Missions, Gains, Profil', (tester) async {
      await withDossier(review: 'approved', status: 'offline');
      approvedHome();
      await launchApp(tester);
      await tester.tap(find.bySemanticsLabel('Gains'));
      await tester.pumpAndSettle();
      expect(find.text('CETTE SEMAINE'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Accueil'));
      await tester.pumpAndSettle();
      expect(find.text('Vous êtes hors ligne'), findsOneWidget);
    });

    testWidgets('accueil hors ligne : police à 200 % sur 320 dp', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await withDossier(review: 'approved', status: 'offline');
      approvedHome(delivered: [DateTime.now().toUtc()]);
      await launchApp(tester);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Glisser pour passer en ligne'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });

    for (final allow in [false, true]) {
      testWidgets('en ligne sans autorisation (030) : écran, puis '
          '${allow ? 'position envoyée' : 'en ligne sans position'}', (
        tester,
      ) async {
        await withDossier(review: 'approved', status: 'offline');
        SharedPreferences.setMockInitialValues({
          'onboarding_seen': true,
          'location_prompt_done': true,
        });
        location.state = LocationAccess.askable;
        server
          ..on(
            'GET',
            '/v1/driver/missions/current',
            (_) => FakeResponse.json(200, {'mission': null}),
          )
          ..on(
            'GET',
            '/v1/driver/pharmacy-missions/current',
            (_) => FakeResponse.json(200, {'mission': null}),
          )
          ..on(
            'GET',
            '/v1/driver/offers/current',
            (_) => FakeResponse.json(200, {'offer': null}),
          )
          ..on(
            'GET',
            '/v1/driver/pharmacy-offers/current',
            (_) => FakeResponse.json(200, {'offer': null}),
          )
          ..on(
            'PUT',
            '/v1/driver/availability',
            (_) => FakeResponse.json(204, null),
          )
          ..on(
            'POST',
            '/v1/driver/location',
            (_) => FakeResponse.json(204, null),
          );
        await launchApp(tester);
        // Glissière amenée au bout : passage en ligne (D08).
        await tester.drag(
          find.byKey(const Key('slide-knob')),
          const Offset(2000, 0),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Des missions près de vous', findRichText: true),
          findsOneWidget,
        );
        // En ligne : animation continue, pas de pumpAndSettle.
        final choice = find.text(
          allow ? 'Autoriser la localisation' : 'Plus tard',
        );
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(location.requests, allow ? 1 : 0);
        expect(server.calls('PUT', '/v1/driver/availability'), hasLength(1));
        // Position lue au passage en ligne ; elle part par la WebSocket des
        // positions (repli HTTP). Sans autorisation, rien n'est envoyé.
        expect(location.calls, greaterThan(0));
        if (!allow) {
          expect(server.calls('POST', '/v1/driver/location'), isEmpty);
        }
        // Hors ligne : plus d'envoi périodique en attente.
        await tester.tap(find.text('Pause'));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
      });
    }

    /// Réponses du passage en ligne : propositions vides, position.
    void goOnlineServer() => server
      ..on(
        'GET',
        '/v1/driver/offers/current',
        (_) => FakeResponse.json(200, {'offer': null}),
      )
      ..on(
        'GET',
        '/v1/driver/pharmacy-offers/current',
        (_) => FakeResponse.json(200, {'offer': null}),
      )
      ..on(
        'PUT',
        '/v1/driver/availability',
        (_) => FakeResponse.json(204, null),
      )
      ..on('POST', '/v1/driver/location', (_) => FakeResponse.json(204, null));

    testWidgets('accueil en ligne : police à 200 % sur 320 dp', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await withDossier(review: 'approved', status: 'offline');
      approvedHome(delivered: [DateTime.now().toUtc()]);
      goOnlineServer();
      await launchApp(tester);
      await tester.scrollUntilVisible(
        find.text('Glisser pour passer en ligne'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('slide-knob')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('slide-knob')),
        const Offset(2000, 0),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Pause'), findsOneWidget);
      final error = tester.takeException();
      expect(error, isNull, reason: '$error');
      await tester.tap(find.text('Pause'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    });

    /// En ligne avec [offer] proposée (jusqu'à acceptation ou refus).
    Future<void> onlineWithOffer(
      WidgetTester tester,
      Map<String, dynamic> offer, {
      FakeResponse Function()? accept,
    }) async {
      await withDossier(review: 'approved', status: 'offline');
      approvedHome();
      goOnlineServer();
      Map<String, dynamic>? current = offer;
      final id = offer['id'];
      server
        ..on(
          'GET',
          '/v1/driver/offers/current',
          (_) => FakeResponse.json(200, {'offer': current}),
        )
        ..on('POST', '/v1/driver/offers/$id/accept', (_) {
          final response = accept?.call() ?? FakeResponse.json(204, null);
          if (response.status == 204) current = null;
          return response;
        })
        ..on('POST', '/v1/driver/offers/$id/decline', (_) {
          current = null;
          return FakeResponse.json(204, null);
        });
      await launchApp(tester);
      await tester.drag(
        find.byKey(const Key('slide-knob')),
        const Offset(2000, 0),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    Future<void> wait(WidgetTester tester, {int ticks = 5}) async {
      for (var i = 0; i < ticks; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('proposition (D10) : gain, trajet, glisser pour accepter', (
      tester,
    ) async {
      await onlineWithOffer(tester, driverOfferBody());
      expect(find.text('NOUVELLE MISSION'), findsOneWidget);
      expect(find.text(formatXof(1200)), findsOneWidget);
      expect(find.text('Gain indicatif · payé à la livraison'), findsOneWidget);
      // 800 m + 3,4 km ; moto : ≈ 14 min (4 200 m × 1,3 à 22 km/h).
      expect(find.text('4,2 km'), findsOneWidget);
      expect(find.text('≈ 14 min'), findsOneWidget);
      expect(find.text('Colis moyen'), findsOneWidget);
      expect(find.text('Retrait · Chez Afi'), findsOneWidget);
      expect(find.text('Rue 248, Tokoin · à 800 m'), findsOneWidget);
      expect(find.text('Livraison · Bè Kpota'), findsOneWidget);
      expect(find.text('3,4 km après le retrait'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'secondes pour accepter')),
        findsOneWidget,
      );
      // Glissement incomplet : rien ne part.
      await tester.drag(
        find.byKey(const Key('slide-knob')),
        const Offset(80, 0),
      );
      await wait(tester);
      expect(server.calls('POST', '/v1/driver/offers/offer-1/accept'), isEmpty);
      await tester.drag(
        find.byKey(const Key('slide-knob')),
        const Offset(2000, 0),
      );
      await wait(tester);
      expect(
        server.calls('POST', '/v1/driver/offers/offer-1/accept'),
        hasLength(1),
      );
    });

    testWidgets('proposition prise par un autre : message, recherche', (
      tester,
    ) async {
      await onlineWithOffer(
        tester,
        driverOfferBody(),
        accept: () => FakeResponse.json(409, {
          'error': {
            'code': 'offer_expired',
            'message': 'Cette mission a déjà été attribuée.',
          },
        }),
      );
      await tester.drag(
        find.byKey(const Key('slide-knob')),
        const Offset(2000, 0),
      );
      await wait(tester);
      expect(find.text('Cette mission a déjà été attribuée.'), findsOneWidget);
      expect(find.text('Recherche de missions…'), findsOneWidget);
      // Relue par le serveur, elle ne revient pas.
      await wait(tester, ticks: 15);
      expect(find.text('NOUVELLE MISSION'), findsNothing);
    });

    testWidgets('compte à rebours fini : proposition retirée', (tester) async {
      await onlineWithOffer(
        tester,
        driverOfferBody(expiresIn: const Duration(seconds: 3)),
      );
      expect(find.text('NOUVELLE MISSION'), findsOneWidget);
      await wait(tester, ticks: 12);
      expect(find.text('NOUVELLE MISSION'), findsNothing);
      expect(
        find.text('Proposition expirée. La recherche continue.'),
        findsOneWidget,
      );
    });

    testWidgets('Refuser : appel au serveur, retour à la recherche', (
      tester,
    ) async {
      await onlineWithOffer(tester, driverOfferBody());
      await tester.ensureVisible(find.text('Refuser'));
      await tester.pump();
      await tester.tap(find.text('Refuser'));
      await wait(tester);
      expect(
        server.calls('POST', '/v1/driver/offers/offer-1/decline'),
        hasLength(1),
      );
      expect(find.text('Recherche de missions…'), findsOneWidget);
    });

    testWidgets('proposition : police à 220 % sur 320 dp', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await onlineWithOffer(tester, driverOfferBody());
      tester.platformDispatcher.textScaleFactorTestValue = 2.2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await wait(tester, ticks: 2);
      expect(find.text('NOUVELLE MISSION'), findsOneWidget);
      final error = tester.takeException();
      expect(error, isNull, reason: '$error');
      await tester.scrollUntilVisible(
        find.text('Refuser'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.takeException(), isNull);
    });

    /// Livreur validé avec [mission] en cours ; itinéraire du serveur :
    /// [routeM] mètres en [routeS] secondes.
    Future<void> withMission(
      WidgetTester tester,
      Map<String, dynamic> mission, {
      bool pharmacy = false,
      int routeM = 800,
      int routeS = 240,
    }) async {
      await withDossier(review: 'approved', status: 'offline');
      approvedHome();
      server
        ..on(
          'GET',
          pharmacy
              ? '/v1/driver/pharmacy-missions/current'
              : '/v1/driver/missions/current',
          (_) => FakeResponse.json(200, {'mission': mission}),
        )
        ..on(
          'POST',
          '/v1/geo/route',
          (_) => FakeResponse.json(200, {
            'distance_m': routeM,
            'duration_s': routeS,
            'polyline': '',
            'approximate': false,
          }),
        );
      await launchApp(tester, settle: false);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('vers le retrait (D11) : boutique, Maps, appel, arrivée', (
      tester,
    ) async {
      await withMission(tester, driverMissionBody());
      server.on(
        'POST',
        '/v1/driver/missions/mission-1/arrived-at-shop',
        (_) => FakeResponse.json(204, null),
      );
      expect(find.text('ÉTAPE 1 SUR 2 · RETRAIT'), findsOneWidget);
      expect(find.text('Chez Afi'), findsOneWidget);
      expect(find.text('#1042'), findsOneWidget);
      expect(find.text('Rue 248, Tokoin'), findsOneWidget);
      expect(find.text('3 articles'), findsOneWidget);
      expect(find.text('Colis moyen'), findsOneWidget);
      expect(find.text('Payée'), findsOneWidget);
      // Bandeau : itinéraire du serveur (800 m, 4 min).
      expect(find.text('Vers Chez Afi'), findsOneWidget);
      expect(find.text('800 m'), findsOneWidget);
      expect(find.text('4 min'), findsOneWidget);
      // Messagerie masquée (pas de serveur).
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);

      await tester.ensureVisible(find.text('Ouvrir dans Maps'));
      await tester.tap(find.text('Ouvrir dans Maps'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(launched.single.host, 'www.google.com');
      expect(launched.single.queryParameters['destination'], '6.139,1.216');
      await tester.tap(find.byTooltip('Appeler la boutique'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(launched.last.toString(), 'tel:+22890112233');

      await tester.ensureVisible(find.byKey(const Key('slide-knob')));
      await tester.drag(
        find.byKey(const Key('slide-knob')),
        const Offset(2000, 0),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(
        server.calls('POST', '/v1/driver/missions/mission-1/arrived-at-shop'),
        hasLength(1),
      );
    });

    testWidgets('vers le client (D13) : restant, arrivée, consigne', (
      tester,
    ) async {
      await withMission(
        tester,
        driverMissionBody(arrivedShop: true, pickedUp: true),
        routeM: 3400,
        routeS: 720,
      );
      server.on(
        'POST',
        '/v1/driver/missions/mission-1/arrived-at-customer',
        (_) => FakeResponse.json(204, null),
      );
      expect(find.text('ÉTAPE 2 SUR 2 · LIVRAISON'), findsOneWidget);
      // Bandeau et volet : 3,4 km, 12 min.
      expect(find.text('3,4 km'), findsNWidgets(2));
      expect(find.text('12 min'), findsNWidgets(2));
      expect(find.text('Restant'), findsOneWidget);
      expect(find.text('Arrivée'), findsOneWidget);
      expect(find.text('Awa M.'), findsOneWidget);
      expect(find.text('Rue 112, portail bleu · Bè Kpota'), findsOneWidget);
      expect(
        find.text('« Appelez-moi en arrivant, je descends. »'),
        findsOneWidget,
      );
      // Pas de retrait possible après le retrait du colis.
      expect(find.text('Je ne peux pas faire cette course'), findsNothing);
      await tester.tap(find.byTooltip('Ouvrir dans Maps'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(launched.single.queryParameters['destination'], '6.16,1.24');
      await tester.tap(find.byTooltip('Appeler le client'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(launched.last.toString(), 'tel:+22890445566');

      await tester.ensureVisible(find.byKey(const Key('slide-knob')));
      await tester.drag(
        find.byKey(const Key('slide-knob')),
        const Offset(2000, 0),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(
        server.calls(
          'POST',
          '/v1/driver/missions/mission-1/arrived-at-customer',
        ),
        hasLength(1),
      );
    });

    testWidgets('pharmacie : arrivée signalée dans l\'app, sans serveur', (
      tester,
    ) async {
      await withMission(tester, driverPharmacyMissionBody(), pharmacy: true);
      expect(find.text('ÉTAPE 1 SUR 2 · PHARMACIE'), findsOneWidget);
      expect(find.text('1 produit'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('slide-knob')));
      await tester.drag(
        find.byKey(const Key('slide-knob')),
        const Offset(2000, 0),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(
        server.requests.where((r) => r.path.contains('/arrived')),
        isEmpty,
      );
      expect(find.text('ÉTAPE 1 SUR 2 · PHARMACIE'), findsNothing);
    });

    testWidgets('position inconnue : distance et durée masquées', (
      tester,
    ) async {
      location.next = const LocationResult.failed(LocationFailure.unavailable);
      await withMission(tester, driverMissionBody());
      expect(find.text('Position inconnue'), findsOneWidget);
      expect(server.calls('POST', '/v1/geo/route'), isEmpty);
    });

    for (final toClient in [false, true]) {
      testWidgets(
        '${toClient ? 'vers le client' : 'vers le retrait'} : police à 220 % '
        'sur 320 dp',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2.2;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await withMission(
            tester,
            driverMissionBody(arrivedShop: toClient, pickedUp: toClient),
          );
          final error = tester.takeException();
          expect(error, isNull, reason: '$error');
          await tester.ensureVisible(find.byKey(const Key('slide-knob')));
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }

    // ── Retrait (D12) et preuve de remise (D14) : parties critiques, tests
    // écrits avant le code (spec 033, tâche 13).

    /// Glissière amenée au bout.
    Future<void> slideToEnd(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('slide-knob')));
      await tester.drag(
        find.byKey(const Key('slide-knob')),
        const Offset(2000, 0),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('retrait boutique (D12) : cases du colis, puis « récupéré »', (
      tester,
    ) async {
      await withMission(tester, driverMissionBody(arrivedShop: true));
      server.on(
        'POST',
        '/v1/driver/missions/mission-1/picked-up',
        (_) => FakeResponse.json(204, null),
      );
      expect(find.text('Retrait'), findsOneWidget);
      expect(find.text('1 sur 2'), findsOneWidget);
      expect(find.text('Chez Afi'), findsOneWidget);
      expect(find.text('Commande #1042 · payée'), findsOneWidget);
      expect(find.text('Vérifiez le colis'), findsOneWidget);
      // Course de boutique : pas de code de retrait.
      expect(find.text('VOTRE CODE DE RETRAIT'), findsNothing);
      // Cases à cocher d'abord : la glissière ne fait rien.
      await slideToEnd(tester);
      expect(
        server.calls('POST', '/v1/driver/missions/mission-1/picked-up'),
        isEmpty,
      );
      await tapVisible(tester, find.text('3 articles reçus'));
      await slideToEnd(tester);
      expect(
        server.calls('POST', '/v1/driver/missions/mission-1/picked-up'),
        isEmpty,
      );
      await tapVisible(tester, find.text('Colis fermé et en bon état'));
      await slideToEnd(tester);
      expect(
        server.calls('POST', '/v1/driver/missions/mission-1/picked-up'),
        hasLength(1),
      );
    });

    testWidgets('retrait pharmacie (D12) : code, sans glissière, passage seul '
        'après la validation, montant avancé', (tester) async {
      await withMission(
        tester,
        driverPharmacyMissionBody(pickupCode: '7319'),
        pharmacy: true,
      );
      // Arrivée à la pharmacie (D11).
      await slideToEnd(tester);
      expect(find.text('VOTRE CODE DE RETRAIT'), findsOneWidget);
      for (final digit in ['7', '3', '1', '9']) {
        expect(find.text(digit), findsOneWidget);
      }
      expect(
        find.textContaining('Montrez ce code au pharmacien'),
        findsOneWidget,
      );
      expect(find.textContaining('Paracétamol 500 mg'), findsOneWidget);
      // La pharmacie valide la remise : pas de glissière.
      expect(find.byKey(const Key('slide-knob')), findsNothing);

      // Elle valide : remise enregistrée, 4 500 F payés en espèces.
      server.on(
        'GET',
        '/v1/driver/pharmacy-missions/current',
        (_) => FakeResponse.json(200, {
          'mission': driverPharmacyMissionBody(
            pickedUp: true,
            cashAdvancedXof: 4500,
          ),
        }),
      );
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      // Étape suivante, seule, avec le montant avancé.
      expect(find.text('ÉTAPE 2 SUR 2 · LIVRAISON'), findsOneWidget);
      expect(
        find.textContaining('La pharmacie a validé la remise'),
        findsOneWidget,
      );
      expect(find.textContaining(formatXof(4500)), findsOneWidget);
      // Le code n'est plus affiché.
      expect(find.text('VOTRE CODE DE RETRAIT'), findsNothing);
    });

    testWidgets('ancienne course pharmacie sans code : « récupéré » proposé', (
      tester,
    ) async {
      await withMission(tester, driverPharmacyMissionBody(), pharmacy: true);
      server.on(
        'POST',
        '/v1/driver/pharmacy-missions/courier-1/picked-up',
        (_) => FakeResponse.json(204, null),
      );
      await slideToEnd(tester);
      expect(find.text('Retrait'), findsOneWidget);
      expect(find.text('VOTRE CODE DE RETRAIT'), findsNothing);
      await slideToEnd(tester);
      expect(
        server.calls(
          'POST',
          '/v1/driver/pharmacy-missions/courier-1/picked-up',
        ),
        hasLength(1),
      );
    });

    for (final pharmacy in [false, true]) {
      testWidgets('retrait ${pharmacy ? 'pharmacie' : 'boutique'} : police à '
          '220 % sur 320 dp', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2.2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await withMission(
          tester,
          pharmacy
              ? driverPharmacyMissionBody(pickupCode: '7319')
              : driverMissionBody(arrivedShop: true),
          pharmacy: pharmacy,
        );
        if (pharmacy) await slideToEnd(tester);
        expect(find.text('Retrait'), findsOneWidget);
        final error = tester.takeException();
        expect(error, isNull, reason: '$error');
      });
    }

    testWidgets('preuve de remise (D14) : 4 chiffres, puis confirmer', (
      tester,
    ) async {
      await withMission(
        tester,
        driverMissionBody(
          arrivedShop: true,
          pickedUp: true,
          arrivedCustomer: true,
        ),
      );
      server.on(
        'POST',
        '/v1/driver/missions/mission-1/deliver',
        (_) => FakeResponse.json(204, null),
      );
      expect(find.text('Preuve de remise'), findsOneWidget);
      expect(find.text('2 sur 2'), findsOneWidget);
      expect(find.text('#1042 · Awa M.'), findsOneWidget);
      expect(find.text('Code du client'), findsOneWidget);
      // Photo du colis masquée (pas de serveur).
      expect(find.text('Photo du colis remis'), findsNothing);

      await tapVisible(tester, find.text('Confirmer la livraison'));
      await tester.enterText(find.byType(TextField), '482');
      await tester.pump();
      await tapVisible(tester, find.text('Confirmer la livraison'));
      expect(
        server.calls('POST', '/v1/driver/missions/mission-1/deliver'),
        isEmpty,
      );
      await tester.enterText(find.byType(TextField), '4827');
      await tester.pump();
      await tapVisible(tester, find.text('Confirmer la livraison'));
      final calls = server.calls(
        'POST',
        '/v1/driver/missions/mission-1/deliver',
      );
      expect(calls, hasLength(1));
      expect(calls.single.body, {'code': '4827'});
    });

    testWidgets('code faux : erreur du serveur, code effacé', (tester) async {
      await withMission(
        tester,
        driverMissionBody(
          arrivedShop: true,
          pickedUp: true,
          arrivedCustomer: true,
        ),
      );
      server.on(
        'POST',
        '/v1/driver/missions/mission-1/deliver',
        (_) => FakeResponse.json(422, {
          'error': {
            'code': 'handover_code_invalid',
            'message': 'Code incorrect. Il reste 4 essai(s).',
          },
        }),
      );
      await tester.enterText(find.byType(TextField), '1111');
      await tester.pump();
      await tapVisible(tester, find.text('Confirmer la livraison'));
      expect(find.text('Code incorrect. Il reste 4 essai(s).'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('pharmacie : case ordonnance exigée, code faux du champ', (
      tester,
    ) async {
      await withMission(
        tester,
        driverPharmacyMissionBody(pickedUp: true, prescription: true),
        pharmacy: true,
      );
      var wrong = true;
      server.on(
        'POST',
        '/v1/driver/pharmacy-missions/courier-1/delivered',
        (_) => wrong
            ? FakeResponse.json(422, {
                'error': {
                  'code': 'validation_failed',
                  'message': 'Données invalides.',
                  'fields': {'code': 'Code incorrect.'},
                },
              })
            : FakeResponse.json(200, driverPharmacyMissionBody(pickedUp: true)),
      );
      // Arrivée chez le client (D13), dans l'app.
      await slideToEnd(tester);
      expect(find.text('Médicament sur ordonnance'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      // Sans la case : rien ne part.
      await tapVisible(tester, find.text('Confirmer la livraison'));
      expect(
        server.calls(
          'POST',
          '/v1/driver/pharmacy-missions/courier-1/delivered',
        ),
        isEmpty,
      );
      await tapVisible(tester, find.text("J'ai vu l'original de l'ordonnance"));
      await tapVisible(tester, find.text('Confirmer la livraison'));
      expect(find.text('Code incorrect.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      wrong = false;
      await tester.enterText(find.byType(TextField), '5678');
      await tester.pump();
      await tapVisible(tester, find.text('Confirmer la livraison'));
      final calls = server.calls(
        'POST',
        '/v1/driver/pharmacy-missions/courier-1/delivered',
      );
      expect(calls, hasLength(2));
      expect(calls.last.body, {'code': '5678', 'prescription_checked': true});
    });

    testWidgets('accueil en ligne (D09) : bandeau, jour calculé, Pause', (
      tester,
    ) async {
      await withDossier(review: 'approved', status: 'offline');
      approvedHome(delivered: [DateTime.now().toUtc()]);
      goOnlineServer();
      server.on(
        'GET',
        '/v1/driver/options',
        (_) => FakeResponse.json(200, driverOptionsBody()),
      );
      await launchApp(tester);
      await tester.drag(
        find.byKey(const Key('slide-knob')),
        const Offset(2000, 0),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('En ligne'), findsOneWidget);
      expect(find.text("À l'instant · Tokoin"), findsOneWidget);
      expect(find.text('Recherche de missions…'), findsOneWidget);
      // Une livraison aujourd'hui : 1 200 F.
      expect(find.text('1'), findsOneWidget);
      expect(find.text(formatXof(1200)), findsOneWidget);
      // Masqués : km parcourus, commandes bientôt prêtes.
      expect(find.textContaining('km'), findsNothing);
      expect(find.textContaining('bientôt prêtes'), findsNothing);

      await tester.tap(find.text('Pause'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      final calls = server.calls('PUT', '/v1/driver/availability');
      expect(calls, hasLength(2));
      expect(calls.last.body, {'online': false});
      expect(find.text('Vous êtes hors ligne'), findsOneWidget);
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
      expect(find.text('Ajouté'), findsNWidgets(4));
      // Zone et compte déjà enregistrés : rien à ressaisir.
      expect(find.text('Tokoin'), findsOneWidget);
      expect(find.text('+228 90 •• •• 77 · Kossi Adjo'), findsOneWidget);
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
      // Compte déjà enregistré : pas renvoyé ; dossier renvoyé.
      expect(server.calls('PUT', '/v1/driver/payout'), isEmpty);
      expect(
        server.calls('POST', '/v1/driver/activities/delivery/submit'),
        hasLength(1),
      );
      // Le serveur garde l'ancienne carte grise : 5 pièces, 4 types.
      expect(serverDocuments, hasLength(5));
      expect(find.text('Moto · 4 documents'), findsOneWidget);
    });

    testWidgets('envoi interrompu : pièces manquantes complétées', (
      tester,
    ) async {
      await withDossier(documents: ['id_card']);
      await launchApp(tester);
      expect(find.text('1 document sur 4 : dossier incomplet'), findsOneWidget);
      await tapText(tester, 'Compléter mon dossier');
      expect(find.text('Ajouté'), findsOneWidget);
      for (final label in [
        'Permis de conduire',
        'Carte grise',
        'Assurance du véhicule',
      ]) {
        await tapText(tester, label);
        await tester.tap(find.text('Choisir une photo'));
        await tester.pumpAndSettle();
      }
      await tapText(tester, 'Envoyer mon dossier');
      expect(documentsSent.map((d) => d['kind']), [
        'driving_license',
        'vehicle_registration',
        'vehicle_insurance',
      ]);
      // Déjà en vérification : pas de nouvel envoi.
      expect(
        server.calls('POST', '/v1/driver/activities/delivery/submit'),
        isEmpty,
      );
      expect(find.text('Moto · 4 documents'), findsOneWidget);
      expect(find.text('Compléter mon dossier'), findsNothing);
    });

    testWidgets('correction : le retour revient au motif', (tester) async {
      await withDossier(review: 'rejected');
      await launchApp(tester);
      await tapText(tester, 'Corriger mon dossier');
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(find.text("Votre dossier n'a pas été validé"), findsOneWidget);
      expect(server.calls('POST', '/v1/auth/logout'), isEmpty);
    });

    testWidgets('compléments demandés : motif, « Compléter mon dossier »', (
      tester,
    ) async {
      await withDossier(review: 'changes_requested');
      await launchApp(tester);
      expect(find.text('Votre dossier est à compléter'), findsOneWidget);
      expect(find.text('Motif : Carte grise illisible.'), findsOneWidget);
      await tapText(tester, 'Compléter mon dossier');
      expect(find.text('Corrigez votre dossier'), findsOneWidget);
    });

    testWidgets('récapitulatif : modèle et compte de versement masqué', (
      tester,
    ) async {
      await withDossier();
      await launchApp(tester);
      await tapText(tester, 'Voir mon dossier');
      expect(find.text('Honda CG 125'), findsOneWidget);
      expect(
        find.text('Moov Money (Flooz) · +228 90 •• •• 77'),
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
