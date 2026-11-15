import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_pharmacy/common/ui.dart';
import 'package:ivia_pharmacy/features/alerts/response_screen.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'helpers.dart';

void main() {
  late PharmacyHarness app;
  late Map<String, dynamic> alert;

  setUp(() async {
    PharmacyHarness.resetDevice();
    app = PharmacyHarness();
    alert = alertBody(id: 'a1');
    await app.signInApproved(inbox: () => [alert]);
    app.server
      ..on('GET', '/v1/pharmacy/inbox/a1', (_) => FakeResponse.json(200, alert))
      ..on(
        'POST',
        '/v1/pharmacy/inbox/a1/respond',
        (_) => FakeResponse.json(201, {}),
      );
  });

  Future<void> openResponse(WidgetTester tester) async {
    await app.launch(tester);
    await tapText(tester, 'Voir');
    await tapText(tester, 'Répondre');
  }

  /// Fait défiler la liste de la réponse jusqu'à [target].
  Future<void> reveal(WidgetTester tester, Finder target, {bool up = false}) =>
      tester.scrollUntilVisible(
        target,
        up ? -200 : 200,
        scrollable: find
            .descendant(
              of: find.byType(ResponseScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );

  PButton sendButton(WidgetTester tester) => tester.widget<PButton>(
    find.widgetWithText(PButton, 'Envoyer la réponse'),
  );

  Finder priceOf(int i) => find.descendant(
    of: find
        .ancestor(
          of: find.text('Prix unitaire'),
          matching: find.byType(IviaFieldLabel),
        )
        .at(i),
    matching: find.byType(TextField),
  );

  testWidgets('total des disponibles, générique, ordonnance, puis F14', (
    tester,
  ) async {
    await openResponse(tester);
    expect(find.text('Votre réponse'), findsOneWidget);
    expect(find.text('Demandé : 1'), findsOneWidget);
    expect(find.text('Demandé : 2'), findsOneWidget);
    // Prix manquants : rien ne part.
    expect(sendButton(tester).onTap, isNull);

    await tester.enterText(priceOf(0), '1250');
    await tester.enterText(priceOf(1), '3100');
    await tester.pump();
    expect(find.text('1 250'), findsOneWidget);
    await reveal(tester, find.text(formatXof(7450)));
    expect(find.text(formatXof(7450)), findsOneWidget);
    expect(find.text('2 / 2 disponibles'), findsOneWidget);

    // Générique proposé pour l'amoxicilline, délivrée sur ordonnance.
    final generic = find.text('Proposer un générique').last;
    await tester.ensureVisible(generic);
    await tester.pumpAndSettle();
    await tester.tap(generic);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Amoxicilline Denk 500 mg',
    );
    await tapText(tester, 'Valider');
    expect(
      find.textContaining('Amoxicilline Denk 500 mg', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('Délivré sur ordonnance uniquement').last);
    await tester.pump();

    // Paracétamol indisponible : le total ne compte que l'amoxicilline.
    await tester.fling(
      find
          .descendant(
            of: find.byType(ResponseScreen),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, 2000),
      3000,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PSwitch).first);
    await tester.pumpAndSettle();
    await reveal(tester, find.text(formatXof(6200)));
    expect(find.text(formatXof(6200)), findsOneWidget);
    expect(find.text('1 / 2 disponible'), findsOneWidget);

    await tapText(tester, 'Envoyer la réponse');
    expect(
      app.server.calls('POST', '/v1/pharmacy/inbox/a1/respond').single.body,
      {
        'lines': [
          {
            'alert_item_id': 'i1',
            'name': 'Paracétamol 1000 mg',
            'quantity': 1,
            'unit_price_xof': 0,
            'available': false,
            'prescription_required': false,
          },
          {
            'alert_item_id': 'i2',
            'name': 'Amoxicilline Denk 500 mg',
            'quantity': 2,
            'unit_price_xof': 3100,
            'available': true,
            'prescription_required': true,
          },
        ],
        'note': '',
      },
    );
    expect(find.text('Réponse envoyée'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tapText(tester, 'Retour aux alertes');
    expect(find.text('Alertes à traiter'), findsOneWidget);
  });

  testWidgets('réponse trop tard : message de l\'API, écran gardé', (
    tester,
  ) async {
    app.server.on(
      'POST',
      '/v1/pharmacy/inbox/a1/respond',
      (_) =>
          FakeResponse.error(409, 'alert_closed', 'Cette alerte est terminée.'),
    );
    await openResponse(tester);
    await tester.enterText(priceOf(0), '1250');
    await tester.enterText(priceOf(1), '3100');
    await tester.pump();
    await tapText(tester, 'Envoyer la réponse');
    await reveal(tester, find.text('Cette alerte est terminée.'));
    expect(find.text('Cette alerte est terminée.'), findsOneWidget);
    expect(find.text('Votre réponse'), findsOneWidget);
  });

  testWidgets('ordonnance en photo seule : produits ajoutés à la main', (
    tester,
  ) async {
    alert = alertBody(
      id: 'a1',
      items: [],
      photos: [
        {'kind': 'prescription', 'url': null},
      ],
    );
    await openResponse(tester);
    expect(find.text('Produit'), findsOneWidget);
    await tapText(tester, 'Ajouter un produit');
    expect(find.text('Produit'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Retirer ce produit').last);
    await tester.pump();
    expect(find.text('Produit'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Ibuprofène 400 mg');
    await tester.enterText(priceOf(0), '900');
    await tester.pump();
    await tapText(tester, 'Envoyer la réponse');
    final body =
        app.server.calls('POST', '/v1/pharmacy/inbox/a1/respond').single.body
            as Map<String, dynamic>;
    expect(body['lines'], [
      {
        'name': 'Ibuprofène 400 mg',
        'quantity': 1,
        'unit_price_xof': 900,
        'available': true,
        'prescription_required': false,
      },
    ]);
  });

  testWidgets('police à 200 % sur 320 dp : la réponse tient', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openResponse(tester);
    expect(tester.takeException(), isNull);
  });
}
