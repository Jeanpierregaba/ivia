import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: IviaTheme.light(),
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('puce : active en Berkeley, annoncée choisie, flèche', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      Row(
        children: [
          IviaChip(label: 'Tout', selected: true, onTap: () {}),
          IviaChip(label: 'Prix', dropdown: true, onTap: () => taps++),
        ],
      ),
    );
    final active = tester.widget<Material>(
      find.descendant(
        of: find.widgetWithText(IviaChip, 'Tout'),
        matching: find.byType(Material),
      ),
    );
    expect(active.color, IviaColors.tertiary);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Tout')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    await tester.tap(find.text('Prix'));
    expect(taps, 1);
    expect(tester.getSize(find.byType(IviaChip).first).height, 48);
    semantics.dispose();
  });

  testWidgets('carte produit : lue d\'un bloc, épuisé, sans photo', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      SizedBox(
        width: 180,
        child: IviaProductCard(
          imageUrl: null,
          name: 'Riz parfumé 5 kg',
          shopName: 'Chez Afi',
          distance: '350 m',
          price: '4 500 F',
          soldOut: true,
          onTap: () => taps++,
        ),
      ),
    );
    expect(
      find.bySemanticsLabel(
        'Riz parfumé 5 kg, 4 500 F, Chez Afi, 350 m, épuisé',
      ),
      findsOneWidget,
    );
    expect(find.text('Épuisé'), findsOneWidget);
    expect(find.byType(IviaImagePlaceholder), findsOneWidget);
    await tester.tap(find.text('Riz parfumé 5 kg'));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('carte produit : police à 200 % sur une demi-largeur de 320 dp', (
    tester,
  ) async {
    await pump(
      tester,
      SizedBox(
        width: 140,
        child: IviaProductCard(
          imageUrl: null,
          name: 'Riz parfumé long grain de Thaïlande, sac de 5 kg',
          shopName: 'Superette Nyékonakpoè',
          distance: '1,8 km',
          price: '14 000 F',
          onTap: () {},
        ),
      ),
      scale: 2,
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('image réseau : emplacement hachuré si le chargement échoue', (
    tester,
  ) async {
    await pump(
      tester,
      const SizedBox(
        width: 100,
        height: 100,
        child: IviaNetworkImage(url: 'https://cdn.test/inconnue.jpg'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(IviaImagePlaceholder), findsOneWidget);
  });

  testWidgets('carrousel : points et position annoncée', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      const SizedBox(
        height: 300,
        child: IviaPhotoCarousel(
          urls: ['https://cdn.test/1.jpg', 'https://cdn.test/2.jpg'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Photo 1 sur 2'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Photo 2 sur 2'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('carte produit : « + » lu à part, 48 dp, attente', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var opened = 0;
    var added = 0;
    Widget card({bool adding = false}) => SizedBox(
      width: 180,
      child: IviaProductCard(
        imageUrl: null,
        name: 'Riz parfumé 5 kg',
        shopName: 'Chez Afi',
        price: '4 500 F',
        onTap: () => opened++,
        onAdd: () => added++,
        adding: adding,
      ),
    );
    await pump(tester, card());
    final add = find.bySemanticsLabel('Ajouter Riz parfumé 5 kg au panier');
    expect(add, findsOneWidget);
    expect(
      tester.getSemantics(add),
      isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
    );
    expect(tester.getSize(find.byType(IviaAddButton)), const Size(48, 48));
    await tester.tap(find.byType(IviaAddButton));
    expect((added, opened), (1, 0));
    await tester.tap(find.text('Riz parfumé 5 kg'));
    expect((added, opened), (1, 1));

    await pump(tester, card(adding: true));
    expect(
      find.descendant(
        of: find.byType(IviaAddButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(IviaAddButton));
    expect(added, 1);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('carte produit sans « + » : rien de plus', (tester) async {
    await pump(
      tester,
      SizedBox(
        width: 180,
        child: IviaProductCard(
          imageUrl: null,
          name: 'Lait',
          shopName: 'Chez Afi',
          price: '2 750 F',
          soldOut: true,
          onTap: () {},
        ),
      ),
    );
    expect(find.byType(IviaAddButton), findsNothing);
  });

  testWidgets('icône à pastille : nombre, 99+, lue avec son libellé', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    Widget button(int count) => IviaIconBadgeButton(
      icon: Icons.shopping_bag_outlined,
      label: 'Panier',
      count: count,
      semanticLabel: count == 0 ? 'Panier' : 'Panier, $count articles',
      onPressed: () => taps++,
    );
    await pump(tester, button(0));
    expect(find.text('0'), findsNothing);
    expect(find.bySemanticsLabel('Panier'), findsOneWidget);
    expect(
      tester.getSize(find.byType(IviaIconBadgeButton)),
      const Size(48, 48),
    );

    await pump(tester, button(3));
    expect(find.text('3'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Panier, 3 articles')),
      isSemantics(isButton: true, hasTapAction: true, isEnabled: true),
    );
    await tester.tap(find.byType(IviaIconBadgeButton));
    expect(taps, 1);

    await pump(tester, button(120), scale: 2);
    expect(find.text('99+'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });
}
