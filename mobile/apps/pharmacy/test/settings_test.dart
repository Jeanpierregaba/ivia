import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_pharmacy/common/ui.dart';
import 'package:ivia_pharmacy/features/planning/planning_screen.dart';
import 'package:ivia_pharmacy/features/profile/alert_sound.dart';
import 'package:ivia_pharmacy/features/profile/profile_tab.dart';
import 'package:ivia_pharmacy/features/push/push.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  late PharmacyHarness app;
  late List<Map<String, dynamic>> shifts;
  late List<Map<String, dynamic>> orders;

  setUp(() async {
    PharmacyHarness.resetDevice();
    app = PharmacyHarness();
    final now = DateTime.now();
    // Garde le jour même à Lomé, quelle que soit l'heure du test.
    final start = lomeDay(now).add(const Duration(minutes: 30));
    shifts = [
      {
        'id': 's1',
        'starts_at': start.toIso8601String(),
        'ends_at': start.add(const Duration(hours: 12)).toIso8601String(),
      },
    ];
    orders = [
      {
        ...orderBody(id: 'o9', delivery: true, status: 'completed'),
        'number': 'M-211',
        'items_xof': 3950,
        'pharmacy_due_xof': 3950,
        'completed_at': now.toUtc().toIso8601String(),
      },
      orderBody(id: 'o8', status: 'completed'),
    ];
    await app.signInApproved(orders: () => orders);
    app.server
      ..on(
        'GET',
        '/v1/pharmacy/me/duty-shifts',
        (_) => FakeResponse.json(200, {'items': shifts}),
      )
      ..on(
        'POST',
        '/v1/pharmacy/me/duty-shifts',
        (_) => FakeResponse.json(201, {}),
      )
      ..on(
        'PUT',
        '/v1/pharmacy/me/night-hours',
        (_) => FakeResponse.json(200, {}),
      )
      ..on(
        'PATCH',
        '/v1/pharmacy/me',
        (_) => FakeResponse.json(200, pharmacyBody(status: 'approved')),
      )
      ..on(
        'PUT',
        '/v1/pharmacy/me/status',
        (_) => FakeResponse.json(200, pharmacyBody(status: 'approved')),
      )
      ..on('POST', '/v1/auth/logout', (_) => FakeResponse.json(204, null))
      ..on('DELETE', '/v1/me/devices', (_) => FakeResponse.json(204, null))
      ..on(
        'GET',
        '/v1/pharmacy/earnings',
        (_) => FakeResponse.json(200, {
          'due_xof': 3950,
          'paid_out_xof': 0,
          'balance_xof': 3950,
          'delivered_count': 1,
          'pickup_count': 1,
          'payouts': <Object>[],
        }),
      );
  });

  Future<void> openProfile(WidgetTester tester) async {
    await app.launch(tester);
    await tester.tap(find.bySemanticsLabel('Profil'));
    await tester.pumpAndSettle();
  }

  test('prochaine garde : en cours, ce soir, demain, la date', () {
    final now = DateTime.utc(2026, 11, 6, 10);
    ({String id, DateTime startsAt, DateTime endsAt}) at(DateTime start) => (
      id: 's',
      startsAt: start,
      endsAt: start.add(const Duration(hours: 12)),
    );
    expect(nextDutyLabel(const [], now), 'Aucune garde prévue');
    expect(
      nextDutyLabel([at(DateTime.utc(2026, 11, 6, 8))], now),
      'De garde maintenant',
    );
    expect(
      nextDutyLabel([at(DateTime.utc(2026, 11, 6, 20))], now),
      'Prochaine garde : ce soir',
    );
    expect(
      nextDutyLabel([at(DateTime.utc(2026, 11, 7, 20))], now),
      'Prochaine garde : demain',
    );
    expect(
      nextDutyLabel([at(DateTime.utc(2026, 11, 12, 20))], now),
      'Prochaine garde : le 12 novembre',
    );
  });

  test('sonnerie : canal sonore ou canal muet', () {
    final loud = alertNotificationDetails(loud: true);
    final quiet = alertNotificationDetails(loud: false);
    expect(loud.android!.channelId, alertChannelId);
    expect(loud.android!.fullScreenIntent, isTrue);
    expect(quiet.android!.channelId, quietAlertChannelId);
    expect(quiet.android!.playSound, isFalse);
    expect(quiet.iOS!.presentSound, isFalse);
  });

  test('import : une garde par ligne, ligne illisible signalée', () {
    final ok = parseShiftList('08/11/2026 20:00 07:00\n15/11/2026 20h00 07h00');
    expect(ok.badLine, isNull);
    expect(ok.shifts, hasLength(2));
    expect(ok.shifts.first.startsAt, DateTime.utc(2026, 11, 8, 20));
    expect(ok.shifts.first.endsAt, DateTime.utc(2026, 11, 9, 7));
    expect(parseShiftList('08/11/2026 20:00 07:00\nlundi soir').badLine, 2);
  });

  testWidgets('profil : informations, planning, relevé, documents', (
    tester,
  ) async {
    await openProfile(tester);
    expect(find.text('Pharmacie du Boulevard'), findsOneWidget);
    expect(find.text('Validée'), findsOneWidget);
    final parsed = [
      for (final m in shifts)
        (
          id: m['id'] as String,
          startsAt: DateTime.parse(m['starts_at'] as String),
          endsAt: DateTime.parse(m['ends_at'] as String),
        ),
    ];
    expect(find.text(nextDutyLabel(parsed, DateTime.now())), findsOneWidget);
    expect(find.text('${formatXof(3950)} à recevoir'), findsOneWidget);

    await tapText(tester, 'Planning de garde');
    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('Garde de nuit'), findsOneWidget);
    expect(find.text('Service de jour'), findsOneWidget);
    expect(find.textContaining('En journée, les alertes'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Ajouter une garde'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Ajouter');
    expect(
      app.server.calls('POST', '/v1/pharmacy/me/duty-shifts'),
      hasLength(1),
    );
    await tapText(tester, 'Heures de nuit');
    await tapText(tester, 'Enregistrer');
    expect(app.server.calls('PUT', '/v1/pharmacy/me/night-hours').single.body, {
      'night_from_hour': 20,
      'night_to_hour': 8,
    });
    await tester.tap(find.bySemanticsLabel('Retour'));
    await tester.pumpAndSettle();

    await tapText(tester, 'Relevé des versements');
    expect(find.text('Relevé'), findsOneWidget);
    expect(find.text('0 % de commission'), findsOneWidget);
    expect(find.text('#M-211'), findsOneWidget);
    // Retrait payé au comptoir : absent du relevé.
    expect(find.text('#M-208'), findsNothing);
    expect(find.text('Compte de versement'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Retour'));
    await tester.pumpAndSettle();

    await tapText(tester, 'Documents');
    expect(find.text("Autorisation d'exercice"), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Retour'));
    await tester.pumpAndSettle();

    await tapText(tester, 'Informations');
    await tester.enterText(fieldOf('Horaires'), 'Tous les jours 8 h - 22 h');
    await tapText(tester, 'Enregistrer');
    expect(app.server.calls('PATCH', '/v1/pharmacy/me').single.body, {
      'phone': '+22822214567',
      'opening_hours': 'Tous les jours 8 h - 22 h',
    });
    await tester.tap(find.byType(PSwitch).first);
    await tester.pumpAndSettle();
    expect(app.server.calls('PUT', '/v1/pharmacy/me/status').single.body, {
      'is_open': true,
      'on_duty': false,
      'open_24h': true,
    });
  });

  testWidgets('sonnerie coupée : mémorisée sur ce téléphone', (tester) async {
    await openProfile(tester);
    expect(find.text('Forte · répétée'), findsOneWidget);
    await tapText(tester, 'Sonnerie des alertes');
    expect(find.text('Coupée · notification seule'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(alertSoundKey), isFalse);
    expect(await readAlertSound(), isFalse);
  });

  testWidgets('déconnexion : l\'appareil quitte d\'abord le push', (
    tester,
  ) async {
    await openProfile(tester);
    await tapText(tester, 'Se déconnecter');
    expect(app.server.calls('POST', '/v1/auth/logout'), hasLength(1));
    expect(find.text('Espace pharmacie'), findsOneWidget);
  });

  testWidgets('police à 200 % sur 320 dp : profil et planning tiennent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openProfile(tester);
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Planning de garde');
    expect(tester.takeException(), isNull);
    expect(find.byType(IviaLogo), findsNothing);
  });

  testWidgets('police à 200 % sur 320 dp : relevé et informations tiennent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openProfile(tester);
    await tapText(tester, 'Relevé des versements');
    expect(tester.takeException(), isNull);
    await tester.tap(find.bySemanticsLabel('Retour'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Informations');
    expect(tester.takeException(), isNull);
  });
}
