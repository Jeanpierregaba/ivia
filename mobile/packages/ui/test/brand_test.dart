import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  test('couleurs des apps (maquettes du splash)', () {
    expect(IviaAppBrand.buyer.accent, const Color(0xFFED1C2F));
    expect(IviaAppBrand.seller.accent, const Color(0xFF0E2E54));
    expect(IviaAppBrand.driver.accent, const Color(0xFF004DA8));
  });

  for (final color in IviaLogoColor.values) {
    testWidgets('logotype ${color.name} : image présente et proportions', (
      tester,
    ) async {
      // Lève une erreur si le fichier manque ou n'est pas déclaré.
      final data = await rootBundle.load('packages/ivia_ui/${color.asset}');
      expect(data.lengthInBytes, greaterThan(0));

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: IviaLogo(color: color, height: 40)),
        ),
      );
      final size = tester.getSize(find.byType(Image));
      expect(size.height, 40);
      expect(size.width, closeTo(40 * IviaLogo.aspectRatio, 0.01));
    });
  }

  testWidgets('le logotype est annoncé « ivia »', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: IviaLogo(color: IviaLogoColor.white),
      ),
    );
    expect(find.bySemanticsLabel('ivia'), findsOneWidget);
    semantics.dispose();
  });
}
