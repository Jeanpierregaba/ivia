import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_buyer/app/onboarding_store.dart';
import 'package:ivia_buyer/features/onboarding/onboarding_screen.dart';
import 'package:ivia_buyer/main.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _firstTitle = "Trouvez ce qu'il vous faut, tout près.";

void main() {
  /// Lance l'app comme main(), avec le stockage tel qu'il est.
  Future<void> launchApp(WidgetTester tester) async {
    final store = await OnboardingStore.open();
    // Nouvel arbre : simule un redémarrage de l'app.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [onboardingStoreProvider.overrideWithValue(store)],
        child: const BuyerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
  }

  Future<bool?> seenFlag() async =>
      (await SharedPreferences.getInstance()).getBool('onboarding_seen');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets("l'app utilise le thème ivia", (tester) async {
    await launchApp(tester);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'ivia');
    expect(app.theme?.colorScheme.primary, IviaColors.primary);
  });

  testWidgets('premier lancement : la présentation de l\'acheteur', (
    tester,
  ) async {
    await launchApp(tester);
    expect(find.text(_firstTitle), findsOneWidget);
    final onboarding = tester.widget<IviaOnboarding>(
      find.byType(IviaOnboarding),
    );
    expect(onboarding.brand, IviaAppBrand.buyer);
    expect(onboarding.slides, hasLength(3));
  });

  testWidgets('« Passer » depuis la page 2 : connexion, puis plus jamais', (
    tester,
  ) async {
    await launchApp(tester);
    await next(tester);
    await tester.tap(find.text('Passer'));
    await tester.pumpAndSettle();
    expect(find.text('Connexion'), findsOneWidget);
    expect(await seenFlag(), isTrue);

    await launchApp(tester);
    expect(find.text('Connexion'), findsOneWidget);
    expect(find.byType(IviaOnboarding), findsNothing);
  });

  testWidgets('« Commencer » : connexion et présentation mémorisée', (
    tester,
  ) async {
    await launchApp(tester);
    await next(tester);
    await next(tester);
    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    expect(find.text('Connexion'), findsOneWidget);
    expect(await seenFlag(), isTrue);
  });

  testWidgets('app fermée pendant la présentation : reprise à la page 1', (
    tester,
  ) async {
    await launchApp(tester);
    await next(tester);
    await launchApp(tester);
    expect(find.text(_firstTitle), findsOneWidget);
  });

  testWidgets('retour Android : page précédente, puis sortie de l\'app', (
    tester,
  ) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    await launchApp(tester);
    await next(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_firstTitle), findsOneWidget);
    expect(calls, isNot(contains('SystemNavigator.pop')));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(calls, contains('SystemNavigator.pop'));
  });

  testWidgets('titres : aucun mot coupé sur 320 dp, police agrandie', (
    tester,
  ) async {
    // Vraie police (les tests utilisent sinon une police de substitution).
    final loader = FontLoader('packages/ivia_ui/Parkinsans')
      ..addFont(rootBundle.load('packages/ivia_ui/fonts/Parkinsans-Bold.ttf'));
    await loader.load();

    const width = 320 - 2 * IviaSpacing.screen;
    final style = IviaTheme.light().textTheme.headlineMedium!;
    for (final slide in onboardingSlides) {
      for (final word in slide.title.split(' ')) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: TextDirection.ltr,
          textScaler: const TextScaler.linear(IviaOnboarding.titleMaxTextScale),
        )..layout();
        expect(painter.width, lessThanOrEqualTo(width), reason: word);
        painter.dispose();
      }
    }
  });
}
