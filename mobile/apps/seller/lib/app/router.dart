import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../features/home/home_placeholder_screen.dart';
import '../features/home/products_placeholder_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/shop/shop_blocked_screen.dart';
import '../features/shop/shop_form_screen.dart';
import '../features/shop/shop_pending_screen.dart';
import '../features/splash/loading_screen.dart';
import 'seller_shop.dart';

abstract final class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = AuthRoutes.login;
  static const code = AuthRoutes.code;
  static const offline = '/offline';
  static const shopNew = '/shop/new';
  static const shopPending = '/shop/pending';
  static const shopBlocked = '/shop/blocked';
  static const home = '/home';
  static const products = '/products';
}

/// Écrans permis selon la session et la boutique ; le premier est la
/// destination par défaut. Un écran hors de la liste n'est jamais affiché.
String? redirectFor(
  AuthState auth,
  AsyncValue<Shop?> shop, {
  required bool onboardingSeen,
  required String location,
}) {
  final allowed = switch (auth) {
    AuthStarting() => const [Routes.splash],
    AuthSignedOut() when !onboardingSeen => const [Routes.onboarding],
    AuthSignedOut() => const [Routes.login, Routes.code],
    AuthOffline() => const [Routes.offline],
    AuthSignedIn() || AuthNeedsProfile() => _shopScreens(shop),
  };
  return allowed.contains(location) ? null : allowed.first;
}

List<String> _shopScreens(AsyncValue<Shop?> shop) {
  // Riverpod garde l'ancienne valeur pendant un rechargement ou après une
  // erreur : l'erreur et le chargement passent donc avant la valeur.
  if (shop.hasError) return const [Routes.offline];
  if (shop.isLoading) return const [Routes.splash];
  return switch (shop.value?.status) {
    null => const [Routes.shopNew],
    ShopStatus.pendingReview => const [Routes.shopPending, Routes.products],
    ShopStatus.published => const [Routes.home, Routes.products],
    ShopStatus.rejected || ShopStatus.suspended => const [Routes.shopBlocked],
  };
}

final routerProvider = Provider<GoRouter>((ref) {
  // go_router relit la règle à chaque changement de session, de boutique ou
  // de présentation.
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(sellerShopProvider, (_, _) => refresh.value++);
  ref.listen(onboardingSeenProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      ref.read(authControllerProvider),
      ref.read(sellerShopProvider),
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
          GoRoute(
            path: 'code',
            builder: (context, state) => const CodeScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.offline,
        builder: (context, state) => const OfflineScreen(),
      ),
      GoRoute(
        path: Routes.shopNew,
        builder: (context, state) => const ShopFormScreen(),
      ),
      GoRoute(
        path: Routes.shopPending,
        builder: (context, state) => const ShopPendingScreen(),
      ),
      GoRoute(
        path: Routes.shopBlocked,
        builder: (context, state) => const ShopBlockedScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomePlaceholderScreen(),
      ),
      GoRoute(
        path: Routes.products,
        builder: (context, state) => const ProductsPlaceholderScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
