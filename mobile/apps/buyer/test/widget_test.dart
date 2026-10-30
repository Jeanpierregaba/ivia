import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_buyer/main.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  testWidgets("l'app démarre avec le thème ivia", (tester) async {
    await tester.pumpWidget(const BuyerApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'ivia');
    expect(app.theme?.colorScheme.primary, IviaColors.primary);
    expect(find.text('ACHETEUR'), findsOneWidget);
  });
}
