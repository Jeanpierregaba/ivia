// Captures des écrans à 360 dp, au double (720 px comme les maquettes D00 à
// D19), avec les vraies polices. Outil de vérification visuelle (spec 033) :
//   flutter test tool/shots_test.dart --update-goldens
// Les images vont dans tool/shots/ (non versionné).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_driver/features/onboarding/onboarding_screen.dart';
import 'package:ivia_driver/features/splash/loading_screen.dart';
import 'package:ivia_ui/ivia_ui.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}

Future<void> loadFonts() async {
  const ui = '../../packages/ui/fonts';
  await _font('packages/ivia_ui/Parkinsans', [
    '$ui/Parkinsans-Regular.ttf',
    '$ui/Parkinsans-SemiBold.ttf',
    '$ui/Parkinsans-Bold.ttf',
  ]);
  // flutter_tester est dans <sdk>/bin/cache/artifacts/engine/<plateforme>/.
  final cache = File(Platform.resolvedExecutable).parent.parent.parent.path;
  await _font('MaterialIcons', [
    '$cache/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

Future<void> shot(
  WidgetTester tester,
  String name,
  Widget screen, {
  Future<void> Function(WidgetTester)? before,
}) async {
  tester.view.physicalSize = const Size(720, 1560);
  tester.view.devicePixelRatio = 2;
  // Barre d'état des maquettes : 40 dp en haut.
  tester.view.padding = const FakeViewPadding(top: 80);
  tester.view.viewPadding = const FakeViewPadding(top: 80);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: IviaTheme.light(IviaAppBrand.driver),
        home: screen,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  if (before != null) await before(tester);
  // Images d'assets (logotype) : chargées hors du temps simulé.
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('shots/$name.png'),
  );
}

void main() {
  setUpAll(loadFonts);

  testWidgets('D00', (t) => shot(t, 'D00', const LoadingScreen()));
  for (final page in [0, 1, 2]) {
    testWidgets(
      'D0${page + 1}',
      (t) => shot(
        t,
        'D0${page + 1}',
        const OnboardingScreen(),
        before: (t) async {
          for (var i = 0; i < page; i++) {
            await t.tap(find.text('Suivant'));
            await t.pumpAndSettle();
          }
        },
      ),
    );
  }
}
