import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/code_screen.dart';
import '../features/auth/email_screen.dart';
import '../features/auth/offline_screen.dart';
import '../features/auth/profile_screen.dart';
import '../features/home/home_placeholder_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/splash/loading_screen.dart';
import 'auth_controller.dart';
import 'onboarding_store.dart';

abstract final class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const code = '/login/code';
  static const profile = '/profile';
  static const home = '/home';
  static const offline = '/offline';
}

/// Écrans permis pour un état ; le premier est la destination par défaut.
/// Un écran hors de la liste n'est jamais affiché.
String? redirectFor(
  AuthState auth, {
  required bool onboardingSeen,
  required String location,
}) {
  final allowed = switch (auth) {
    AuthStarting() => const [Routes.splash],
    AuthSignedOut() when !onboardingSeen => const [Routes.onboarding],
    AuthSignedOut() => const [Routes.login, Routes.code],
    AuthNeedsProfile() => const [Routes.profile],
    AuthSignedIn() => const [Routes.home],
    AuthOffline() => const [Routes.offline],
  };
  return allowed.contains(location) ? null : allowed.first;
}

final routerProvider = Provider<GoRouter>((ref) {
  // go_router relit la règle à chaque changement de session ou de présentation.
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(onboardingSeenProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      ref.read(authControllerProvider),
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
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const EmailScreen(),
        routes: [
          // Sous /login : le retour depuis le code revient à l'e-mail.
          GoRoute(
            path: 'code',
            builder: (context, state) => const CodeScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomePlaceholderScreen(),
      ),
      GoRoute(
        path: Routes.offline,
        builder: (context, state) => const OfflineScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
