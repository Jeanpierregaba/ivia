import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_pharmacy/features/alerts/prescription_viewer.dart';
import 'package:ivia_pharmacy/features/security/secure_screen.dart';

import 'helpers.dart';

void main() {
  late PharmacyHarness app;
  late Map<String, dynamic> alert;
  late List<String> secureCalls;

  setUp(() async {
    PharmacyHarness.resetDevice();
    app = PharmacyHarness();
    alert = alertBody(
      id: 'a1',
      note: 'Le sirop plutôt que les comprimés si possible.',
      photos: [
        {'kind': 'prescription', 'url': null},
        {'kind': 'prescription', 'url': null},
      ],
    );
    await app.signInApproved(inbox: () => [alert]);
    app.server
      ..on('GET', '/v1/pharmacy/inbox/a1', (_) => FakeResponse.json(200, alert))
      ..on('POST', '/v1/pharmacy/inbox/a1/decline', (_) {
        alert = {...alert, 'status': 'declined'};
        return FakeResponse.json(200, {});
      });
    secureCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecureScreen.channel, (call) async {
          secureCalls.add(call.method);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecureScreen.channel, null);
  });

  Future<void> openDetail(WidgetTester tester) async {
    await app.launch(tester);
    await tapText(tester, 'Voir');
  }

  testWidgets('détail : ordonnance, produits, générique, précision, anonymat', (
    tester,
  ) async {
    await openDetail(tester);
    expect(app.server.calls('GET', '/v1/pharmacy/inbox/a1'), isNotEmpty);
    expect(find.textContaining('Alerte de '), findsOneWidget);
    expect(find.textContaining(':'), findsWidgets);
    expect(find.text('Ordonnance · 2 pages'), findsOneWidget);
    expect(find.text('Touchez pour agrandir'), findsOneWidget);
    expect(find.text('Produits demandés'), findsOneWidget);
    expect(find.text('Paracétamol 1000 mg'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('Générique accepté'), findsOneWidget);
    expect(
      find.text('« Le sirop plutôt que les comprimés si possible. »'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('Client anonyme'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('Client anonyme'), findsOneWidget);
    expect(find.text('Ignorer'), findsOneWidget);
    expect(find.text('Répondre'), findsOneWidget);
  });

  testWidgets('sans photo : pas de carte Ordonnance', (tester) async {
    alert = alertBody(id: 'a1');
    await openDetail(tester);
    expect(find.textContaining('Ordonnance ·'), findsNothing);
  });

  testWidgets('« Ignorer » refuse l\'alerte et revient', (tester) async {
    await openDetail(tester);
    await tapText(tester, 'Ignorer');
    expect(
      app.server.calls('POST', '/v1/pharmacy/inbox/a1/decline'),
      hasLength(1),
    );
    expect(find.text('Alertes à traiter'), findsOneWidget);
  });

  testWidgets('« Répondre » ouvre la réponse', (tester) async {
    await openDetail(tester);
    await tapText(tester, 'Répondre');
    expect(find.text('Votre réponse, produit par produit'), findsOneWidget);
  });

  testWidgets('alerte terminée : ni « Ignorer » ni « Répondre »', (
    tester,
  ) async {
    await openDetail(tester);
    alert = alertBody(id: 'a1', endsIn: const Duration(minutes: -2));
    await tester.fling(find.byType(ListView).last, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.textContaining('Alerte terminée'), findsOneWidget);
    expect(find.text('Ignorer'), findsNothing);
    expect(find.text('Répondre'), findsNothing);
    expect(find.text('Retour'), findsOneWidget);
  });

  testWidgets('ordonnance en grand : pages, zoom, pivot, capture bloquée', (
    tester,
  ) async {
    await openDetail(tester);
    await tapText(tester, 'Ordonnance · 2 pages');
    expect(find.text('Page 1 sur 2'), findsOneWidget);
    expect(secureCalls, ['enable']);
    expect(find.textContaining("Capture d'écran désactivée"), findsOneWidget);
    expect(find.text('100 %'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Agrandir'));
    await tester.pumpAndSettle();
    expect(find.text('150 %'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Réduire'));
    await tester.pumpAndSettle();
    expect(find.text('100 %'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Pivoter'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<RotatedBox>(find.byType(RotatedBox).first).quarterTurns,
      1,
    );

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Page 2 sur 2'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Fermer'));
    await tester.pumpAndSettle();
    expect(secureCalls, ['enable', 'disable']);
  });

  testWidgets('iOS : rien n\'est annoncé ni demandé', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      const MaterialApp(home: PrescriptionViewer(photos: [])),
    );
    expect(find.textContaining("Capture d'écran"), findsNothing);
    expect(find.text("Photo supprimée 24 h après l'alerte"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(secureCalls, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('photo au lien expiré : le détail est relu', (tester) async {
    alert = alertBody(
      id: 'a1',
      photos: [
        {'kind': 'prescription', 'url': 'https://stockage.test/rx.jpg?sig=x'},
      ],
    );
    await openDetail(tester);
    await tester.pumpAndSettle();
    expect(
      app.server.calls('GET', '/v1/pharmacy/inbox/a1').length,
      greaterThan(1),
    );
  });

  testWidgets('police à 200 % sur 320 dp : le détail tient', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openDetail(tester);
    expect(tester.takeException(), isNull);
  });
}
