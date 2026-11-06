import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'features/application_screen.dart';
import 'features/shell.dart';

/// Identité de l'app pharmacie dans les écrans communs de connexion.
const pharmacyIdentity = AppIdentity(
  brand: IviaAppBrand.pharmacy,
  loginTitle: 'Espace pharmacie',
  loginBody:
      "Recevez les alertes médicament des patients autour de vous et répondez "
      'en quelques secondes. Connexion avec votre numéro de téléphone.',
  loginBadge: 'Pharmacie',
  codeHint: _codeHint,
  appCode: 'pharmacy',
);

String _codeHint(Duration expiresIn) =>
    'Code valable ${expiresIn.inMinutes} minutes.';

/// Pharmacie du compte connecté ; `null` : pas encore inscrite.
final pharmacyProfileProvider = FutureProvider<PharmacyProfile?>((ref) async {
  final signedIn = ref.watch(
    authControllerProvider.select((a) => a is AuthSignedIn),
  );
  if (!signedIn) return null;
  return ref.read(apiClientProvider).pharmacyMe();
});

abstract final class Routes {
  static const splash = '/';
  static const login = AuthRoutes.login;
  static const code = AuthRoutes.code;
  static const signup = AuthRoutes.signup;
  static const welcome = '/welcome';
  static const offline = '/offline';
  static const application = '/application';
  static const home = '/home';
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(pharmacyProfileProvider, (_, _) => refresh.value++);
  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final profile = ref.read(pharmacyProfileProvider);
      final allowed = switch (auth) {
        AuthStarting() => const [Routes.splash],
        AuthSignedOut() => const [Routes.login, Routes.code, Routes.signup],
        AuthOffline() => const [Routes.offline],
        AuthNeedsProfile() => const [Routes.welcome],
        AuthSignedIn() when profile.isLoading => const [Routes.splash],
        AuthSignedIn() when profile.value?.approved == true => const [
          Routes.home,
        ],
        AuthSignedIn() => const [Routes.application],
      };
      final here = state.matchedLocation;
      return allowed.any((a) => here == a || here.startsWith('$a/'))
          ? null
          : allowed.first;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const IviaLoadingSplash(
          brand: IviaAppBrand.pharmacy,
          tile: true,
          title: 'Pharmacie',
          tagline: 'Les patients près de chez vous.',
        ),
      ),
      GoRoute(
        path: Routes.login,
        builder: (_, _) => const PhoneScreen(),
        routes: [
          GoRoute(path: 'code', builder: (_, _) => const PhoneCodeScreen()),
          GoRoute(path: 'signup', builder: (_, _) => const PhoneSignupScreen()),
        ],
      ),
      GoRoute(path: Routes.welcome, builder: (_, _) => const ProfileScreen()),
      GoRoute(path: Routes.offline, builder: (_, _) => const OfflineScreen()),
      GoRoute(
        path: Routes.application,
        builder: (_, _) => const ApplicationScreen(),
      ),
      GoRoute(path: Routes.home, builder: (_, _) => const PharmacyShell()),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await clearSessionAfterReinstall(SessionStore());
  await IviaLogo.precache(IviaAppBrand.pharmacy.logoOnLight);
  runApp(
    ProviderScope(
      overrides: [
        appIdentityProvider.overrideWithValue(pharmacyIdentity),
        apiClientProvider.overrideWithValue(
          IviaApiClient(config: ApiConfig.fromEnvironment()),
        ),
      ],
      child: const PharmacyApp(),
    ),
  );
}

class PharmacyApp extends ConsumerWidget {
  const PharmacyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'ivia Pharmacie',
    theme: IviaTheme.light(IviaAppBrand.pharmacy),
    routerConfig: ref.watch(routerProvider),
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: child!,
    ),
  );
}
