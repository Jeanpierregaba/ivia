import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_ui/ivia_ui.dart';

const _slides = [
  OnboardingSlide(
    illustration: OnboardingIconIllustration(
      brand: IviaAppBrand.buyer,
      icon: Icons.storefront,
    ),
    title: 'Titre un',
    body: 'Texte un',
  ),
  OnboardingSlide(
    illustration: OnboardingIconIllustration(
      brand: IviaAppBrand.buyer,
      icon: Icons.payments,
    ),
    title: 'Titre deux',
    body: 'Texte deux',
  ),
  OnboardingSlide(
    illustration: OnboardingIconIllustration(
      brand: IviaAppBrand.buyer,
      icon: Icons.local_shipping,
    ),
    title: 'Titre trois',
    body: 'Texte trois',
  ),
];

void main() {
  late int done;

  setUp(() => done = 0);

  Future<void> pumpOnboarding(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IviaTheme.light(),
        home: IviaOnboarding(
          brand: IviaAppBrand.buyer,
          slides: _slides,
          onDone: () => done++,
        ),
      ),
    );
  }

  testWidgets('« Suivant » fait défiler les pages, « Commencer » termine', (
    tester,
  ) async {
    await pumpOnboarding(tester);
    expect(find.text('Titre un'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 1 sur 3'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Titre deux'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 2 sur 3'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Titre trois'), findsOneWidget);
    expect(find.text('Suivant'), findsNothing);
    // Masqué mais gardé dans la mise en page : l'en-tête ne bouge pas.
    expect(find.text('Passer').hitTestable(), findsNothing);
    expect(done, 0);

    await tester.tap(find.text('Commencer'));
    expect(done, 1);
  });

  testWidgets('le balayage change de page', (tester) async {
    await pumpOnboarding(tester);
    await tester.fling(find.text('Titre un'), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Titre deux'), findsOneWidget);
  });

  testWidgets('« Passer » termine depuis la première page', (tester) async {
    await pumpOnboarding(tester);
    await tester.tap(find.text('Passer'));
    expect(done, 1);
  });

  testWidgets('retour : page précédente, puis sortie depuis la première', (
    tester,
  ) async {
    await pumpOnboarding(tester);
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.text('Titre un'), findsOneWidget);

    // Première page : le retour n'est plus intercepté (l'app se ferme).
    final state = tester.state<NavigatorState>(find.byType(Navigator));
    expect(await state.maybePop(), isFalse);
    expect(done, 0);
  });

  testWidgets('bouton retour rond : page précédente ; logo sur la page 1', (
    tester,
  ) async {
    await pumpOnboarding(tester);
    expect(find.byType(IviaLogoTile), findsOneWidget);
    expect(find.byType(IviaBackButton), findsNothing);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.byType(IviaLogoTile), findsNothing);

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Titre un'), findsOneWidget);
  });

  testWidgets('partie du titre en rouge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IviaTheme.light(),
        home: IviaOnboarding(
          brand: IviaAppBrand.buyer,
          slides: const [
            OnboardingSlide(
              illustration: SizedBox(),
              title: 'Payez avec Mobile Money.',
              highlight: 'Mobile Money.',
              body: 'Texte',
            ),
          ],
          onDone: () {},
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('Payez avec Mobile Money.'));
    final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((s) => s.text), ['Payez avec ', 'Mobile Money.', '']);
    expect(spans[1].style?.color, IviaColors.primary);
  });

  testWidgets('logo et titres annoncés au lecteur d\'écran', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOnboarding(tester);
    expect(find.bySemanticsLabel('ivia'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Titre un')),
      matchesSemantics(label: 'Titre un', isHeader: true),
    );
    semantics.dispose();
  });

  for (final size in [const Size(320, 568), const Size(412, 915)]) {
    testWidgets(
      'police à 200 % sur ${size.width.toInt()} × ${size.height.toInt()} : '
      'pas de débordement',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          MaterialApp(
            theme: IviaTheme.light(),
            home: IviaOnboarding(
              brand: IviaAppBrand.driver,
              slides: const [
                OnboardingSlide(
                  illustration: OnboardingIconIllustration(
                    brand: IviaAppBrand.buyer,
                    icon: Icons.near_me,
                  ),
                  title: 'Disponible quand vous le décidez',
                  body:
                      'Votre position n\'est partagée que lorsque vous êtes '
                      'en service.',
                ),
                OnboardingSlide(
                  illustration: OnboardingIconIllustration(
                    brand: IviaAppBrand.buyer,
                    icon: Icons.route,
                  ),
                  title: 'Deux',
                  body: 'B',
                ),
              ],
              onDone: () {},
            ),
          ),
        );
        await tester.tap(find.text('Suivant'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Commencer'), findsOneWidget);

        // Titre plafonné (mots longs entiers), texte courant à 200 %.
        double scaleOf(String text) =>
            MediaQuery.textScalerOf(tester.element(find.text(text))).scale(1);
        expect(scaleOf('Deux'), IviaOnboarding.titleMaxTextScale);
        expect(scaleOf('B'), 2);
      },
    );
  }
}
