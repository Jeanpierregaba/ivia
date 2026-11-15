import 'package:flutter/material.dart' show MaterialPage;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_ui/ivia_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../features/account/account_screen.dart';
import '../features/business/business_screens.dart';
import '../features/catalog/catalog_screen.dart';
import '../features/catalog/product_edit_screen.dart';
import '../features/catalog/product_editor_screen.dart';
import '../features/catalog/product_published_screen.dart';
import '../features/home/home_screen.dart';
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
import 'business_state.dart';
import 'seller_shop.dart';

abstract final class Routes {
  static const splash = '/';

  /// Autorisation de la localisation, juste après le splash (spec 030).
  static const location = '/location';
  static const onboarding = '/onboarding';
  static const login = AuthRoutes.login;
  static const code = AuthRoutes.code;
  static const signup = AuthRoutes.signup;
  static const welcome = '/welcome';
  static const businessNew = '/business/new';
  static const businessChoose = '/business/choose';
  static const businessDossier = '/business/dossier';
  static const businessStatus = '/business/status';
  static const businessModule = '/business/module';
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
  bool locationPromptDone = true,
  AsyncValue<BusinessGate>? business,
}) {
  final allowed = switch (auth) {
    AuthStarting() => const [Routes.splash],
    // Après le splash, avant tout le reste : une fois (spec 030).
    _ when !locationPromptDone => const [Routes.location],
    AuthSignedOut() when !onboardingSeen => const [Routes.onboarding],
    AuthSignedOut() => const [Routes.login, Routes.code, Routes.signup],
    AuthOffline() => const [Routes.offline],
    AuthNeedsProfile() when business != null => const [Routes.welcome],
    AuthSignedIn() when business != null => _spaceScreens(business, shop),
    AuthSignedIn() || AuthNeedsProfile() => _shopScreens(shop),
  };
  final ok = allowed.any((a) => location == a || location.startsWith('$a/'));
  return ok ? null : allowed.first;
}

/// Workflow de connexion Ivia Business : aucun espace, inscription ; plusieurs
/// espaces, choix ; puis les écrans découlent du statut de l'espace ouvert.
List<String> _spaceScreens(
  AsyncValue<BusinessGate> business,
  AsyncValue<Shop?> shop,
) {
  if (business.hasError) return const [Routes.offline];
  if (business.isLoading) return const [Routes.splash];
  final gate = business.value ?? const BusinessGate();
  final opened = gate.opened;
  if (opened == null) {
    return gate.spaces.isEmpty
        ? const [Routes.businessNew]
        : const [Routes.businessChoose, Routes.businessNew];
  }
  return switch (opened.status) {
    'active' when opened.usesShop => _shopScreens(shop),
    'active' => const [Routes.businessModule],
    'pending_review' when opened.usesShop => const [
      Routes.businessStatus,
      Routes.catalog,
    ],
    'pending_review' => const [Routes.businessStatus, Routes.businessModule],
    'suspended' => const [Routes.businessStatus],
    _ => const [Routes.businessDossier],
  };
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
  ref.listen(businessGateProvider, (_, _) => refresh.value++);
  ref.listen(onboardingSeenProvider, (_, _) => refresh.value++);
  ref.listen(locationPromptDoneProvider, (_, _) => refresh.value++);

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
      locationPromptDone: ref.read(locationPromptDoneProvider),
      location: state.matchedLocation,
      business: ref.read(businessGateProvider),
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
        pageBuilder: (context, state) => _page(state, const PhoneScreen()),
        routes: [
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
        path: Routes.offline,
        pageBuilder: (context, state) => _page(state, const OfflineScreen()),
      ),
      GoRoute(
        path: Routes.welcome,
        pageBuilder: (_, state) => _page(state, const ProfileScreen()),
      ),
      GoRoute(
        path: Routes.businessNew,
        pageBuilder: (_, state) => _page(state, const SectorScreen()),
      ),
      GoRoute(
        path: Routes.businessChoose,
        pageBuilder: (_, state) => _page(state, const ChooseSpaceScreen()),
      ),
      GoRoute(
        path: Routes.businessDossier,
        pageBuilder: (_, state) => _page(state, const DossierScreen()),
      ),
      GoRoute(
        path: Routes.businessStatus,
        pageBuilder: (_, state) => _page(state, const BusinessStatusScreen()),
      ),
      GoRoute(
        path: Routes.businessModule,
        pageBuilder: (_, state) => _page(state, const BusinessModuleScreen()),
      ),
      GoRoute(
        path: Routes.shopNew,
        pageBuilder: (context, state) => _page(state, const ShopFormScreen()),
      ),
      GoRoute(
        path: Routes.shopPending,
        pageBuilder: (context, state) =>
            _page(state, const ShopPendingScreen()),
        routes: [
          GoRoute(
            path: 'documents',
            pageBuilder: (context, state) =>
                _page(state, const ShopDocumentsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: Routes.shopBlocked,
        pageBuilder: (context, state) =>
            _page(state, const ShopBlockedScreen()),
      ),
      StatefulShellRoute(
        navigatorContainerBuilder: (context, shell, children) =>
            IviaTabSwitcher(index: shell.currentIndex, children: children),
        builder: (context, state, shell) => SellerShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                pageBuilder: (context, state) =>
                    _page(state, const HomeScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.orders,
                pageBuilder: (context, state) => _page(
                  state,
                  OrdersScreen(
                    tab: OrderTab.parse(state.uri.queryParameters['tab']),
                  ),
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: rootKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      OrderScreen(orderId: state.pathParameters['id']!),
                    ),
                    routes: [
                      GoRoute(
                        path: 'handover',
                        parentNavigatorKey: rootKey,
                        pageBuilder: (context, state) => _page(
                          state,
                          HandoverScreen(orderId: state.pathParameters['id']!),
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
                pageBuilder: (context, state) =>
                    _page(state, const CatalogScreen()),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: rootKey,
                    pageBuilder: (context, state) =>
                        _page(state, const ProductEditorScreen()),
                  ),
                  GoRoute(
                    path: 'published',
                    parentNavigatorKey: rootKey,
                    // Écran rouvert sans produit (restauration, lien) :
                    // retour au catalogue, dans ses onglets.
                    redirect: (context, state) =>
                        state.extra is Product ? null : Routes.catalog,
                    pageBuilder: (context, state) => _page(
                      state,
                      ProductPublishedScreen(product: state.extra! as Product),
                    ),
                  ),
                  GoRoute(
                    path: 'draft/:id',
                    parentNavigatorKey: rootKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      ProductEditorScreen(
                        productId: state.pathParameters['id'],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: ':id/edit',
                    parentNavigatorKey: rootKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      ProductEditScreen(productId: state.pathParameters['id']!),
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
                pageBuilder: (context, state) =>
                    _page(state, const AccountScreen()),
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

/// Page avec la transition d'écran ivia : sans elle, go_router peut créer des
/// pages sans aucune animation (elles apparaissent d'un coup).
MaterialPage<void> _page(GoRouterState state, Widget child) =>
    MaterialPage<void>(
      key: state.pageKey,
      name: state.name ?? state.path,
      child: child,
    );
