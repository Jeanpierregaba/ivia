import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'common/providers.dart';
import 'features/alerts/alert_detail_screen.dart';
import 'features/alerts/incoming_alert_screen.dart';
import 'features/application/application_screen.dart';
import 'features/home/pharmacy_shell.dart';
import 'features/launch/onboarding_screen.dart';
import 'features/push/alerts_permission.dart';
import 'features/push/push.dart';

/// Identité de l'app pharmacie dans les écrans communs de connexion.
const pharmacyIdentity = AppIdentity(
  brand: IviaAppBrand.pharmacy,
  loginTitle: 'Espace pharmacie',
  loginBody: 'Connectez-vous avec votre numéro. Nous vous envoyons un code.',
  loginBadge: 'Pharmacie',
  // Maquettes F04 et F05 (spec 031).
  loginBadgeFilled: true,
  termsLabel: 'Conditions partenaires',
  authTips: false,
  codeTitleByChannel: true,
  codeHint: _codeHint,
  appCode: 'pharmacy',
  locationPrompt: LocationPromptCopy(
    space: 'Pharmacie',
    center: Icons.medical_services,
    satellites: [Icons.person, Icons.person, Icons.person, Icons.person],
    title: 'Les alertes',
    titleAccent: 'de votre quartier',
    body:
        'Activez la localisation pour recevoir les demandes des clients '
        'proches.',
    laterLabel: "Saisir l'adresse",
  ),
);

String _codeHint(Duration expiresIn) =>
    'Code valable ${expiresIn.inMinutes} minutes.';

abstract final class Routes {
  static const splash = '/';

  /// Autorisation de la localisation, juste après le splash (spec 030).
  static const location = '/location';

  /// Présentation en 3 pages, une fois sur le téléphone (F01 à F03).
  static const onboarding = '/onboarding';
  static const login = AuthRoutes.login;
  static const code = AuthRoutes.code;
  static const signup = AuthRoutes.signup;
  static const welcome = '/welcome';
  static const offline = '/offline';
  static const application = '/application';
  static const permissions = '/permissions';
  static const home = '/home';
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(pharmacyProfileProvider, (_, _) => refresh.value++);
  ref.listen(alertsReadyProvider, (_, _) => refresh.value++);
  ref.listen(alertsPromptSkippedProvider, (_, _) => refresh.value++);
  ref.listen(locationPromptDoneProvider, (_, _) => refresh.value++);
  ref.listen(onboardingSeenProvider, (_, _) => refresh.value++);
  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final profile = ref.read(pharmacyProfileProvider);
      // Sans ces autorisations, l'alerte ne sonne pas par-dessus l'écran verrouillé.
      final askAlerts =
          ref.read(alertsReadyProvider).value == false &&
          !ref.read(alertsPromptSkippedProvider);
      final allowed = switch (auth) {
        AuthStarting() => const [Routes.splash],
        // Après le splash, avant tout le reste : une fois (spec 030).
        _ when !ref.read(locationPromptDoneProvider) => const [Routes.location],
        AuthSignedOut() when !ref.read(onboardingSeenProvider) => const [
          Routes.onboarding,
        ],
        AuthSignedOut() => const [Routes.login, Routes.code, Routes.signup],
        AuthOffline() => const [Routes.offline],
        AuthNeedsProfile() => const [Routes.welcome],
        // Première lecture, ou relecture après la connexion : le splash. Une
        // relecture forcée (après un envoi) garde l'écran en place.
        AuthSignedIn() when profile.isLoading && !profile.isRefreshing =>
          const [Routes.splash],
        AuthSignedIn() when profile.value?.approved == true && askAlerts =>
          const [Routes.permissions],
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
        builder: (_, _) => IviaLoadingSplash(
          brand: IviaAppBrand.pharmacy,
          tile: true,
          title: 'Pharmacie',
          tagline: 'Répondez aux urgences de votre quartier.',
          // Maquette F00 : tuile de 132 dp, logotype vert.
          tileStyle: const IviaSplashTile(
            size: 132,
            radiusRatio: 0.242,
            logoRatio: 0.595,
            logoTint: IviaPharmacyColors.green,
          ),
          titleStyle: const TextStyle(fontSize: 24),
          taglineStyle: const TextStyle(
            fontSize: 16,
            color: IviaPharmacyColors.onGreenMuted,
          ),
          centerGroup: true,
        ),
      ),
      GoRoute(
        path: Routes.location,
        builder: (_, _) => const LaunchLocationPromptScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingScreen(),
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
      GoRoute(
        path: Routes.permissions,
        builder: (_, _) => const AlertsPermissionScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (_, _) => const PharmacyShell(),
        routes: [
          GoRoute(
            path: 'incoming/:id',
            builder: (_, state) =>
                IncomingAlertScreen(alertId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'alert/:id',
            builder: (_, state) =>
                AlertDetailScreen(alertId: state.pathParameters['id']!),
          ),
        ],
      ),
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
  setUpPushBackground();
  // Position de l'officine : précise.
  const location = DeviceLocationService();
  final locationPrompt = await LocationPromptStore.open(location);
  final onboarding = await OnboardingStore.open();
  await IviaLogo.precache(IviaLogoColor.white);
  runApp(
    ProviderScope(
      overrides: [
        appIdentityProvider.overrideWithValue(pharmacyIdentity),
        locationServiceProvider.overrideWithValue(location),
        locationPromptStoreProvider.overrideWithValue(locationPrompt),
        onboardingStoreProvider.overrideWithValue(onboarding),
        apiClientProvider.overrideWithValue(
          IviaApiClient(config: ApiConfig.fromEnvironment()),
        ),
      ],
      child: const PharmacyApp(),
    ),
  );
}

class PharmacyApp extends ConsumerStatefulWidget {
  const PharmacyApp({super.key});

  @override
  ConsumerState<PharmacyApp> createState() => _PharmacyAppState();
}

class _PharmacyAppState extends ConsumerState<PharmacyApp> {
  @override
  void initState() {
    super.initState();
    final push = ref.read(pushProvider);
    // Notification touchée : l'alerte entrante (F10).
    push.onOpenAlert = (id) =>
        ref.read(routerProvider).push(incomingAlertPath(id));
    // App ouverte : la boîte est relue, et l'accueil ouvre l'alerte en plein
    // écran s'il est au premier plan (jamais par-dessus une réponse).
    push.onAlertReceived = (_) => ref.invalidate(inboxProvider);
    // Dès la connexion, y compris dossier en attente : la validation arrive aussi par push.
    ref.listenManual(authControllerProvider.select((a) => a is AuthSignedIn), (
      _,
      signedIn,
    ) {
      if (signedIn) push.start();
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'ivia Pharmacie',
    theme: IviaTheme.light(IviaAppBrand.pharmacy),
    routerConfig: ref.watch(routerProvider),
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: child!,
    ),
  );
}
