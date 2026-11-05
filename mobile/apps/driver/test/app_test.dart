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
  late List<Map<String, dynamic>> documentsSent;

  /// Dossier côté serveur : comme le backend, une pièce envoyée s'ajoute aux
  /// précédentes, sans les remplacer.
  late List<String> serverDocuments;
  late String serverVehicle;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    picker = _FakePicker();
    documentsSent = [];
    serverDocuments = [];
    serverVehicle = 'motorbike';
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
      ..on('PUT', '/v1/driver/application', (request) {
        serverVehicle =
            (request.body! as Map<String, dynamic>)['vehicle_type'] as String;
        return FakeResponse.json(
          200,
          driverBody(vehicleType: serverVehicle, documents: serverDocuments),
        );
      })
      ..on('POST', '/v1/driver/application/documents', (request) {
        final body = request.body! as Map<String, dynamic>;
        documentsSent.add(body);
        serverDocuments = [...serverDocuments, body['kind'] as String];
        return FakeResponse.json(
          201,
          driverBody(vehicleType: serverVehicle, documents: serverDocuments),
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
    PhotoPicker? photoPicker,
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
          photoPickerProvider.overrideWithValue(photoPicker ?? picker),
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
    await tapText(tester, 'Recevoir le code sur WhatsApp');
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
      final stored = server.requests.where((r) => r.host == 'prive.test');
      expect(stored, hasLength(3));
      for (final put in stored) {
        expect(put.headers['authorization'], isNull);
      }
      expect(picker.requests.map((r) => r.$2).toSet(), {2048});

      expect(
        find.text('Votre dossier est en cours de vérification'),
        findsOneWidget,
      );
      expect(find.text('Voiture · 3 documents'), findsOneWidget);
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
        return FakeResponse.json(201, driverBody(documents: serverDocuments));
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
        return FakeResponse.json(201, driverBody(documents: serverDocuments));
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
      expect(server.calls('POST', '/v1/uploads'), hasLength(4));
      expect(documentsSent.map((d) => d['kind']), [
        'id_card',
        'vehicle_registration',
        'driving_license',
      ]);
      expect(documentsSent.last['object_key'], 'driver_document/u1/doc4.jpg');
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
        '/v1/driver/application',
        (_) => FakeResponse.error(
          400,
          'validation_failed',
          'Données invalides.',
          fields: {'vehicle_plate': 'Immatriculation invalide.'},
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
      ],
    }) async {
      await signedInWith(_user());
      serverDocuments = documents;
      server.on(
        'GET',
        '/v1/driver/me',
        (_) => FakeResponse.json(
          200,
          driverBody(
            review: review,
            status: status ?? review,
            documents: serverDocuments,
          ),
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
      expect(find.text('Profil'), findsOneWidget);
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
      // Le serveur garde l'ancienne carte grise : 4 pièces, 3 types.
      expect(serverDocuments, hasLength(4));
      expect(find.text('Moto · 3 documents'), findsOneWidget);
    });

    testWidgets('envoi interrompu : pièces manquantes complétées', (
      tester,
    ) async {
      await withDossier(documents: ['id_card']);
      await launchApp(tester);
      expect(find.text('1 document sur 3 : dossier incomplet'), findsOneWidget);
      await tapText(tester, 'Compléter mon dossier');
      expect(find.text('Envoyé'), findsOneWidget);
      for (final label in ['Permis de conduire', 'Carte grise']) {
        await tapText(tester, label);
        await tester.tap(find.text('Choisir une photo'));
        await tester.pumpAndSettle();
      }
      await tapText(tester, 'Envoyer mon dossier');
      expect(documentsSent.map((d) => d['kind']), [
        'driving_license',
        'vehicle_registration',
      ]);
      expect(find.text('Moto · 3 documents'), findsOneWidget);
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
