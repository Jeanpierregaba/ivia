import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'app/device_services.dart';
import 'app/identity.dart';
import 'app/router.dart';

// Le splash natif (flutter_native_splash.yaml) reste affiché jusqu'à la
// première image ; le splash de chargement prend ensuite le relais pendant
// la vérification de la session et de la boutique.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  requireMapsInRelease();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await clearSessionAfterReinstall(SessionStore());
  final onboarding = await OnboardingStore.open();
  // Logotype de la tuile prêt dès la première image du splash de chargement.
  await IviaLogo.precache(IviaAppBrand.seller.logoOnLight);
  runApp(
    ProviderScope(
      overrides: [
        onboardingStoreProvider.overrideWithValue(onboarding),
        appIdentityProvider.overrideWithValue(sellerIdentity),
        apiClientProvider.overrideWithValue(
          IviaApiClient(config: ApiConfig.fromEnvironment()),
        ),
      ],
      child: const SellerApp(),
    ),
  );
}

class SellerApp extends ConsumerWidget {
  const SellerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Ivia Business',
      theme: IviaTheme.light(IviaAppBrand.seller),
      routerConfig: ref.watch(routerProvider),
      // Barre d'état sombre sur les écrans clairs ; le splash de chargement
      // (fond Berkeley) la repasse en clair.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: child!,
      ),
    );
  }
}
