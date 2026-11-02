import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  late DateTime clock;
  late int expired;
  final deadline = DateTime.utc(2026, 11, 2, 14, 15);

  setUp(() {
    clock = DateTime.utc(2026, 11, 2, 14, 2, 20);
    expired = 0;
  });

  Future<void> pump(
    WidgetTester tester, {
    String Function(String)? label,
    DateTime? at,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: IviaTheme.light(IviaAppBrand.seller),
      home: Scaffold(
        body: IviaCountdown(
          deadline: at ?? deadline,
          now: () => clock,
          onExpired: () => expired++,
          label: label,
        ),
      ),
    ),
  );

  Color colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  test('format : minutes et secondes, arrondies au-dessus', () {
    expect(
      IviaCountdown.format(const Duration(minutes: 12, seconds: 40)),
      '12:40',
    );
    expect(
      IviaCountdown.format(const Duration(seconds: 59, milliseconds: 1)),
      '1:00',
    );
    expect(IviaCountdown.format(const Duration(milliseconds: 300)), '0:01');
    expect(IviaCountdown.format(Duration.zero), '0:00');
    expect(IviaCountdown.format(const Duration(seconds: -5)), '0:00');
  });

  testWidgets('défile chaque seconde, en warning puis error sous 3 min', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('12:40'), findsOneWidget);
    expect(colorOf(tester, '12:40'), IviaColors.warning);

    clock = clock.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('12:39'), findsOneWidget);

    clock = deadline.subtract(const Duration(minutes: 3, seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(colorOf(tester, '3:01'), IviaColors.warning);
    clock = deadline.subtract(const Duration(minutes: 2, seconds: 59));
    await tester.pump(const Duration(seconds: 1));
    expect(colorOf(tester, '2:59'), IviaColors.error);
    expect(expired, 0);
  });

  testWidgets('à zéro : « Délai dépassé », onExpired une seule fois', (
    tester,
  ) async {
    await pump(tester);
    clock = deadline;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Délai dépassé'), findsOneWidget);
    expect(colorOf(tester, 'Délai dépassé'), IviaColors.error);
    expect(expired, 1);
    clock = clock.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(expired, 1);
  });

  testWidgets('délai déjà passé à l\'affichage : onExpired aussitôt', (
    tester,
  ) async {
    clock = deadline.add(const Duration(minutes: 1));
    await pump(tester);
    await tester.pump();
    expect(find.text('Délai dépassé'), findsOneWidget);
    expect(expired, 1);
  });

  testWidgets('nouveau délai : le compte reprend et peut réexpirer', (
    tester,
  ) async {
    clock = deadline;
    await pump(tester);
    await tester.pump();
    expect(expired, 1);
    await pump(tester, at: deadline.add(const Duration(minutes: 1)));
    expect(find.text('1:00'), findsOneWidget);
    clock = deadline.add(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(expired, 2);
  });

  testWidgets('texte autour et lecture à la minute près', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, label: (t) => 'Il vous reste $t pour répondre');
    expect(find.text('Il vous reste 12:40 pour répondre'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Il vous reste 13 min pour répondre'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('défaut : lu « Il reste N min »', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    expect(find.bySemanticsLabel('Il reste 13 min'), findsOneWidget);
    semantics.dispose();
  });
}
