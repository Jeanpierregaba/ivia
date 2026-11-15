import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_pharmacy/features/push/push.dart';
import 'package:ivia_pharmacy/main.dart';

import 'helpers.dart';

void main() {
  late PharmacyHarness app;
  late List<Map<String, dynamic>> inbox;

  setUp(() async {
    PharmacyHarness.resetDevice();
    app = PharmacyHarness();
    inbox = [];
    await app.signInApproved(inbox: () => inbox);
    app.server
      ..onPattern(
        'GET',
        '/v1/pharmacy/inbox/[^/]+',
        (r) => FakeResponse.json(
          200,
          inbox.firstWhere((a) => r.path.endsWith('/${a['alert_id']}')),
        ),
      )
      ..onPattern('POST', '/v1/pharmacy/inbox/[^/]+/decline', (r) {
        inbox = [
          for (final a in inbox)
            r.path.contains('/${a['alert_id']}/')
                ? {...a, 'status': 'declined'}
                : a,
        ];
        return FakeResponse.json(200, {});
      });
  });

  PushManager push(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PharmacyApp)))
          .read(pushProvider);

  Future<void> poll(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('nouvelle alerte à la relecture : plein écran, une seule fois', (
    tester,
  ) async {
    await app.launch(tester);
    expect(find.text('ALERTE MÉDICAMENT'), findsNothing);
    inbox = [
      alertBody(
        id: 'a9',
        photos: [
          {'kind': 'prescription', 'url': null},
        ],
      ),
    ];
    await poll(tester);
    expect(find.text('ALERTE MÉDICAMENT'), findsOneWidget);
    expect(find.text('2 produits demandés'), findsOneWidget);
    expect(find.textContaining('ordonnance jointe'), findsOneWidget);
    expect(find.textContaining('pour répondre'), findsOneWidget);

    await tapText(tester, "Voir l'alerte");
    expect(find.text('ALERTE MÉDICAMENT'), findsNothing);
    expect(app.server.calls('GET', '/v1/pharmacy/inbox/a9'), isNotEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await poll(tester);
    // Déjà montrée : pas une deuxième fois.
    expect(find.text('ALERTE MÉDICAMENT'), findsNothing);
  });

  testWidgets('alertes déjà là au lancement : pas de plein écran', (
    tester,
  ) async {
    inbox = [alertBody(id: 'a1')];
    await app.launch(tester);
    await poll(tester);
    expect(find.text('ALERTE MÉDICAMENT'), findsNothing);
  });

  testWidgets('« Ignorer » refuse l\'alerte', (tester) async {
    await app.launch(tester);
    inbox = [alertBody(id: 'a9')];
    await poll(tester);
    await tapText(tester, 'Ignorer');
    expect(
      app.server.calls('POST', '/v1/pharmacy/inbox/a9/decline'),
      hasLength(1),
    );
    expect(find.text('ALERTE MÉDICAMENT'), findsNothing);
    expect(find.text('Alertes à traiter'), findsOneWidget);
  });

  testWidgets('push reçu app ouverte, puis notification touchée', (
    tester,
  ) async {
    await app.launch(tester);
    inbox = [alertBody(id: 'a9')];
    push(tester).onAlertReceived!('a9');
    await tester.pumpAndSettle();
    expect(find.text('ALERTE MÉDICAMENT'), findsOneWidget);
    // Retour Android.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Même alerte : le push app ouverte ne la remontre pas…
    push(tester).onAlertReceived!('a9');
    await tester.pumpAndSettle();
    expect(find.text('ALERTE MÉDICAMENT'), findsNothing);
    // … mais la notification touchée, si.
    push(tester).onOpenAlert!('a9');
    await tester.pumpAndSettle();
    expect(find.text('ALERTE MÉDICAMENT'), findsOneWidget);
  });

  testWidgets(
    'alerte expirée ouverte par la notification : « Alerte terminée »',
    (tester) async {
      inbox = [alertBody(id: 'a8', endsIn: const Duration(minutes: -1))];
      await app.launch(tester);
      push(tester).onOpenAlert!('a8');
      await tester.pumpAndSettle();
      expect(find.textContaining('Alerte terminée'), findsOneWidget);
      expect(find.text("Voir l'alerte"), findsNothing);
      await tapText(tester, 'Fermer');
      expect(find.text('Alertes à traiter'), findsOneWidget);
    },
  );

  testWidgets('alerte inconnue : « Alerte terminée »', (tester) async {
    await app.launch(tester);
    push(tester).onOpenAlert!('zz');
    await tester.pumpAndSettle();
    expect(find.text('Alerte terminée'), findsOneWidget);
  });

  testWidgets('police à 200 % sur 320 dp : le plein écran tient', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await app.launch(tester);
    inbox = [alertBody(id: 'a9')];
    await poll(tester);
    expect(find.text('ALERTE MÉDICAMENT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
