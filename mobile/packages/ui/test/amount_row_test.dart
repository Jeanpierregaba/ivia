import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required String label,
    required String amount,
    double scale = 1,
    bool strong = false,
  }) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: IviaTheme.light(IviaAppBrand.buyer),
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: Scaffold(
            body: Padding(
              // Comme une carte dans un écran : 2 × 16 + 2 × 16.
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  IviaAmountRow(label: label, amount: amount, strong: strong),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('taille normale : montant à droite, nom long à la ligne', (
    tester,
  ) async {
    await pump(
      tester,
      label: '2 × Pagne wax hollandais grand format six yards',
      amount: '25 000 F',
    );
    expect(tester.takeException(), isNull);
    final label = tester.getRect(find.textContaining('Pagne'));
    final amount = tester.getRect(find.text('25 000 F'));
    expect(amount.left, greaterThan(label.right));
    expect(amount.top, label.top);
  });

  for (final scale in [1.3, 1.5, 2.0]) {
    testWidgets('gros montant à ${(scale * 100).round()} % sur 320 dp : '
        'rien ne déborde', (tester) async {
      await pump(
        tester,
        label: 'Vous recevez',
        amount: '1 250 000 F',
        scale: scale,
        strong: true,
      );
      expect(tester.takeException(), isNull);
      // Sous le libellé si la place manque ; jamais hors de l'écran.
      expect(tester.getRect(find.text('1 250 000 F')).right, lessThan(320));
    });
  }

  testWidgets('police à 200 % : montant sous le libellé', (tester) async {
    await pump(tester, label: 'Produits', amount: '10 500 F', scale: 2);
    final label = tester.getRect(find.text('Produits'));
    final amount = tester.getRect(find.text('10 500 F'));
    expect(amount.top, greaterThanOrEqualTo(label.bottom));
  });
}
