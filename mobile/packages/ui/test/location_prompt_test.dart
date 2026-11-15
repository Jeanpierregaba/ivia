import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  late int allowed;
  late int refused;

  setUp(() {
    allowed = 0;
    refused = 0;
  });

  Widget prompt({
    bool busy = false,
    IviaAppBrand brand = IviaAppBrand.seller,
  }) => MaterialApp(
    theme: IviaTheme.light(),
    home: IviaLocationPrompt(
      brand: brand,
      space: 'Business',
      radar: (
        center: Icons.storefront,
        satellites: const [
          Icons.storefront,
          Icons.apartment,
          Icons.restaurant,
          Icons.construction,
        ],
      ),
      title: 'Soyez visible',
      titleAccent: 'dans votre quartier',
      body: 'Activez la localisation pour placer votre activité sur la carte.',
      busy: busy,
      onAllow: () => allowed++,
      onRefuse: () => refused++,
    ),
  );

  testWidgets('textes de la maquette, partie colorée du titre', (tester) async {
    await tester.pumpWidget(prompt());
    expect(find.text('Business'), findsOneWidget);
    expect(
      find.text('Soyez visible dans votre quartier', findRichText: true),
      findsOneWidget,
    );
    final title = tester.widget<Text>(
      find.byWidgetPredicate((w) => w is Text && w.textSpan != null),
    );
    final accent = (title.textSpan! as TextSpan).children![1] as TextSpan;
    expect(accent.text, 'dans votre quartier');
    expect(accent.style?.color, IviaAppBrand.seller.highlight);
    expect(find.bySemanticsLabel('ivia'), findsOneWidget);
    expect(find.text('Autoriser la localisation'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
  });

  testWidgets('« Autoriser » et « Plus tard » appellent leur action', (
    tester,
  ) async {
    await tester.pumpWidget(prompt());
    await tester.ensureVisible(find.text('Plus tard'));
    await tester.tap(find.text('Autoriser la localisation'));
    await tester.tap(find.text('Plus tard'));
    expect((allowed, refused), (1, 1));
  });

  testWidgets('demande en cours : « Autoriser » occupé, « Plus tard » actif', (
    tester,
  ) async {
    await tester.pumpWidget(prompt(busy: true));
    await tester.ensureVisible(find.text('Plus tard'));
    await tester.tap(find.text('Autoriser la localisation'));
    await tester.tap(find.text('Plus tard'));
    expect((allowed, refused), (0, 1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('barre d\'état claire, barre de navigation blanche', (
    tester,
  ) async {
    await tester.pumpWidget(prompt());
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value.statusBarIconBrightness, Brightness.light);
    expect(region.value.systemNavigationBarColor, IviaColors.surface);
    expect(region.value.systemNavigationBarIconBrightness, Brightness.dark);
  });

  testWidgets('logo teinté de la couleur de l\'app dans une tuile blanche', (
    tester,
  ) async {
    await tester.pumpWidget(prompt(brand: IviaAppBrand.pharmacy));
    final logo = tester.widget<Image>(
      find.descendant(of: find.byType(IviaLogo), matching: find.byType(Image)),
    );
    expect(logo.color, IviaAppBrand.pharmacy.accent);
    expect(logo.colorBlendMode, BlendMode.srcIn);
  });

  testWidgets('police à 200 % sur 320 dp : rien ne déborde, tout atteignable', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: prompt(),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Plus tard'), 200);
    await tester.tap(find.text('Plus tard'));
    expect(refused, 1);
  });
}
