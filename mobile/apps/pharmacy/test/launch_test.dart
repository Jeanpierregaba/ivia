import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import 'helpers.dart';

const _page1 = 'Les urgences de votre quartier, en direct.';
const _page2 = "Répondez en moins d'une minute.";
const _page3 = 'Le client confirme, vous préparez.';

Finder _rich(String text) => find.text(text, findRichText: true);

void main() {
  late PharmacyHarness app;

  setUp(() {
    PharmacyHarness.resetDevice();
    app = PharmacyHarness();
  });

  group('localisation (030)', () {
    testWidgets('après le splash, puis la présentation', (tester) async {
      await app.launch(tester);
      expect(_rich(locationTitle), findsOneWidget);
      await tapText(tester, "Saisir l'adresse");
      expect(_rich(_page1), findsOneWidget);
      expect(app.location.requests, 0);

      // Relancée : plus d'écran de localisation, la présentation reste à voir.
      await app.launch(tester);
      expect(_rich(locationTitle), findsNothing);
      expect(_rich(_page1), findsOneWidget);
    });

    testWidgets('« Autoriser » : fenêtre du système', (tester) async {
      PharmacyHarness.resetDevice(prefs: {'onboarding_seen': true});
      await app.launch(tester);
      await tapText(tester, 'Autoriser la localisation');
      expect(app.location.requests, 1);
      expect(find.text('Espace pharmacie'), findsOneWidget);
    });

    testWidgets('position déjà autorisée : pas d\'écran', (tester) async {
      PharmacyHarness.resetDevice(prefs: {'onboarding_seen': true});
      app.location.state = LocationAccess.granted;
      await app.launch(tester);
      expect(_rich(locationTitle), findsNothing);
      expect(find.text('Espace pharmacie'), findsOneWidget);
    });
  });

  group('présentation (F01 à F03)', () {
    setUp(() {
      PharmacyHarness.resetDevice(prefs: {'location_prompt_done': true});
    });

    testWidgets('3 pages, « Commencer » ouvre la connexion, une seule fois', (
      tester,
    ) async {
      await app.launch(tester);
      expect(_rich(_page1), findsOneWidget);
      expect(find.text('Pharmacie'), findsOneWidget);
      await tapText(tester, 'Suivant');
      expect(_rich(_page2), findsOneWidget);
      await tapText(tester, 'Suivant');
      expect(_rich(_page3), findsOneWidget);
      // Dernière page : plus de « Passer ».
      expect(find.text('Passer').hitTestable(), findsNothing);
      await tapText(tester, 'Commencer');
      expect(find.text('Espace pharmacie'), findsOneWidget);

      await app.launch(tester);
      expect(_rich(_page1), findsNothing);
      expect(find.text('Espace pharmacie'), findsOneWidget);
    });

    testWidgets('« Passer » ouvre la connexion', (tester) async {
      await app.launch(tester);
      await tapText(tester, 'Passer');
      expect(find.text('Espace pharmacie'), findsOneWidget);
    });

    testWidgets('le retour rond revient à la page précédente', (tester) async {
      await app.launch(tester);
      await tapText(tester, 'Suivant');
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      expect(_rich(_page1), findsOneWidget);
    });

    testWidgets('police à 200 % sur 320 dp : chaque page tient', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await app.launch(tester);
      for (final next in ['Suivant', 'Suivant', null]) {
        expect(tester.takeException(), isNull);
        if (next != null) await tapText(tester, next);
      }
      expect(_rich(_page3), findsOneWidget);
    });
  });

  group('connexion (F04, F05)', () {
    setUp(() {
      PharmacyHarness.resetDevice(
        prefs: {'location_prompt_done': true, 'onboarding_seen': true},
      );
    });

    testWidgets('numéro seulement, WhatsApp puis SMS, conditions partenaires', (
      tester,
    ) async {
      await app.launch(tester);
      expect(find.text('Espace pharmacie'), findsOneWidget);
      expect(
        find.text(
          'Connectez-vous avec votre numéro. Nous vous envoyons un code.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pharmacie'), findsOneWidget);
      expect(find.text('E-mail'), findsNothing);
      expect(find.text('Recevoir le code sur WhatsApp'), findsOneWidget);
      expect(find.text('Recevoir par SMS'), findsOneWidget);
      expect(
        find.textContaining('Conditions partenaires', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Pas de mot de passe'), findsNothing);
    });

    for (final sms in [true, false]) {
      testWidgets('code par ${sms ? 'SMS' : 'WhatsApp'} : titre du canal, '
          '« Valider » grisé avant 6 chiffres', (tester) async {
        app.server.on(
          'POST',
          '/v1/auth/phone/code',
          (_) => FakeResponse.json(202, {
            ...phoneOtpBody,
            'channel': sms ? 'sms' : 'whatsapp',
          }),
        );
        await app.launch(tester);
        await tester.enterText(find.byType(TextField), '90 11 22 33');
        await tapText(
          tester,
          sms ? 'Recevoir par SMS' : 'Recevoir le code sur WhatsApp',
        );
        expect(
          find.text(sms ? 'Vérifiez vos SMS' : 'Vérifiez WhatsApp'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Modifier', findRichText: true),
          findsOneWidget,
        );
        expect(find.textContaining('Le code est valable'), findsNothing);
        await tester.enterText(find.byType(TextField), '6204');
        await tester.pump();
        final validate = find.ancestor(
          of: find.text('Valider'),
          matching: find.byType(FilledButton),
        );
        expect(tester.widget<FilledButton>(validate).onPressed, isNull);
      });
    }
  });
}
