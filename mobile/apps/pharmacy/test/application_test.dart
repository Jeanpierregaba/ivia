import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_pharmacy/common/ui.dart';
import 'package:ivia_pharmacy/features/application/application_flow.dart';

import 'helpers.dart';

void main() {
  late PharmacyHarness app;

  /// Dossier du compte : aucun avant la création, puis [created].
  late Map<String, dynamic>? profile;

  setUp(() async {
    PharmacyHarness.resetDevice();
    app = PharmacyHarness();
    await app.signIn();
    profile = null;
    app
      ..acceptUploads()
      ..server.on(
        'GET',
        '/v1/pharmacy/me',
        (_) => profile == null
            ? FakeResponse.error(404, 'not_found', 'Introuvable.')
            : FakeResponse.json(200, profile),
      )
      ..server.on(
        'GET',
        '/v1/geo/reverse',
        (_) => FakeResponse.json(200, {'label': 'Tokoin'}),
      )
      ..server.on(
        'GET',
        '/v1/geo/my-places',
        (_) => FakeResponse.json(200, {'items': <Object>[]}),
      )
      ..server.on(
        'GET',
        '/v1/neighborhoods',
        (_) => FakeResponse.json(200, {'items': <Object>[]}),
      )
      ..server.on('POST', '/v1/pharmacy/application', (_) {
        profile = pharmacyBody(documents: ['storefront_photo']);
        return FakeResponse.json(201, profile);
      })
      ..server.on(
        'POST',
        '/v1/auth/logout',
        (_) => FakeResponse.json(204, null),
      );
  });

  Future<void> fill(WidgetTester tester) async {
    for (final (label, value) in [
      ('Nom de la pharmacie', 'Pharmacie du Boulevard'),
      ("N° d'autorisation d'exercice", 'AE-2019-0412'),
      ('Téléphone de la pharmacie', '22 21 45 67'),
      ('E-mail de la pharmacie', 'contact@boulevard.tg'),
      ('Adresse', 'Bd du 13 Janvier, Tokoin'),
    ]) {
      await tester.ensureVisible(fieldOf(label));
      await tester.enterText(fieldOf(label), value);
    }
    await tester.pumpAndSettle();
  }

  group('étape de reprise', () {
    test('première étape incomplète', () {
      PharmacyProfile p(Map<String, dynamic> j) => PharmacyProfile.fromJson(j);
      expect(initialDossierStep(null), 1);
      expect(initialDossierStep(p(pharmacyBody())), 3);
      expect(
        initialDossierStep(
          p(
            pharmacyBody(
              documents: [
                'opening_authorization',
                'owner_id',
                'storefront_photo',
              ],
            ),
          ),
        ),
        4,
      );
      expect(
        initialDossierStep(
          p(
            pharmacyBody(
              documents: [
                'opening_authorization',
                'owner_id',
                'storefront_photo',
              ],
              payout: true,
            ),
          ),
        ),
        5,
      );
      expect(
        initialDossierStep(
          p(pharmacyBody(status: 'changes_requested', note: 'Photo floue.')),
        ),
        1,
      );
    });
  });

  group('étapes 1 et 2 (F06)', () {
    testWidgets('fiche : « 1 sur 5 », champs exigés avant la carte', (
      tester,
    ) async {
      await app.launch(tester);
      expect(find.text('Votre pharmacie'), findsOneWidget);
      expect(find.text('1 sur 5'), findsOneWidget);
      await tapText(tester, 'Continuer');
      expect(find.text('Saisissez le nom de la pharmacie.'), findsOneWidget);
      expect(find.text('Confirmer cet emplacement'), findsNothing);
      expect(app.server.calls('POST', '/v1/pharmacy/application'), isEmpty);
    });

    for (final allow in [false, true]) {
      testWidgets('carte sans autorisation (030), '
          '${allow ? 'position du téléphone' : 'repère placé à la main'}, '
          'puis création et envoi de la devanture', (tester) async {
        await app.launch(tester);
        await tapText(tester, 'Ajouter');
        await tapText(tester, 'Choisir une photo');
        expect(find.text('Changer'), findsOneWidget);
        await fill(tester);
        await tapText(tester, 'Continuer');
        expect(find.text(locationTitle, findRichText: true), findsOneWidget);
        await tapText(
          tester,
          allow ? 'Autoriser la localisation' : "Saisir l'adresse",
        );
        expect(app.location.requests, allow ? 1 : 0);
        await tapText(tester, 'Confirmer cet emplacement');

        final sent =
            app.server.calls('POST', '/v1/pharmacy/application').single.body
                as Map<String, dynamic>;
        expect(sent['name'], 'Pharmacie du Boulevard');
        expect(sent['phone'], '+22822214567');
        expect(sent['email'], 'contact@boulevard.tg');
        if (allow) {
          expect(sent['location'], {'lat': 6.1375, 'lng': 1.2123});
        } else {
          expect(sent['location'], isNotNull);
        }
        // La devanture part après la création de la pharmacie.
        final paths = [
          for (final r in app.server.requests) '${r.method} ${r.path}',
        ];
        final created = paths.indexOf('POST /v1/pharmacy/application');
        expect(paths.indexOf('POST /v1/uploads'), greaterThan(created));
        expect(
          app.server.calls('POST', '/v1/pharmacy/me/documents').single.body,
          {
            'kind': 'storefront_photo',
            'object_key': 'pharmacy_document/u1/piece.jpg',
          },
        );
        expect(find.text('Votre pharmacie'), findsNothing);
      });
    }

    testWidgets('erreur de champ à la création : retour à la fiche', (
      tester,
    ) async {
      app.server.on(
        'POST',
        '/v1/pharmacy/application',
        (_) => FakeResponse.error(
          400,
          'validation_failed',
          'Données invalides.',
          fields: {'license_number': 'Numéro déjà utilisé.'},
        ),
      );
      app.location.state = LocationAccess.granted;
      await app.launch(tester);
      await fill(tester);
      await tapText(tester, 'Continuer');
      await tapText(tester, 'Confirmer cet emplacement');
      expect(find.text('1 sur 5'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Numéro déjà utilisé.'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Numéro déjà utilisé.'), findsOneWidget);
      expect(app.server.calls('POST', '/v1/uploads'), isEmpty);
    });

    testWidgets('compléments demandés : motif en haut de la fiche remplie', (
      tester,
    ) async {
      profile = pharmacyBody(
        status: 'changes_requested',
        note: 'La photo de la devanture est floue.',
        documents: ['opening_authorization', 'owner_id', 'storefront_photo'],
      );
      await app.launch(tester);
      expect(find.text('Compléments demandés'), findsOneWidget);
      expect(find.text('La photo de la devanture est floue.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(fieldOf('Nom de la pharmacie'))
            .controller!
            .text,
        'Pharmacie du Boulevard',
      );
    });

    testWidgets('retour depuis la fiche : déconnexion', (tester) async {
      await app.launch(tester);
      await tester.tap(find.bySemanticsLabel('Retour'));
      await tester.pumpAndSettle();
      expect(app.server.calls('POST', '/v1/auth/logout'), hasLength(1));
    });

    testWidgets('police à 200 % sur 320 dp : la fiche tient', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await app.launch(tester);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Position sur la carte'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('étape 3 (F07)', () {
    /// Pièces reçues par le faux serveur.
    late List<String> docs;

    setUp(() {
      docs = ['storefront_photo'];
      profile = pharmacyBody(documents: docs);
      app.server.on('POST', '/v1/pharmacy/me/documents', (r) {
        docs.add((r.body as Map)['kind'] as String);
        profile = pharmacyBody(documents: docs);
        return FakeResponse.json(201, {});
      });
    });

    PButton continueButton(WidgetTester tester) =>
        tester.widget<PButton>(find.widgetWithText(PButton, 'Continuer'));

    testWidgets('brouillon : reprise aux pièces, envoi, case obligatoire', (
      tester,
    ) async {
      await app.launch(tester);
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('3 sur 5'), findsOneWidget);
      expect(find.text('Vérification de la pharmacie'), findsOneWidget);
      // Devanture déjà reçue : pas de ligne.
      expect(find.text('Photo de la devanture'), findsNothing);
      expect(continueButton(tester).onTap, isNull);

      for (final label in [
        "Autorisation d'exercice",
        "Pièce d'identité du titulaire",
      ]) {
        await tapText(tester, label);
        await tapText(tester, 'Prendre une photo');
      }
      expect(docs, ['storefront_photo', 'opening_authorization', 'owner_id']);
      expect(find.text('Ajouté'), findsNWidgets(2));
      // Pièces complètes, case pas cochée : toujours grisé.
      expect(continueButton(tester).onTap, isNull);
      await tapText(
        tester,
        'Je certifie être titulaire ou gérant de cette pharmacie.',
      );
      expect(continueButton(tester).onTap, isNotNull);
      await tapText(tester, 'Continuer');
      expect(find.text('3 sur 5'), findsNothing);
    });

    testWidgets('devanture pas partie : redemandée ici', (tester) async {
      docs = [];
      profile = pharmacyBody(documents: docs);
      await app.launch(tester);
      expect(find.text('Photo de la devanture'), findsOneWidget);
    });

    testWidgets('retour : la fiche', (tester) async {
      await app.launch(tester);
      await tester.tap(find.bySemanticsLabel('Retour'));
      await tester.pumpAndSettle();
      expect(find.text('1 sur 5'), findsOneWidget);
      expect(app.server.calls('POST', '/v1/auth/logout'), isEmpty);
    });
  });
}
