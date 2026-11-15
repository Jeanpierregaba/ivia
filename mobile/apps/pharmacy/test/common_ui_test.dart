import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_pharmacy/common/ui.dart';
import 'package:ivia_ui/ivia_ui.dart';

Future<void> _show(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: IviaTheme.light(IviaAppBrand.pharmacy),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('compte à rebours : temps restant, puis « Terminée »', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 6, 10);
    var expired = 0;
    await _show(
      tester,
      PCountdownPill(
        deadline: DateTime(2026, 11, 6, 10, 2, 5),
        now: () => now,
        onExpired: () => expired++,
        suffix: 'pour répondre',
      ),
    );
    expect(find.text('02:05 pour répondre'), findsOneWidget);
    now = DateTime(2026, 11, 6, 10, 3);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Terminée'), findsOneWidget);
    expect(expired, 1);
    final text = tester.widget<Text>(find.text('Terminée'));
    expect(text.style?.color, P.red);
  });

  testWidgets('bouton sans action : gris, rien ne se passe', (tester) async {
    await _show(tester, const PButton(label: 'Valider', onTap: null));
    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(button.onPressed, isNull);
    expect(
      button.style?.backgroundColor?.resolve({}),
      IviaPharmacyColors.disabled,
    );
  });

  testWidgets('bouton occupé : indicateur, un seul envoi', (tester) async {
    var taps = 0;
    await _show(
      tester,
      PButton(label: 'Envoyer', busy: true, onTap: () => taps++),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    expect(taps, 0);
  });

  testWidgets('case à cocher : bascule et lue comme cochée', (tester) async {
    var value = false;
    await _show(
      tester,
      StatefulBuilder(
        builder: (context, setState) => PCheckRow(
          value: value,
          label: 'Je certifie',
          onChanged: (v) => setState(() => value = v),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    await tester.tap(find.text('Je certifie'));
    await tester.pump();
    expect(value, isTrue);
    expect(
      tester.getSemantics(find.text('Je certifie')),
      isSemantics(
        label: 'Je certifie',
        hasCheckedState: true,
        isChecked: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('interrupteur : bascule ; sans action, il ne bouge pas', (
    tester,
  ) async {
    var value = false;
    await _show(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PSwitch(
              key: const Key('on'),
              value: value,
              label: 'En service',
              onChanged: (v) => setState(() => value = v),
            ),
            const PSwitch(key: Key('off'), value: false, onChanged: null),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('on')));
    await tester.pump();
    expect(value, isTrue);
    await tester.tap(find.byKey(const Key('off')));
    await tester.pump();
  });

  testWidgets('en-tête : retour vers l\'écran précédent, étape lue', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: PHeader(
                    title: 'Votre pharmacie',
                    trailing: PStepPill(step: 1, of: 5),
                  ),
                ),
              ),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('1 sur 5'), findsOneWidget);
    expect(find.bySemanticsLabel('Étape 1 sur 5'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Votre pharmacie'), findsNothing);
  });

  testWidgets('police à 200 % sur 320 dp : en-tête et barre du bas tiennent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: IviaTheme.light(IviaAppBrand.pharmacy),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              const PHeader(
                title: 'Votre pharmacie',
                trailing: PStepPill(step: 3, of: 5),
              ),
              const Spacer(),
              PBottomBar(
                children: [
                  PButton(
                    label: 'Ignorer',
                    style: PButtonStyle.outline,
                    onTap: () {},
                  ),
                  PButton(label: 'Répondre', onTap: () {}),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
