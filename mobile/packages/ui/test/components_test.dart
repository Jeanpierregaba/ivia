import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: IviaTheme.light(),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('bouton retour : 48 dp, libellé « Retour »', (tester) async {
    var pressed = 0;
    await pump(tester, IviaBackButton(onPressed: () => pressed++));
    expect(tester.getSize(find.byType(IviaBackButton)).height, 48);
    await tester.tap(find.byTooltip('Retour'));
    expect(pressed, 1);
  });

  testWidgets('libellé de champ lu avec le champ', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      const IviaFieldLabel(label: 'Adresse e-mail', child: TextField()),
    );
    expect(find.bySemanticsLabel(RegExp('Adresse e-mail')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('tuile du logo annoncée « ivia »', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, const IviaLogoTile(size: 76));
    expect(find.bySemanticsLabel('ivia'), findsOneWidget);
    expect(tester.getSize(find.byType(IviaLogoTile)), const Size(76, 76));
    semantics.dispose();
  });

  testWidgets('boutons pleins en pilule de 54 dp, gris si désactivés', (
    tester,
  ) async {
    await pump(
      tester,
      const FilledButton(onPressed: null, child: Text('Valider')),
    );
    final button = find.byType(FilledButton);
    expect(tester.getSize(button).height, 54);
    final material = tester.widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)),
    );
    expect(material.shape, isA<StadiumBorder>());
    expect(material.color, IviaColors.border);
  });

  testWidgets('splash de chargement : slogan, chargement annoncé', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      const IviaLoadingSplash(
        color: IviaColors.imperialRed,
        tagline: 'Tout, près de chez vous.',
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Tout, près de chez vous.'), findsOneWidget);
    expect(find.bySemanticsLabel('Chargement'), findsOneWidget);
    // Logo au centre exact de l'écran, comme le splash natif.
    final logo = tester.getCenter(find.byType(IviaLogo));
    expect(logo, tester.getCenter(find.byType(Scaffold)));
    expect(tester.getSize(find.byType(IviaLogo)).width, closeTo(174, 0.5));
    // Slogan 40 dp sous le logo.
    final logoBottom = tester.getBottomLeft(find.byType(IviaLogo)).dy;
    final taglineTop = tester
        .getTopLeft(find.text('Tout, près de chez vous.'))
        .dy;
    expect(taglineTop - logoBottom, closeTo(40, 0.5));
    semantics.dispose();
  });

  testWidgets('splash : barre d\'état claire', (tester) async {
    await pump(
      tester,
      const IviaLoadingSplash(color: IviaColors.imperialRed, tagline: 'x'),
    );
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).last,
    );
    expect(region.value, SystemUiOverlayStyle.light);
  });
}
