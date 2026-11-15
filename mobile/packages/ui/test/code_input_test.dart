import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  late TextEditingController controller;
  late List<String> completed;

  setUp(() {
    controller = TextEditingController();
    completed = [];
  });

  Future<void> pumpInput(WidgetTester tester, {bool hasError = false}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: IviaTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: IviaCodeInput(
                controller: controller,
                hasError: hasError,
                onCompleted: completed.add,
              ),
            ),
          ),
        ),
      );

  List<String> boxes(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(IviaCodeInput),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data ?? '')
      .toList();

  testWidgets('chaque chiffre dans sa case, fin signalée une fois', (
    tester,
  ) async {
    await pumpInput(tester);
    await tester.enterText(find.byType(TextField), '481');
    await tester.pump();
    expect(boxes(tester), ['4', '8', '1', '', '', '']);
    expect(completed, isEmpty);

    await tester.enterText(find.byType(TextField), '481902');
    await tester.pump();
    expect(boxes(tester), ['4', '8', '1', '9', '0', '2']);
    // Déplacer le curseur ne redéclenche pas la fin.
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    expect(completed, ['481902']);
  });

  testWidgets('collage : espaces et lettres retirés, 6 chiffres gardés', (
    tester,
  ) async {
    await pumpInput(tester);
    await tester.enterText(find.byType(TextField), 'Code : 481 902 77');
    await tester.pump();
    expect(controller.text, '481902');
    expect(completed, ['481902']);
  });

  testWidgets('effacement arrière', (tester) async {
    await pumpInput(tester);
    await tester.enterText(find.byType(TextField), '4819');
    await tester.enterText(find.byType(TextField), '481');
    await tester.pump();
    expect(boxes(tester), ['4', '8', '1', '', '', '']);
  });

  testWidgets('annoncé « Code à 6 chiffres », clavier numérique', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpInput(tester);
    expect(find.bySemanticsLabel(RegExp('Code à 6 chiffres')), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.keyboardType, TextInputType.number);
    expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
    semantics.dispose();
  });

  testWidgets('erreur : cases encadrées en rouge', (tester) async {
    await pumpInput(tester, hasError: true);
    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(IviaCodeInput),
            matching: find.byType(Container),
          )
          .first,
    );
    final border = (box.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, IviaColors.error);
  });

  testWidgets('police à 200 % sur 320 dp : pas de débordement', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpInput(tester);
    await tester.enterText(find.byType(TextField), '888888');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
