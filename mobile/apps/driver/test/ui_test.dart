import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_driver/common/formats.dart';
import 'package:ivia_driver/common/ui.dart';
import 'package:ivia_driver/features/mission/navigation.dart';
import 'package:ivia_driver/features/splash/loading_screen.dart';
import 'package:ivia_ui/ivia_ui.dart';

// Spec 033, tâche 3 : composants d'Ivia Driver.

Future<void> _pump(WidgetTester tester, Widget child, {double width = 360}) {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: IviaTheme.light(IviaAppBrand.driver),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(D.gutter),
          child: Center(child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('glissière', () {
    testWidgets('relâchée avant le bout : revient, rien ne part', (
      tester,
    ) async {
      var calls = 0;
      await _pump(
        tester,
        DSlide(
          label: 'Glisser pour passer en ligne',
          onConfirmed: () async => calls++,
        ),
      );
      final knob = find.byKey(const Key('slide-knob'));
      final start = tester.getTopLeft(knob).dx;
      await tester.drag(knob, const Offset(150, 0));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(tester.getTopLeft(knob).dx, start);
    });

    testWidgets('amenée au bout : l\'action part une fois, puis retour', (
      tester,
    ) async {
      var calls = 0;
      await _pump(
        tester,
        DSlide(
          label: 'Glisser pour accepter',
          onConfirmed: () async => calls++,
        ),
      );
      final knob = find.byKey(const Key('slide-knob'));
      final start = tester.getTopLeft(knob).dx;
      await tester.drag(knob, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.getTopLeft(knob).dx, start);
    });

    testWidgets('inactive : le glissement ne fait rien', (tester) async {
      await _pump(
        tester,
        const DSlide(label: 'Glisser : colis récupéré', onConfirmed: null),
      );
      await tester.drag(
        find.byKey(const Key('slide-knob')),
        const Offset(400, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('lecteur d\'écran : un toucher suffit', (tester) async {
      final handle = tester.ensureSemantics();
      var calls = 0;
      await _pump(
        tester,
        DSlide(label: 'Glisser à l\'arrivée', onConfirmed: () async => calls++),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel("Glisser à l'arrivée")),
        matchesSemantics(
          label: 'Glisser à l\'arrivée',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('Glisser à l\'arrivée'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      handle.dispose();
    });
  });

  group('barre du bas', () {
    testWidgets('claire, onglet actif bleu avec libellé, autres en icône', (
      tester,
    ) async {
      var selected = -1;
      await _pump(
        tester,
        DBottomNav(
          tabs: DBottomNav.driverTabs,
          index: 0,
          onSelect: (i) => selected = i,
        ),
      );
      final bar = tester.widget<Container>(find.byKey(const Key('bottom-nav')));
      expect((bar.decoration! as BoxDecoration).color, Colors.white);
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Gains'), findsNothing);
      await tester.tap(find.byIcon(Icons.payments_outlined));
      expect(selected, 2);
      final active = tester.widget<Material>(
        find
            .ancestor(of: find.text('Accueil'), matching: find.byType(Material))
            .first,
      );
      expect(active.color, D.blue);
    });
  });

  group('code en cases', () {
    testWidgets('chiffres dans les cases, lus d\'un bloc', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const DCodeBoxes(
          '7319',
          style: DCodeStyle.dark,
          semanticLabel: 'Votre code de retrait',
        ),
      );
      for (final d in ['7', '3', '1', '9']) {
        expect(find.text(d), findsOneWidget);
      }
      expect(
        find.semantics.byLabel('Votre code de retrait : 7 3 1 9'),
        findsOne,
      );
      handle.dispose();
    });

    testWidgets('code incomplet : cases vides', (tester) async {
      await _pump(tester, const DCodeBoxes('48'));
      expect(find.byKey(const Key('code-box-3')), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
    });
  });

  testWidgets('police à 220 % sur 320 dp : composants sans débordement', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      width: 320,
      SingleChildScrollView(
        child: Column(
          children: [
            DSlide(
              label: 'Glisser pour passer en ligne',
              onConfirmed: () async {},
            ),
            const SizedBox(height: 8),
            const DCodeBoxes('4827'),
            const SizedBox(height: 8),
            DButton(label: 'Envoyer mon dossier', onTap: () {}),
            const SizedBox(height: 8),
            const DStep(
              title: 'Vérification par ivia',
              subtitle: 'En cours',
              state: DStepState.current,
            ),
            const SizedBox(height: 8),
            const DTitle('Le code du client', 'valide la livraison.'),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  group('formats', () {
    test('heure et jour de Lomé, quel que soit le fuseau', () {
      final t = DateTime.utc(2026, 11, 7, 23, 41);
      expect(hhmm(t), '23:41');
      expect(hhmm(t.toLocal()), '23:41');
      expect(
        lomeDay(DateTime.utc(2026, 11, 8, 0, 5)),
        DateTime.utc(2026, 11, 8),
      );
    });

    test('distances', () {
      expect(distance(800), '800 m');
      expect(distance(4230), '4,2 km');
      expect(distance(3000), '3 km');
      expect(distance(995), '1 km');
    });

    test('durées', () {
      expect(duration(const Duration(minutes: 12)), '12 min');
      expect(duration(const Duration(minutes: 72)), '1 h 12');
      expect(duration(const Duration(minutes: 125)), '2 h 05');
      expect(duration(const Duration(hours: 2)), '2 h');
      expect(duration(const Duration(seconds: 20)), '1 min');
    });

    test('salutation et initiales', () {
      expect(greeting(DateTime.utc(2026, 11, 8, 9)), 'Bonjour');
      expect(greeting(DateTime.utc(2026, 11, 8, 23, 24)), 'Bonsoir');
      expect(initials('Kossi Adjo'), 'KA');
      expect(initials('  awa  '), 'A');
    });
  });

  testWidgets('lancement (D00) : police à 200 % sur 320 dp', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const MaterialApp(home: LoadingScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  test('lien d\'appel : chiffres et « + » seulement', () {
    expect(telUri('+228 90 11-22-33').toString(), 'tel:+22890112233');
    expect(telUri('+22890000000').toString(), 'tel:+22890000000');
  });
}
