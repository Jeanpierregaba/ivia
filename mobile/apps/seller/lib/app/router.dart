import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_placeholder_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import 'onboarding_store.dart';

abstract final class Routes {
  static const onboarding = '/onboarding';
  static const login = '/login';
}

final routerProvider = Provider<GoRouter>((ref) {
  final onboarding = ref.watch(onboardingStoreProvider);
  final router = GoRouter(
    initialLocation: onboarding.seenAtLaunch ? Routes.login : Routes.onboarding,
    routes: [
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginPlaceholderScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
