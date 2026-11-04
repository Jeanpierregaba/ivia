import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../features/dossier/dossier_blocked_screen.dart';
import '../features/dossier/dossier_form_screen.dart';
import '../features/dossier/dossier_pending_screen.dart';
import '../features/dossier/dossier_summary_screen.dart';
import '../features/home/home_placeholder_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/splash/loading_screen.dart';
import 'driver_dossier.dart';

abstract final class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = AuthRoutes.login;
  static const offline = '/offline';
  static const dossierNew = '/dossier/new';
  static const dossierEdit = '/dossier/edit';
  static const dossierPending = '/dossier/pending';
  static const dossierSummary = '/dossier/summary';
  static const dossierBlocked = '/dossier/blocked';
  static const home = '/home';
  static const homePassword = '/home/password';
}

/// Écrans permis selon la session et le dossier ; le premier est la
/// destination par défaut. Un écran hors de la liste n'est jamais affiché.
String? redirectFor(
  AuthState auth,
  AsyncValue<DriverDossier?> dossier, {
  required bool onboardingSeen,
  required String location,
}) {
  final allowed = switch (auth) {
    AuthStarting() => const [Routes.splash],
    AuthSignedOut() when !onboardingSeen => const [Routes.onboarding],
    AuthSignedOut() => const [Routes.login],
    AuthOffline() => const [Routes.offline],
    AuthSignedIn() || AuthNeedsProfile() => _dossierScreens(dossier),
  };
  // Écrans de connexion : `/login` et ses sous-écrans (création, mot de
  // passe oublié) ; les autres écrans sont exacts.
  final ok = allowed.any(
    (a) => location == a || (a == Routes.login && location.startsWith('$a/')),
  );
  return ok ? null : allowed.first;
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
    DriverReview.approved => const [Routes.home, Routes.homePassword],
  };
}

final routerProvider = Provider<GoRouter>((ref) {
  // go_router relit la règle à chaque changement de session, de dossier ou
  // de présentation.
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(driverDossierProvider, (_, _) => refresh.value++);
  ref.listen(onboardingSeenProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      ref.read(authControllerProvider),
      ref.read(driverDossierProvider),
      onboardingSeen: ref.read(onboardingSeenProvider),
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const LoadingScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      ...authRoutes(),
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
        builder: (context, state) => const HomePlaceholderScreen(),
        routes: [
          GoRoute(
            path: 'password',
            builder: (context, state) => const ChangePasswordScreen(),
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
