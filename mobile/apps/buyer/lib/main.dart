import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'app/onboarding_store.dart';
import 'app/providers.dart';
import 'app/router.dart';

// Le splash natif (flutter_native_splash.yaml) reste affiché jusqu'à la
// première image ; le splash de chargement prend ensuite le relais pendant
// la vérification de la session (AuthController).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final onboarding = await OnboardingStore.open();
  runApp(
    ProviderScope(
      overrides: [
        onboardingStoreProvider.overrideWithValue(onboarding),
        apiClientProvider.overrideWithValue(
          IviaApiClient(config: ApiConfig.fromEnvironment()),
        ),
      ],
      child: const BuyerApp(),
    ),
  );
}

class BuyerApp extends ConsumerWidget {
  const BuyerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ivia',
      theme: IviaTheme.light(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
