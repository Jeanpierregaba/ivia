import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../features/cart/cart_screen.dart';
import '../features/checkout/checkout_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/orders/order_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/payment/payment_screen.dart';
import '../features/payment/payment_wait_screen.dart';
import '../features/product/product_screen.dart';
import '../features/profile/profile_tab_screen.dart';
import '../features/search/search_screen.dart';
import '../features/shell/buyer_shell.dart';
import '../features/shop/shop_screen.dart';
import '../features/splash/loading_screen.dart';

abstract final class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = AuthRoutes.login;

  /// « Faisons connaissance » : profil à compléter après la connexion.
  static const welcome = '/welcome';
  static const offline = '/offline';

  // Onglets.
  static const home = '/home';
  static const search = '/search';
  static const orders = '/orders';
  static const profile = '/profile';
  static const profilePassword = '/profile/password';

  // Fiches, par-dessus la barre du bas.
  static const shops = '/shops';
  static const products = '/products';
  static String shop(String id) => '$shops/$id';
  static String product(String id) => '$products/$id';
  static const cart = '/cart';
  static const checkout = '/checkout';
  static String order(String id) => '$orders/$id';

  /// Paiement d'une commande, au-dessus de son suivi.
  static String pay(String orderId, {PaymentOperator? operator}) =>
      '${order(orderId)}/pay'
      '${operator == null ? '' : '?operator=${operator.code}'}';

  /// Attente de la validation d'une demande, au-dessus du suivi : le retour
  /// mène au suivi, pas à l'écran Paiement.
  static String payWait(String orderId, String paymentId) =>
      '${order(orderId)}/payments/$paymentId';
}

/// Écrans permis pour un état ; le premier est la destination par défaut.
/// Un écran hors de la liste n'est jamais affiché ; une entrée permet aussi
/// ses sous-écrans (`/shops` permet `/shops/<id>`).
String? redirectFor(
  AuthState auth, {
  required bool onboardingSeen,
  required String location,
}) {
  final allowed = switch (auth) {
    AuthStarting() => const [Routes.splash],
    AuthSignedOut() when !onboardingSeen => const [Routes.onboarding],
    AuthSignedOut() => const [Routes.login],
    AuthNeedsProfile() => const [Routes.welcome],
    AuthSignedIn() => const [
      Routes.home,
      Routes.search,
      Routes.orders,
      Routes.profile,
      Routes.shops,
      Routes.products,
      Routes.cart,
      Routes.checkout,
    ],
    AuthOffline() => const [Routes.offline],
  };
  final ok = allowed.any((a) => location == a || location.startsWith('$a/'));
  return ok ? null : allowed.first;
}

final routerProvider = Provider<GoRouter>((ref) {
  // go_router relit la règle à chaque changement de session ou de présentation.
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(onboardingSeenProvider, (_, _) => refresh.value++);

  // Fiches au-dessus de la barre du bas.
  final rootKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootKey,
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
      ...authRoutes(),
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) => const ProfileScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => BuyerShell(shell: shell),
        branches: [
          for (final (path, screen) in [
            (Routes.home, const HomeScreen()),
            (Routes.search, const SearchScreen()),
            (Routes.orders, const OrdersScreen()),
            (Routes.profile, const ProfileTabScreen()),
          ])
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: path,
                  builder: (context, state) => screen,
                  routes: [
                    // Changement de mot de passe au-dessus de la barre.
                    if (path == Routes.profile)
                      GoRoute(
                        path: 'password',
                        parentNavigatorKey: rootKey,
                        builder: (context, state) =>
                            const ChangePasswordScreen(),
                      ),
                    // Suivi au-dessus de la barre du bas ; « retour » revient
                    // à l'onglet Commandes.
                    if (path == Routes.orders)
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: rootKey,
                        builder: (context, state) =>
                            OrderScreen(orderId: state.pathParameters['id']!),
                        routes: [
                          GoRoute(
                            path: 'pay',
                            parentNavigatorKey: rootKey,
                            builder: (context, state) => PaymentScreen(
                              orderId: state.pathParameters['id']!,
                              operator: PaymentOperator.parse(
                                state.uri.queryParameters['operator'] ?? '',
                              ),
                            ),
                          ),
                          GoRoute(
                            path: 'payments/:paymentId',
                            parentNavigatorKey: rootKey,
                            builder: (context, state) => PaymentWaitScreen(
                              orderId: state.pathParameters['id']!,
                              paymentId: state.pathParameters['paymentId']!,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
        ],
      ),
      GoRoute(
        path: '${Routes.shops}/:id',
        parentNavigatorKey: rootKey,
        builder: (context, state) =>
            ShopScreen(shopId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '${Routes.products}/:id',
        parentNavigatorKey: rootKey,
        builder: (context, state) =>
            ProductScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.checkout,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: Routes.cart,
        parentNavigatorKey: rootKey,
        builder: (context, state) => const CartScreen(),
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
