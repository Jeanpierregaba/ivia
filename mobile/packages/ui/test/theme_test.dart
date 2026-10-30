import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_ui/ivia_ui.dart';

void main() {
  final theme = IviaTheme.light();

  test('les rôles de couleur reprennent la charte', () {
    final scheme = theme.colorScheme;
    expect(scheme.primary, const Color(0xFFED1C2F));
    expect(scheme.secondary, const Color(0xFF004DA8));
    expect(scheme.tertiary, const Color(0xFF0E2E54));
    expect(scheme.error, const Color(0xFFAA0E1B));
    expect(scheme.onSurface, const Color(0xFF0A1A30));
    expect(scheme.outline, const Color(0xFF7F8C9E));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF3F4F6));
  });

  test('tous les styles de texte utilisent Parkinsans du paquet ivia_ui', () {
    final styles = [
      theme.textTheme.displaySmall,
      theme.textTheme.titleLarge,
      theme.textTheme.bodyLarge,
      theme.textTheme.labelLarge,
      theme.textTheme.labelSmall,
    ];
    for (final style in styles) {
      expect(style?.fontFamily, 'packages/ivia_ui/Parkinsans');
    }
  });

  test('tailles, interlignes et graisses de la charte', () {
    void check(TextStyle s, double size, double line, FontWeight weight) {
      expect(s.fontSize, size);
      expect(s.height! * s.fontSize!, closeTo(line, 0.001));
      expect(s.fontWeight, weight);
    }

    check(IviaTextStyles.display, 34, 38, FontWeight.w700);
    check(IviaTextStyles.title1, 28, 32, FontWeight.w700);
    check(IviaTextStyles.title2, 22, 28, FontWeight.w700);
    check(IviaTextStyles.title3, 17, 22, FontWeight.w700);
    check(IviaTextStyles.body, 15, 22, FontWeight.w400);
    check(IviaTextStyles.bodyStrong, 15, 22, FontWeight.w600);
    check(IviaTextStyles.caption, 13, 18, FontWeight.w400);
    check(IviaTextStyles.overline, 12, 16, FontWeight.w600);
    check(IviaTextStyles.button, 16, 20, FontWeight.w700);
    expect(IviaTextStyles.display.letterSpacing, closeTo(-0.68, 0.001));
    expect(IviaTextStyles.overline.letterSpacing, closeTo(0.96, 0.001));
  });

  Future<void> pumpWithTheme(WidgetTester tester, Widget child) =>
      tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(body: child),
        ),
      );

  Color? textColor(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text)).text.style?.color;

  testWidgets('boutons texte et contour : texte rouge lisible (Cornell)', (
    tester,
  ) async {
    await pumpWithTheme(
      tester,
      Column(
        children: [
          TextButton(onPressed: () {}, child: const Text('Annuler')),
          OutlinedButton(onPressed: () {}, child: const Text('Modifier')),
        ],
      ),
    );
    expect(textColor(tester, 'Annuler'), IviaColors.primaryStrong);
    expect(textColor(tester, 'Modifier'), IviaColors.primaryStrong);
  });

  testWidgets('barre de navigation : icône sélectionnée visible', (
    tester,
  ) async {
    await pumpWithTheme(
      tester,
      NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.receipt), label: 'Commandes'),
        ],
      ),
    );
    final selected = IconTheme.of(tester.element(find.byIcon(Icons.home)));
    final other = IconTheme.of(tester.element(find.byIcon(Icons.receipt)));
    expect(selected.color, IviaColors.tertiary);
    expect(other.color, IviaColors.textSecondary);
    expect(textColor(tester, 'Accueil'), IviaColors.text);
  });

  testWidgets('puce de filtre sélectionnée : fond pâle, texte foncé', (
    tester,
  ) async {
    await pumpWithTheme(
      tester,
      FilterChip(label: const Text('Bè'), selected: true, onSelected: (_) {}),
    );
    expect(theme.chipTheme.selectedColor, IviaColors.secondarySoft);
    expect(textColor(tester, 'Bè'), IviaColors.text);
  });

  testWidgets('le bouton principal est rouge, haut de 48 au moins', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: FilledButton(onPressed: () {}, child: const Text('Payer')),
          ),
        ),
      ),
    );
    final button = find.byType(FilledButton);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    final material = tester.widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)),
    );
    expect(material.color, IviaColors.primary);
  });
}
