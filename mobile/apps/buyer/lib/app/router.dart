import 'package:flutter/material.dart' show MaterialPage;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../features/cart/cart_screen.dart';
import '../features/checkout/checkout_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/orders/order_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/pharmacy/alert_screen.dart';
import '../features/pharmacy/new_alert_screen.dart';
import '../features/pharmacy/pharmacy_hub_screen.dart';
import '../features/pharmacy/reservation_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/payment/payment_screen.dart';
import '../features/payment/payment_wait_screen.dart';
import '../features/product/product_screen.dart';
import '../features/profile/profile_tab_screen.dart';
import '../features/search/search_screen.dart';
import '../features/services/services_screens.dart';
import '../features/shell/buyer_shell.dart';
import '../features/shop/shop_screen.dart';
import '../features/splash/loading_screen.dart';

abstract final class Routes {
  static const splash = '/';

  /// Autorisation de la localisation, juste après le splash (spec 030).
  static const location = '/location';
  static const onboarding = '/onboarding';
  static const login = AuthRoutes.login;
  static const code = AuthRoutes.code;
  static const signup = AuthRoutes.signup;

  /// « Faisons connaissance » : profil à compléter après la connexion.
  static const welcome = '/welcome';
  static const offline = '/offline';

  // Onglets.
  static const home = '/home';
  static const search = '/search';
  static const orders = '/orders';
  static const profile = '/profile';

  // Fiches, par-dessus la barre du bas.
  static const shops = '/shops';
  static const products = '/products';
  static String shop(String id) => '$shops/$id';
  static String product(String id) => '$products/$id';
  static const cart = '/cart';
  static const notifications = '/notifications';

  // Alerte médicament (P01 à P14).
  static const pharmacy = '/pharmacy';
  static const restaurants = '/restaurants';
  static const properties = '/properties';
  static String property(String id) => '/properties/$id';
  static const medNewAlert = '/pharmacy/new';
  static const medItems = '/pharmacy/new/items';
  static String medCapture(String kind) => '/pharmacy/new/capture/$kind';
  static const medReview = '/pharmacy/new/review';
  static const medLaunch = '/pharmacy/new/launch';
  static const medMap = '/pharmacy/map';
  static String medAlert(String id) => '/pharmacy/alerts/$id';
  static String medResponses(String id) => '/pharmacy/alerts/$id/responses';
  static String medUnlock(String alertId, String responseId) =>
      '/pharmacy/alerts/$alertId/unlock/$responseId';
  static String medReservation(String id) => '/pharmacy/reservations/$id';
  static String medPickup(String id) => '/pharmacy/reservations/$id/pickup';
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
  bool locationPromptDone = true,
}) {
  final allowed = switch (auth) {
    AuthStarting() => const [Routes.splash],
    // Après le splash, avant tout le reste : une fois (spec 030).
    _ when !locationPromptDone => const [Routes.location],
    AuthSignedOut() when !onboardingSeen => const [Routes.onboarding],
    AuthSignedOut() => const [Routes.login, Routes.code, Routes.signup],
    AuthNeedsProfile() => const [Routes.welcome],
    AuthSignedIn() => const [
      Routes.home,
      Routes.search,
      Routes.orders,
      Routes.profile,
      Routes.shops,
      Routes.products,
      Routes.cart,
      Routes.notifications,
      Routes.checkout,
      Routes.pharmacy,
      Routes.restaurants,
      Routes.properties,
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
  ref.listen(locationPromptDoneProvider, (_, _) => refresh.value++);

  // Fiches au-dessus de la barre du bas.
  final rootKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      ref.read(authControllerProvider),
      onboardingSeen: ref.read(onboardingSeenProvider),
      locationPromptDone: ref.read(locationPromptDoneProvider),
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: Routes.splash,
        pageBuilder: (context, state) => _page(state, const LoadingScreen()),
      ),
      GoRoute(
        path: Routes.location,
        pageBuilder: (context, state) =>
            _page(state, const LaunchLocationPromptScreen()),
      ),
      GoRoute(
        path: Routes.onboarding,
        pageBuilder: (context, state) => _page(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: Routes.login,
        // Connexion par numéro : numéro, code (WhatsApp ou SMS), puis
        // « Faisons connaissance » pour un numéro nouveau.
        pageBuilder: (context, state) => _page(state, const PhoneScreen()),
        routes: [
          // Sous /login : le retour depuis le code revient au numéro.
          GoRoute(
            path: 'code',
            pageBuilder: (context, state) =>
                _page(state, const PhoneCodeScreen()),
          ),
          GoRoute(
            path: 'signup',
            pageBuilder: (context, state) =>
                _page(state, const PhoneSignupScreen()),
          ),
        ],
      ),
      GoRoute(
        path: Routes.welcome,
        pageBuilder: (context, state) => _page(state, const ProfileScreen()),
      ),
      StatefulShellRoute(
        navigatorContainerBuilder: (context, shell, children) =>
            IviaTabSwitcher(index: shell.currentIndex, children: children),
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
                  pageBuilder: (context, state) => _page(state, screen),
                  routes: [
                    // Suivi au-dessus de la barre du bas ; « retour » revient
                    // à l'onglet Commandes.
                    if (path == Routes.orders)
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: rootKey,
                        pageBuilder: (context, state) => _page(
                          state,
                          OrderScreen(orderId: state.pathParameters['id']!),
                        ),
                        routes: [
                          GoRoute(
                            path: 'pay',
                            parentNavigatorKey: rootKey,
                            pageBuilder: (context, state) => _page(
                              state,
                              PaymentScreen(
                                orderId: state.pathParameters['id']!,
                                operator: PaymentOperator.parse(
                                  state.uri.queryParameters['operator'] ?? '',
                                ),
                              ),
                            ),
                          ),
                          GoRoute(
                            path: 'payments/:paymentId',
                            parentNavigatorKey: rootKey,
                            pageBuilder: (context, state) => _page(
                              state,
                              PaymentWaitScreen(
                                orderId: state.pathParameters['id']!,
                                paymentId: state.pathParameters['paymentId']!,
                              ),
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
        pageBuilder: (context, state) =>
            _page(state, ShopScreen(shopId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '${Routes.products}/:id',
        parentNavigatorKey: rootKey,
        pageBuilder: (context, state) =>
            _page(state, ProductScreen(productId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: Routes.checkout,
        parentNavigatorKey: rootKey,
        pageBuilder: (context, state) => _page(state, const CheckoutScreen()),
      ),
      GoRoute(
        path: Routes.pharmacy,
        parentNavigatorKey: rootKey,
        pageBuilder: (context, state) =>
            _page(state, const PharmacyHubScreen()),
        routes: [
          GoRoute(
            path: 'map',
            parentNavigatorKey: rootKey,
            pageBuilder: (context, state) =>
                _page(state, const OnDutyMapScreen()),
          ),
          GoRoute(
            path: 'new',
            parentNavigatorKey: rootKey,
            pageBuilder: (context, state) =>
                _page(state, const NewAlertScreen()),
            routes: [
              GoRoute(
                path: 'items',
                parentNavigatorKey: rootKey,
                pageBuilder: (context, state) =>
                    _page(state, const AlertItemsScreen()),
              ),
              GoRoute(
                path: 'capture/:kind',
                parentNavigatorKey: rootKey,
                pageBuilder: (context, state) => _page(
                  state,
                  AlertCaptureScreen(kind: state.pathParameters['kind']!),
                ),
              ),
              GoRoute(
                path: 'review',
                parentNavigatorKey: rootKey,
                pageBuilder: (context, state) =>
                    _page(state, const AlertReviewScreen()),
              ),
              GoRoute(
                path: 'launch',
                parentNavigatorKey: rootKey,
                pageBuilder: (context, state) =>
                    _page(state, const AlertLaunchScreen()),
              ),
            ],
          ),
          GoRoute(
            path: 'alerts/:id',
            parentNavigatorKey: rootKey,
            pageBuilder: (context, state) =>
                _page(state, AlertScreen(alertId: state.pathParameters['id']!)),
            routes: [
              GoRoute(
                path: 'responses',
                parentNavigatorKey: rootKey,
                pageBuilder: (context, state) => _page(
                  state,
                  ResponsesScreen(alertId: state.pathParameters['id']!),
                ),
              ),
              GoRoute(
                path: 'unlock/:responseId',
                parentNavigatorKey: rootKey,
                pageBuilder: (context, state) => _page(
                  state,
                  UnlockScreen(
                    alertId: state.pathParameters['id']!,
                    responseId: state.pathParameters['responseId']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'reservations/:id',
            parentNavigatorKey: rootKey,
            pageBuilder: (context, state) => _page(
              state,
              ReservationScreen(reservationId: state.pathParameters['id']!),
            ),
            routes: [
              GoRoute(
                path: 'pickup',
                parentNavigatorKey: rootKey,
                pageBuilder: (context, state) => _page(
                  state,
                  PickupScreen(reservationId: state.pathParameters['id']!),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.restaurants,
        parentNavigatorKey: rootKey,
        pageBuilder: (context, state) =>
            _page(state, const RestaurantsScreen()),
      ),
      GoRoute(
        path: Routes.properties,
        parentNavigatorKey: rootKey,
        pageBuilder: (context, state) => _page(state, const PropertiesScreen()),
        routes: [
          GoRoute(
            path: ':id',
            parentNavigatorKey: rootKey,
            pageBuilder: (context, state) => _page(
              state,
              PropertyScreen(propertyId: state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.notifications,
        parentNavigatorKey: rootKey,
        pageBuilder: (context, state) =>
            _page(state, const NotificationsScreen()),
      ),
      GoRoute(
        path: Routes.cart,
        parentNavigatorKey: rootKey,
        pageBuilder: (context, state) => _page(state, const CartScreen()),
      ),
      GoRoute(
        path: Routes.offline,
        pageBuilder: (context, state) => _page(state, const OfflineScreen()),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// Page avec la transition d'écran ivia : sans elle, go_router peut créer des
/// pages sans aucune animation (elles apparaissent d'un coup).
MaterialPage<void> _page(GoRouterState state, Widget child) =>
    MaterialPage<void>(
      key: state.pageKey,
      name: state.name ?? state.path,
      child: child,
    );
