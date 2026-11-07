import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_pharmacy/features/alerts/history_row.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'helpers.dart';

void main() {
  late PharmacyHarness app;
  late List<Map<String, dynamic>> inbox;
  late List<Map<String, dynamic>> orders;

  setUp(() async {
    PharmacyHarness.resetDevice();
    app = PharmacyHarness();
    inbox = [
      alertBody(id: 'a1'),
      alertBody(id: 'a2', seen: true),
      {
        ...alertBody(
          id: 'a3',
          responded: true,
          endsIn: const Duration(minutes: -5),
        ),
        'my_response': {
          'total_xof': 7450,
          'unlocked': false,
          'lines': [
            {
              'name': 'A',
              'quantity': 1,
              'unit_price_xof': 100,
              'line_total_xof': 100,
              'available': true,
            },
            {
              'name': 'B',
              'quantity': 1,
              'unit_price_xof': 0,
              'line_total_xof': 0,
              'available': false,
            },
          ],
        },
      },
      alertBody(
        id: 'a4',
        endsIn: const Duration(minutes: -5),
        status: 'expired',
      ),
      alertBody(id: 'a5', status: 'declined'),
    ];
    orders = [
      orderBody(id: 'o1'),
      {
        ...orderBody(id: 'o2', delivery: true, status: 'completed'),
        'number': 'M-211',
      },
    ];
    await app.signInApproved(inbox: () => inbox, orders: () => orders);
    app.server.onPattern(
      'GET',
      '/v1/pharmacy/reservations/[^/]+',
      (r) => FakeResponse.json(
        200,
        orders.firstWhere((o) => r.path.endsWith(o['id'] as String)),
      ),
    );
  });

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(IviaBottomNav),
        matching: find.bySemanticsLabel(RegExp('^$label')),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('jour des sections : aujourd\'hui, hier, la date', () {
    final now = DateTime(2026, 11, 6, 10);
    expect(dayLabel(DateTime(2026, 11, 6, 1), now), "Aujourd'hui");
    expect(dayLabel(DateTime(2026, 11, 5, 23), now), 'Hier');
    expect(dayLabel(DateTime(2026, 11, 2, 9), now), '2 novembre');
  });

  testWidgets('Alertes (F21) : en cours, commandes, historique', (
    tester,
  ) async {
    await app.launch(tester);
    await tab(tester, 'Alertes');
    expect(find.text('En cours · 2'), findsOneWidget);
    expect(find.textContaining('2 produits'), findsNWidgets(2));

    await tapText(tester, 'Commandes');
    expect(find.text('#M-208'), findsOneWidget);
    expect(find.text('Mise de côté'), findsOneWidget);

    await tapText(tester, 'Historique');
    expect(find.text("AUJOURD'HUI"), findsOneWidget);
    expect(find.text('Répondue'), findsOneWidget);
    expect(find.textContaining('1 / 2 disponible'), findsOneWidget);
    expect(find.text('Expirée'), findsOneWidget);
    expect(find.textContaining('Non traitée'), findsOneWidget);
    expect(find.text('Ignorée'), findsOneWidget);
    expect(find.text('#M-211'), findsOneWidget);
    expect(find.text('Remise'), findsOneWidget);
  });

  testWidgets('Alertes vides : états vides', (tester) async {
    inbox = [];
    orders = [];
    await app.launch(tester);
    await tab(tester, 'Alertes');
    expect(find.textContaining('Aucune alerte en cours'), findsOneWidget);
    await tapText(tester, 'Commandes');
    expect(find.text('Aucune commande en cours.'), findsOneWidget);
    await tapText(tester, 'Historique');
    expect(find.textContaining('Rien pour le moment'), findsOneWidget);
  });

  testWidgets('onglet Commandes : en cours puis terminées, ouverture', (
    tester,
  ) async {
    await app.launch(tester);
    await tab(tester, 'Commandes');
    expect(find.text('EN COURS'), findsOneWidget);
    expect(find.text('TERMINÉES'), findsOneWidget);
    await tapText(tester, '#M-208');
    expect(find.text('Commande #M-208'), findsOneWidget);
  });

  testWidgets('onglet Commandes vide : état vide', (tester) async {
    orders = [];
    await app.launch(tester);
    await tab(tester, 'Commandes');
    expect(
      find.textContaining('Aucune commande pour le moment'),
      findsOneWidget,
    );
  });

  testWidgets('police à 200 % sur 320 dp : les onglets tiennent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await app.launch(tester);
    await tab(tester, 'Alertes');
    await tapText(tester, 'Historique');
    expect(tester.takeException(), isNull);
    await tab(tester, 'Commandes');
    expect(tester.takeException(), isNull);
  });
}
