import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'package:ivia_app_core/ivia_app_core.dart';

import 'app/buyer_area.dart';
import 'app/identity.dart';
import 'app/router.dart';

// Le splash natif (flutter_native_splash.yaml) reste affiché jusqu'à la
// première image ; le splash de chargement prend ensuite le relais pendant
// la vérification de la session (AuthController).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await clearSessionAfterReinstall(SessionStore());
  final onboarding = await OnboardingStore.open();
  final area = await AreaStore.open();
  // « Autour de moi » : la précision d'un quartier suffit.
  const location = DeviceLocationService(approximate: true);
  final locationPrompt = await LocationPromptStore.open(location);
  // Logotype du splash de chargement prêt dès sa première image.
  await IviaLogo.precache(IviaLogoColor.white);
  runApp(
    ProviderScope(
      overrides: [
        onboardingStoreProvider.overrideWithValue(onboarding),
        areaStoreProvider.overrideWithValue(area),
        locationServiceProvider.overrideWithValue(location),
        locationPromptStoreProvider.overrideWithValue(locationPrompt),
        appIdentityProvider.overrideWithValue(buyerIdentity),
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
      // Barre d'état sombre sur les écrans clairs ; le splash de chargement
      // (fond rouge) la repasse en clair.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: child!,
      ),
    );
  }
}
