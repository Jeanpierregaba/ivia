import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../features/account/account_screen.dart';
import '../features/catalog/catalog_screen.dart';
import '../features/catalog/product_edit_screen.dart';
import '../features/catalog/product_editor_screen.dart';
import '../features/catalog/product_published_screen.dart';
import '../features/home/home_placeholder_screen.dart';
import '../features/orders/handover_screen.dart';
import '../features/orders/order_labels.dart';
import '../features/orders/order_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/shell/seller_shell.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/shop/shop_blocked_screen.dart';
import '../features/shop/shop_documents_screen.dart';
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
  static const shopDocuments = '/shop/pending/documents';
  static const shopBlocked = '/shop/blocked';
  static const home = '/home';
  static const orders = '/orders';
  static const catalog = '/catalog';
  static const account = '/account';
  static const productNew = '/catalog/new';
  static const productPublished = '/catalog/published';
  static String productDraft(String id) => '/catalog/draft/$id';
  static String productEdit(String id) => '/catalog/$id/edit';

  /// Onglet Commandes ouvert sur [tab].
  static String ordersTab(OrderTab tab) => '/orders?tab=${tab.code}';
  static String order(String id) => '/orders/$id';
  static String handover(String id) => '/orders/$id/handover';
}

/// Écrans permis selon la session et la boutique ; le premier est la
/// destination par défaut. Un écran hors de la liste n'est jamais affiché ;
/// une entrée permet aussi ses sous-écrans (`/catalog` permet
/// `/catalog/new`).
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
  final ok = allowed.any((a) => location == a || location.startsWith('$a/'));
  return ok ? null : allowed.first;
}

List<String> _shopScreens(AsyncValue<Shop?> shop) {
  // Riverpod garde l'ancienne valeur pendant un rechargement ou après une
  // erreur : l'erreur et le chargement passent donc avant la valeur.
  if (shop.hasError) return const [Routes.offline];
  if (shop.isLoading) return const [Routes.splash];
  return switch (shop.value?.status) {
    null => const [Routes.shopNew],
    // En attente de validation : les produits se préparent déjà.
    ShopStatus.pendingReview => const [Routes.shopPending, Routes.catalog],
    ShopStatus.published => const [
      Routes.home,
      Routes.orders,
      Routes.catalog,
      Routes.account,
    ],
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

  // Formulaires produit au-dessus de la barre du bas.
  final rootKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootKey,
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
        routes: [
          GoRoute(
            path: 'documents',
            builder: (context, state) => const ShopDocumentsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.shopBlocked,
        builder: (context, state) => const ShopBlockedScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => SellerShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomePlaceholderScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.orders,
                builder: (context, state) => OrdersScreen(
                  tab: OrderTab.parse(state.uri.queryParameters['tab']),
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: rootKey,
                    builder: (context, state) =>
                        OrderScreen(orderId: state.pathParameters['id']!),
                    routes: [
                      GoRoute(
                        path: 'handover',
                        parentNavigatorKey: rootKey,
                        builder: (context, state) => HandoverScreen(
                          orderId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.catalog,
                builder: (context, state) => const CatalogScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: rootKey,
                    builder: (context, state) => const ProductEditorScreen(),
                  ),
                  GoRoute(
                    path: 'published',
                    parentNavigatorKey: rootKey,
                    // Écran rouvert sans produit (restauration, lien) :
                    // retour au catalogue, dans ses onglets.
                    redirect: (context, state) =>
                        state.extra is Product ? null : Routes.catalog,
                    builder: (context, state) => ProductPublishedScreen(
                      product: state.extra! as Product,
                    ),
                  ),
                  GoRoute(
                    path: 'draft/:id',
                    parentNavigatorKey: rootKey,
                    builder: (context, state) => ProductEditorScreen(
                      productId: state.pathParameters['id'],
                    ),
                  ),
                  GoRoute(
                    path: ':id/edit',
                    parentNavigatorKey: rootKey,
                    builder: (context, state) => ProductEditScreen(
                      productId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.account,
                builder: (context, state) => const AccountScreen(),
              ),
            ],
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
