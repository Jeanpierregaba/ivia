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
        theme: IviaTheme.light(IviaAppBrand.seller),
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

  const nav = [
    IviaNavItem(icon: Icons.home_outlined, label: 'Accueil'),
    IviaNavItem(icon: Icons.receipt_long_outlined, label: 'Commandes'),
    IviaNavItem(icon: Icons.grid_view_rounded, label: 'Catalogue'),
    IviaNavItem(icon: Icons.person_outline, label: 'Compte'),
  ];

  testWidgets('barre du bas : libellé sur l\'onglet actif, tous annoncés', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var tapped = -1;
    await pump(
      tester,
      IviaBottomNav(items: nav, currentIndex: 2, onSelected: (i) => tapped = i),
    );
    expect(find.text('Catalogue'), findsOneWidget);
    expect(find.text('Accueil'), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Catalogue')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Accueil')),
      isSemantics(isButton: true, isSelected: false),
    );
    await tester.tap(find.byIcon(Icons.person_outline));
    expect(tapped, 3);
    // Activation par le lecteur d'écran.
    tester.semantics.tap(find.semantics.byLabel('Commandes'));
    expect(tapped, 1);
    semantics.dispose();
  });

  testWidgets('barre du bas dans un Scaffold : hauteur de la barre seule', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IviaTheme.light(IviaAppBrand.seller),
        home: Scaffold(
          body: const SizedBox.expand(key: Key('page')),
          bottomNavigationBar: IviaBottomNav(
            items: nav,
            currentIndex: 2,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(IviaBottomNav)).height, lessThan(100));
    expect(
      tester.getSize(find.byKey(const Key('page'))).height,
      greaterThan(400),
    );
  });

  testWidgets('barre du bas : police à 200 % sur 320 dp sans débordement', (
    tester,
  ) async {
    await pump(
      tester,
      IviaBottomNav(items: nav, currentIndex: 2, onSelected: (_) {}),
      scale: 2,
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('onglets : nombre lu avec le libellé, onglet choisi', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selected = 0;
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => IviaSegmentedTabs(
          segments: const [
            IviaSegment(label: 'En vente', count: 20),
            IviaSegment(label: 'Brouillons', count: 2),
            IviaSegment(label: 'Retirés'),
          ],
          selected: selected,
          onSelected: (i) => setState(() => selected = i),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('En vente, 20')),
      isSemantics(isButton: true, isSelected: true),
    );
    await tester.tap(find.textContaining('Brouillons'));
    await tester.pump();
    expect(selected, 1);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Brouillons, 2')),
      isSemantics(isButton: true, isSelected: true),
    );
    // Nombre inconnu : libellé seul.
    expect(find.bySemanticsLabel('Retirés'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('onglets : police à 200 % sur 320 dp sans débordement', (
    tester,
  ) async {
    await pump(
      tester,
      IviaSegmentedTabs(
        segments: const [
          IviaSegment(label: 'En vente', count: 120),
          IviaSegment(label: 'Brouillons', count: 2),
          IviaSegment(label: 'Retirés', count: 13),
        ],
        selected: 0,
        onSelected: (_) {},
      ),
      scale: 2,
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('recherche : bouton d\'effacement quand du texte est saisi', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];
    await pump(
      tester,
      IviaSearchField(
        controller: controller,
        hint: 'Rechercher un produit',
        onChanged: changes.add,
      ),
    );
    expect(find.byTooltip('Effacer la recherche'), findsNothing);
    await tester.enterText(find.byType(TextField), 'riz');
    await tester.pump();
    await tester.tap(find.byTooltip('Effacer la recherche'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(changes, ['riz', '']);
    expect(find.byTooltip('Effacer la recherche'), findsNothing);
  });

  group('quantité', () {
    Future<List<int>> stepper(WidgetTester tester, int start) async {
      final values = <int>[];
      var value = start;
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => IviaQuantityStepper(
            label: 'Quantité disponible',
            value: value,
            max: 999,
            onChanged: (v) => setState(() {
              value = v;
              values.add(v);
            }),
          ),
        ),
      );
      return values;
    }

    testWidgets('boutons bornés par le minimum', (tester) async {
      final values = await stepper(tester, 1);
      await tester.tap(find.byTooltip('Retirer 1'));
      await tester.pump();
      expect(values, [0]);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '0',
      );
      // Au minimum : bouton désactivé.
      await tester.tap(find.byTooltip('Retirer 1'));
      await tester.pump();
      expect(values, [0]);
      await tester.tap(find.byTooltip('Ajouter 1'));
      await tester.pump();
      expect(values, [0, 1]);
    });

    testWidgets('saisie : chiffres seuls, bornée par le maximum', (
      tester,
    ) async {
      final values = await stepper(tester, 12);
      await tester.enterText(find.byType(TextField), '1a5');
      expect(values.last, 15);
      await tester.enterText(find.byType(TextField), '');
      expect(values.last, 0);
      await tester.enterText(find.byType(TextField), '999');
      await tester.pump();
      await tester.tap(find.byTooltip('Ajouter 1'));
      expect(values.last, 999);
    });

    testWidgets('champ annoncé par son libellé', (tester) async {
      final semantics = tester.ensureSemantics();
      await stepper(tester, 3);
      expect(
        find.bySemanticsLabel(RegExp('Quantité disponible')),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  testWidgets('carte de choix : choisie annoncée, bordure d\'action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      Row(
        children: [
          Expanded(
            child: IviaChoiceCard(
              label: 'Petit',
              selected: false,
              onTap: () => taps++,
              visual: const SizedBox(width: 16, height: 16),
            ),
          ),
          Expanded(
            child: IviaChoiceCard(
              label: 'Moyen',
              selected: true,
              onTap: () {},
              visual: const SizedBox(width: 24, height: 24),
            ),
          ),
        ],
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Moyen')),
      isSemantics(
        isButton: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    await tester.tap(find.text('Petit'));
    expect(taps, 1);
    final material = tester.widget<Material>(
      find.descendant(
        of: find.widgetWithText(IviaChoiceCard, 'Moyen'),
        matching: find.byType(Material),
      ),
    );
    expect(
      (material.shape! as RoundedRectangleBorder).side.color,
      IviaColors.berkeleyBlue,
    );
    semantics.dispose();
  });

  testWidgets('pastilles : ton info en Cobalt, neutre en gris', (tester) async {
    await pump(
      tester,
      const Column(
        children: [
          IviaStatusPill(label: 'En vente'),
          IviaStatusPill(label: 'Alimentation', tone: IviaPillTone.neutral),
        ],
      ),
    );
    expect(
      tester.widget<Text>(find.text('En vente')).style?.color,
      IviaColors.cobaltBlue,
    );
    expect(
      tester.widget<Text>(find.text('Alimentation')).style?.color,
      IviaColors.textSecondary,
    );
  });
}
