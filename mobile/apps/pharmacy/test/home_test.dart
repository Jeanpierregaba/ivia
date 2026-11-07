import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_pharmacy/common/ui.dart';
import 'package:ivia_pharmacy/features/alerts/alert_logic.dart';
import 'package:ivia_pharmacy/features/home/home_tab.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'helpers.dart';

void main() {
  late PharmacyHarness app;
  late Map<String, dynamic> profile;
  late List<Map<String, dynamic>> inbox;
  late List<Map<String, dynamic>> orders;

  setUp(() async {
    PharmacyHarness.resetDevice();
    app = PharmacyHarness();
    profile = pharmacyBody(
      status: 'approved',
      payout: true,
      onDuty: true,
      documents: ['opening_authorization', 'owner_id', 'storefront_photo'],
    );
    inbox = [
      alertBody(id: 'a1'),
      alertBody(id: 'a2', seen: true, endsIn: const Duration(minutes: 5)),
      alertBody(id: 'a3', responded: true),
      alertBody(id: 'a4', responded: true, unlocked: true),
      alertBody(
        id: 'a5',
        receivedAgo: const Duration(days: 2),
        status: 'expired',
      ),
    ];
    orders = [orderBody()];
    await app.signInApproved(
      profile: () => profile,
      inbox: () => inbox,
      orders: () => orders,
    );
    app.server.on('PUT', '/v1/pharmacy/me/status', (r) {
      profile = {...profile, ...(r.body as Map<String, dynamic>)};
      return FakeResponse.json(200, profile);
    });
  });

  test('chiffres du jour : reçues, répondues, confirmées', () {
    final now = DateTime.utc(2026, 11, 6, 10);
    InboxAlert at(Map<String, dynamic> j, DateTime received) =>
        InboxAlert.fromJson({...j, 'received_at': received.toIso8601String()});
    final today = DateTime.utc(2026, 11, 6, 0, 5);
    final stats = todayStats([
      at(alertBody(id: 'a1'), today),
      at(alertBody(id: 'a2', responded: true), today),
      at(alertBody(id: 'a3', responded: true, unlocked: true), today),
      at(
        alertBody(id: 'a4', responded: true),
        DateTime.utc(2026, 11, 5, 23, 59),
      ),
    ], now);
    expect(stats.received, 3);
    expect(stats.responded, 2);
    expect(stats.confirmed, 1);
  });

  test('ligne de garde : garde en cours, sinon ouverture', () {
    final now = DateTime.utc(2026, 11, 6, 22);
    final shift = (
      id: 's1',
      startsAt: DateTime.utc(2026, 11, 6, 20),
      endsAt: DateTime.utc(2026, 11, 7, 8),
    );
    PharmacyProfile p(Map<String, dynamic> j) => PharmacyProfile.fromJson(j);
    expect(dutyLine(p(profile), [shift], now), 'De garde · 20:00 → 08:00');
    expect(dutyLine(p(pharmacyBody()), const [], now), 'En service');
    expect(
      dutyLine(p(pharmacyBody(isOpen: false)), const [], now),
      'Hors service',
    );
    expect(
      dutyLine(p(pharmacyBody(open24h: true)), const [], now),
      'Ouverte 24 h/24',
    );
  });

  testWidgets('accueil : nom, interrupteur, chiffres, alertes, commandes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await app.launch(tester);
    expect(find.text('Pharmacie du Boulevard'), findsOneWidget);
    expect(find.text('En service'), findsOneWidget);
    expect(find.text('Vous recevez les alertes'), findsOneWidget);
    expect(find.bySemanticsLabel('4 Alertes'), findsOneWidget);
    expect(find.bySemanticsLabel('2 Répondues'), findsOneWidget);
    expect(find.bySemanticsLabel('1 Confirmées'), findsOneWidget);
    // Deux alertes ouvertes, une seule pas encore vue.
    expect(find.byType(AlertCard), findsNWidgets(2));
    expect(find.text('Nouvelle'), findsOneWidget);
    expect(find.textContaining('2 produits · client à 650'), findsNWidgets(2));
    expect(find.text('1 commande à préparer'), findsOneWidget);

    // La barre : pilule verte « Accueil », pastille d'une alerte non vue.
    expect(find.bySemanticsLabel('Alertes, 1 nouvelle'), findsOneWidget);

    await tester.tap(find.byType(PSwitch).first);
    await tester.pumpAndSettle();
    expect(app.server.calls('PUT', '/v1/pharmacy/me/status').single.body, {
      'is_open': false,
      'on_duty': true,
      'open_24h': false,
    });
    expect(find.text('Hors service'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('« Tout voir » et la carte des commandes ouvrent leurs onglets', (
    tester,
  ) async {
    await app.launch(tester);
    await tapText(tester, 'Tout voir');
    expect(
      tester.widget<IviaBottomNav>(find.byType(IviaBottomNav)).currentIndex,
      1,
    );
    await tester.tap(find.bySemanticsLabel('Accueil'));
    await tester.pumpAndSettle();
    await tapText(tester, '1 commande à préparer');
    expect(
      tester.widget<IviaBottomNav>(find.byType(IviaBottomNav)).currentIndex,
      2,
    );
  });

  testWidgets('aucune alerte : état vide', (tester) async {
    inbox = [];
    orders = [];
    await app.launch(tester);
    expect(find.textContaining('Aucune alerte à traiter'), findsOneWidget);
    expect(find.textContaining('à préparer'), findsNothing);
  });

  testWidgets('réseau coupé : message et « Tirer pour réessayer »', (
    tester,
  ) async {
    app.server.on(
      'GET',
      '/v1/pharmacy/inbox',
      (_) => FakeResponse.error(503, 'unavailable', 'Service indisponible.'),
    );
    await app.launch(tester);
    expect(find.text('Service indisponible.'), findsOneWidget);
    expect(find.text('Tirer pour réessayer'), findsOneWidget);
  });

  testWidgets('police à 200 % sur 320 dp : l\'accueil tient', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await app.launch(tester);
    expect(tester.takeException(), isNull);
  });
}
