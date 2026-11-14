import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  Future<void> pumpIn(WidgetTester tester, IviaAppBrand brand, Widget child) =>
      tester.pumpWidget(
        MaterialApp(
          theme: IviaTheme.light(brand),
          home: Scaffold(body: Center(child: child)),
        ),
      );

  Color? buttonColor(WidgetTester tester, Type type) => tester
      .widget<Material>(
        find.descendant(of: find.byType(type), matching: find.byType(Material)),
      )
      .color;

  testWidgets('acheteur : action Imperial, liens Cornell', (tester) async {
    await pumpIn(
      tester,
      IviaAppBrand.buyer,
      FilledButton(onPressed: () {}, child: const Text('Payer')),
    );
    expect(buttonColor(tester, FilledButton), IviaColors.imperialRed);
    final theme = IviaTheme.light();
    expect(theme.colorScheme.primary, IviaColors.imperialRed);
    expect(
      theme.textButtonTheme.style?.foregroundColor?.resolve({}),
      IviaColors.cornellRed,
    );
  });

  testWidgets('marchand : action et liens Berkeley, titres Cobalt', (
    tester,
  ) async {
    await pumpIn(
      tester,
      IviaAppBrand.seller,
      FilledButton(onPressed: () {}, child: const Text('Accepter')),
    );
    expect(buttonColor(tester, FilledButton), IviaColors.berkeleyBlue);
    final theme = IviaTheme.light(IviaAppBrand.seller);
    expect(
      theme.textButtonTheme.style?.foregroundColor?.resolve({}),
      IviaColors.berkeleyBlue,
    );
    final focused = theme.inputDecorationTheme.focusedBorder!;
    expect(focused.borderSide.color, IviaColors.berkeleyBlue);
    expect(IviaAppBrand.seller.highlight, IviaColors.cobaltBlue);
    expect(
      IviaAppBrand.of(tester.element(find.byType(FilledButton))),
      IviaAppBrand.seller,
    );
  });

  test('livreur : action, liens et titres Cobalt', () {
    final theme = IviaTheme.light(IviaAppBrand.driver);
    expect(theme.colorScheme.primary, IviaColors.cobaltBlue);
    expect(
      theme.textButtonTheme.style?.foregroundColor?.resolve({}),
      IviaColors.cobaltBlue,
    );
    expect(IviaAppBrand.driver.highlight, IviaColors.cobaltBlue);
  });

  testWidgets('splash tuile : tuile centrée, titre et slogan dessous', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IviaTheme.light(IviaAppBrand.seller),
        home: const IviaLoadingSplash(
          brand: IviaAppBrand.seller,
          tile: true,
          title: 'Marchand',
          tagline: 'Vendez dans votre quartier.',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final screen = tester.getCenter(find.byType(IviaLoadingSplash));
    final logo = find.byType(IviaLogo);
    final tile = find
        .ancestor(of: logo, matching: find.byType(Container))
        .first;
    expect(tester.getSize(tile), const Size(172, 172));
    expect(tester.getCenter(tile), screen);
    expect(tester.widget<IviaLogo>(logo).color, IviaLogoColor.berkeley);
    final titleTop = tester.getTopLeft(find.text('Marchand')).dy;
    expect(titleTop - tester.getBottomLeft(tile).dy, closeTo(24, 0.5));
    expect(find.text('Vendez dans votre quartier.'), findsOneWidget);
  });

  testWidgets('étapes : états lus par le lecteur d\'écran', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpIn(
      tester,
      IviaAppBrand.seller,
      const IviaStepList(
        steps: [
          IviaStep(title: 'Compte créé', state: IviaStepState.done),
          IviaStep(
            title: 'Validation par ivia',
            subtitle: 'En cours',
            state: IviaStepState.current,
          ),
          IviaStep(
            title: 'Boutique visible des acheteurs',
            state: IviaStepState.upcoming,
          ),
        ],
      ),
    );
    expect(
      tester.getSemantics(find.text('Compte créé')),
      matchesSemantics(label: 'Compte créé', value: 'terminé'),
    );
    expect(
      tester.getSemantics(find.text('Boutique visible des acheteurs')),
      matchesSemantics(
        label: 'Boutique visible des acheteurs',
        value: 'à venir',
      ),
    );
    semantics.dispose();
  });
}
