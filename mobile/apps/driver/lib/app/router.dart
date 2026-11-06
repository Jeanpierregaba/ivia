import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../features/dossier/dossier_blocked_screen.dart';
import '../features/dossier/dossier_form_screen.dart';
import '../features/dossier/dossier_pending_screen.dart';
import '../features/dossier/dossier_summary_screen.dart';
import '../features/work/work_screens.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/splash/loading_screen.dart';
import 'driver_dossier.dart';

abstract final class Routes {
  static const splash = '/';

  /// Autorisation de la localisation, juste après le splash (spec 030).
  static const location = '/location';
  static const onboarding = '/onboarding';
  static const login = AuthRoutes.login;
  static const code = AuthRoutes.code;
  static const signup = AuthRoutes.signup;
  static const offline = '/offline';
  static const dossierNew = '/dossier/new';
  static const dossierEdit = '/dossier/edit';
  static const dossierPending = '/dossier/pending';
  static const dossierSummary = '/dossier/summary';
  static const dossierBlocked = '/dossier/blocked';
  static const home = '/home';
}

/// Écrans permis selon la session et le dossier ; le premier est la
/// destination par défaut. Un écran hors de la liste n'est jamais affiché.
String? redirectFor(
  AuthState auth,
  AsyncValue<DriverDossier?> dossier, {
  required bool onboardingSeen,
  required String location,
  bool locationPromptDone = true,
}) {
  final allowed = switch (auth) {
    AuthStarting() => const [Routes.splash],
    // Après le splash, avant tout le reste : une fois (spec 030).
    _ when !locationPromptDone => const [Routes.location],
    AuthSignedOut() when !onboardingSeen => const [Routes.onboarding],
    AuthSignedOut() => const [Routes.login, Routes.code, Routes.signup],
    AuthOffline() => const [Routes.offline],
    AuthSignedIn() || AuthNeedsProfile() => _dossierScreens(dossier),
  };
  return allowed.contains(location) ? null : allowed.first;
}

List<String> _dossierScreens(AsyncValue<DriverDossier?> dossier) {
  // Riverpod garde l'ancienne valeur pendant un rechargement ou après une
  // erreur : l'erreur et le chargement passent donc avant la valeur.
  if (dossier.hasError) return const [Routes.offline];
  if (dossier.isLoading) return const [Routes.splash];
  final value = dossier.value;
  if (value == null) return const [Routes.dossierNew];
  if (value.suspended) return const [Routes.dossierBlocked];
  return switch (value.review) {
    // En vérification, le dossier reste modifiable (pièces manquantes après
    // un envoi interrompu) : le serveur accepte la correction.
    DriverReview.pending => const [
      Routes.dossierPending,
      Routes.dossierSummary,
      Routes.dossierEdit,
    ],
    DriverReview.rejected => const [Routes.dossierBlocked, Routes.dossierEdit],
    DriverReview.approved => const [Routes.home],
  };
}

final routerProvider = Provider<GoRouter>((ref) {
  // go_router relit la règle à chaque changement de session, de dossier ou
  // de présentation.
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(driverDossierProvider, (_, _) => refresh.value++);
  ref.listen(onboardingSeenProvider, (_, _) => refresh.value++);
  ref.listen(locationPromptDoneProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      ref.read(authControllerProvider),
      ref.read(driverDossierProvider),
      onboardingSeen: ref.read(onboardingSeenProvider),
      locationPromptDone: ref.read(locationPromptDoneProvider),
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const LoadingScreen(),
      ),
      GoRoute(
        path: Routes.location,
        builder: (context, state) => const LaunchLocationPromptScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const PhoneScreen(),
        routes: [
          GoRoute(
            path: 'code',
            builder: (context, state) => const PhoneCodeScreen(),
          ),
          GoRoute(
            path: 'signup',
            builder: (context, state) => const PhoneSignupScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.offline,
        builder: (context, state) => const OfflineScreen(),
      ),
      GoRoute(
        path: Routes.dossierNew,
        builder: (context, state) => const DossierFormScreen(),
      ),
      GoRoute(
        path: Routes.dossierEdit,
        builder: (context, state) => const DossierFormScreen(correction: true),
      ),
      GoRoute(
        path: Routes.dossierPending,
        builder: (context, state) => const DossierPendingScreen(),
      ),
      GoRoute(
        path: Routes.dossierSummary,
        builder: (context, state) => const DossierSummaryScreen(),
      ),
      GoRoute(
        path: Routes.dossierBlocked,
        builder: (context, state) => const DossierBlockedScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const DriverShell(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
