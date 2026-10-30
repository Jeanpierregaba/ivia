import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_seller/main.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  testWidgets("l'app démarre avec le thème ivia", (tester) async {
    await tester.pumpWidget(const SellerApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'ivia Marchand');
    expect(app.theme?.colorScheme.primary, IviaColors.primary);
    expect(find.text('MARCHAND'), findsOneWidget);
  });
}
