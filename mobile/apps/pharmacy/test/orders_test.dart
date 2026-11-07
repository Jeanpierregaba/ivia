import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_pharmacy/common/ui.dart';
import 'package:ivia_pharmacy/features/orders/order_screen.dart';

import 'helpers.dart';

void main() {
  late PharmacyHarness app;
  late Map<String, dynamic> order;

  setUp(() async {
    PharmacyHarness.resetDevice();
    app = PharmacyHarness();
    order = orderBody();
    await app.signInApproved(orders: () => [order]);
    app.server
      ..on(
        'GET',
        '/v1/pharmacy/reservations/o1',
        (_) => FakeResponse.json(200, order),
      )
      ..on('POST', '/v1/pharmacy/reservations/o1/prepared', (_) {
        order = {
          ...order,
          'prepared_at': DateTime.now().toUtc().toIso8601String(),
        };
        return FakeResponse.json(200, {});
      })
      ..on('POST', '/v1/pharmacy/reservations/o1/complete', (r) {
        if ((r.body as Map)['code'] != '3916') {
          return FakeResponse.error(
            400,
            'invalid_code',
            'Code de retrait incorrect.',
          );
        }
        order = {...order, 'status': 'completed'};
        return FakeResponse.json(200, {});
      })
      ..on('POST', '/v1/pharmacy/reservations/o1/cancel', (_) {
        order = {...order, 'status': 'cancelled'};
        return FakeResponse.json(200, {});
      });
  });

  /// Ouvre la commande depuis la carte « à préparer » de l'accueil.
  Future<void> openOrder(WidgetTester tester) async {
    await app.launch(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(
      MaterialPageRoute<void>(builder: (_) => const OrderScreen(orderId: 'o1')),
    );
    await tester.pumpAndSettle();
  }

  PButton button(WidgetTester tester, String label) =>
      tester.widget<PButton>(find.widgetWithText(PButton, label));

  group('retrait (F15, F16)', () {
    testWidgets('client confirmé : produits, total, mise de côté puis remise', (
      tester,
    ) async {
      await openOrder(tester);
      expect(find.text('Commande #M-208'), findsOneWidget);
      expect(find.text('Client confirmé'), findsOneWidget);
      expect(
        find.textContaining("Mettez les produits de côté jusqu'à"),
        findsOneWidget,
      );
      expect(find.text('Retrait au comptoir'), findsOneWidget);
      expect(find.textContaining('sur ordonnance'), findsOneWidget);
      expect(find.text('À encaisser sur place'), findsOneWidget);
      expect(find.text(formatXof(7450)), findsOneWidget);

      await tapText(tester, 'Produits mis de côté');
      expect(
        app.server.calls('POST', '/v1/pharmacy/reservations/o1/prepared'),
        hasLength(1),
      );
      // Remise (F16) : code et cases exigés.
      expect(find.text('Code de retrait du client'), findsOneWidget);
      expect(button(tester, 'Valider la remise').onTap, isNull);
      await tester.enterText(find.byType(TextField), '3916');
      await tester.pump();
      expect(button(tester, 'Valider la remise').onTap, isNull);
      await tapText(tester, "J'ai vu l'original de l'ordonnance");
      expect(button(tester, 'Valider la remise').onTap, isNull);
      await tapText(tester, 'Le client a payé ${formatXof(7450)} sur place');
      expect(button(tester, 'Valider la remise').onTap, isNotNull);
      expect(find.textContaining('est délivré sur ordonnance'), findsOneWidget);

      await tapText(tester, 'Valider la remise');
      expect(
        app.server
            .calls('POST', '/v1/pharmacy/reservations/o1/complete')
            .single
            .body,
        {'code': '3916'},
      );
      expect(find.text('Commande remise au client'), findsOneWidget);
      await tapText(tester, 'Retour aux commandes');
      expect(find.text('Commande remise'), findsOneWidget);
    });

    testWidgets('code faux : erreur, écran gardé, code effacé', (tester) async {
      order = orderBody(prepared: true);
      await openOrder(tester);
      await tapText(tester, 'Remettre au client');
      await tester.enterText(find.byType(TextField), '1111');
      await tapText(tester, "J'ai vu l'original de l'ordonnance");
      await tapText(tester, 'Le client a payé ${formatXof(7450)} sur place');
      await tapText(tester, 'Valider la remise');
      expect(find.text('Code de retrait incorrect.'), findsOneWidget);
      expect(find.text('Code de retrait du client'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
    });

    testWidgets('annulée pendant qu\'on la regarde : actions retirées', (
      tester,
    ) async {
      await openOrder(tester);
      order = {
        ...order,
        'status': 'cancelled',
        'cancel_reason': 'Client injoignable',
      };
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Commande annulée'), findsOneWidget);
      expect(find.text('Produits mis de côté'), findsNothing);
      expect(find.text('Signaler une rupture'), findsNothing);
    });
  });

  group('annulation (F18)', () {
    testWidgets('« Garder la commande » ferme sans rien faire', (tester) async {
      await openOrder(tester);
      await tapText(tester, 'Signaler une rupture');
      expect(find.text('Annuler cette commande ?'), findsOneWidget);
      await tapText(tester, 'Garder la commande');
      expect(find.text('Annuler cette commande ?'), findsNothing);
      expect(
        app.server.calls('POST', '/v1/pharmacy/reservations/o1/cancel'),
        isEmpty,
      );
    });

    testWidgets('motif choisi envoyé', (tester) async {
      await openOrder(tester);
      await tapText(tester, 'Signaler une rupture');
      await tapText(tester, 'Erreur sur le prix');
      await tapText(tester, "Confirmer l'annulation");
      expect(
        app.server
            .calls('POST', '/v1/pharmacy/reservations/o1/cancel')
            .single
            .body,
        {'reason': 'Erreur sur le prix'},
      );
      expect(find.text('Commande annulée'), findsOneWidget);
    });

    testWidgets('« Autre motif » : texte libre exigé', (tester) async {
      await openOrder(tester);
      await tapText(tester, 'Signaler une rupture');
      await tapText(tester, 'Autre motif');
      expect(button(tester, "Confirmer l'annulation").onTap, isNull);
      await tester.enterText(
        find.byType(TextField).last,
        'Pharmacie fermée ce soir',
      );
      await tester.pump();
      await tapText(tester, "Confirmer l'annulation");
      expect(
        app.server
            .calls('POST', '/v1/pharmacy/reservations/o1/cancel')
            .single
            .body,
        {'reason': 'Pharmacie fermée ce soir'},
      );
    });
  });

  group('livraison (F17, F19)', () {
    testWidgets('payée dans l\'app, étapes, marquer prête', (tester) async {
      order = orderBody(delivery: true, status: 'courier_search');
      await openOrder(tester);
      expect(find.text('Livraison #M-208'), findsOneWidget);
      expect(find.text("Payée dans l'app"), findsOneWidget);
      expect(find.text('Préparer la commande'), findsOneWidget);
      expect(find.text("Recherche d'un livreur"), findsOneWidget);
      await tapText(tester, 'Marquer prête');
      expect(
        app.server.calls('POST', '/v1/pharmacy/reservations/o1/prepared'),
        hasLength(1),
      );
      expect(find.text('Marquer prête'), findsNothing);
    });

    testWidgets('récupérée par le livreur : F19 et montant à verser', (
      tester,
    ) async {
      order = orderBody(
        delivery: true,
        status: 'courier_assigned',
        prepared: true,
        courier: {'first_name': 'Kossi', 'vehicle_plate': 'TG 1234'},
      );
      await openOrder(tester);
      expect(find.textContaining('Kossi'), findsOneWidget);
      order = {...order, 'status': 'picked_up'};
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Commande remise au livreur'), findsOneWidget);
      expect(find.textContaining('Kossi livre le client'), findsOneWidget);
      expect(find.text('À vous verser'), findsOneWidget);
    });
  });

  testWidgets('police à 200 % sur 320 dp : commande et remise tiennent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openOrder(tester);
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Produits mis de côté');
    expect(tester.takeException(), isNull);
  });
}
