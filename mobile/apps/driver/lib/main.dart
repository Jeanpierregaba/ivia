import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'app/onboarding_store.dart';
import 'app/router.dart';

// Le splash natif (flutter_native_splash.yaml) reste affiché jusqu'à la
// première image : l'initialisation se fait donc avant runApp().
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final onboarding = await OnboardingStore.open();
  runApp(
    ProviderScope(
      overrides: [onboardingStoreProvider.overrideWithValue(onboarding)],
      child: const DriverApp(),
    ),
  );
}

class DriverApp extends ConsumerWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ivia Livreur',
      theme: IviaTheme.light(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
