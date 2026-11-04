import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_seller/app/router.dart';

void main() {
  final user = User.fromJson(userBody(complete: true));
  Shop shop(String status) => Shop.fromJson(shopBody(status: status));

  String? go(
    AuthState auth,
    String location, {
    AsyncValue<Shop?> shopState = const AsyncData(null),
    bool seen = true,
  }) => redirectFor(auth, shopState, onboardingSeen: seen, location: location);

  test('session : splash, présentation, connexion, hors ligne', () {
    expect(go(const AuthStarting(), Routes.home), Routes.splash);
    expect(
      go(const AuthSignedOut(), Routes.splash, seen: false),
      Routes.onboarding,
    );
    expect(go(const AuthSignedOut(), Routes.home), Routes.login);
    expect(go(const AuthSignedOut(), AuthRoutes.signupPassword), isNull);
    expect(go(const AuthSignedOut(), AuthRoutes.forgotCode), isNull);
    expect(go(const AuthOffline(), Routes.home), Routes.offline);
  });

  test('connecté : écran selon la boutique', () {
    final signedIn = AuthSignedIn(user);
    expect(
      go(signedIn, Routes.home, shopState: const AsyncLoading()),
      Routes.splash,
    );
    expect(
      go(
        signedIn,
        Routes.home,
        shopState: AsyncError<Shop?>(Exception(), StackTrace.empty),
      ),
      Routes.offline,
    );
    expect(go(signedIn, Routes.home), Routes.shopNew);
    expect(
      go(AuthNeedsProfile(user), Routes.login),
      Routes.shopNew,
      reason: 'profil incomplet : la boutique suffit au marchand',
    );
    expect(
      go(signedIn, Routes.home, shopState: AsyncData(shop('pending_review'))),
      Routes.shopPending,
    );
    // En attente de validation : le catalogue et ses sous-écrans, sans le
    // reste des onglets.
    final pending = AsyncData<Shop?>(shop('pending_review'));
    for (final location in [
      Routes.catalog,
      Routes.productNew,
      Routes.productDraft('p1'),
      Routes.productEdit('p1'),
    ]) {
      expect(
        go(signedIn, location, shopState: pending),
        isNull,
        reason: location,
      );
    }
    expect(go(signedIn, Routes.orders, shopState: pending), Routes.shopPending);
    expect(
      go(signedIn, Routes.account, shopState: pending),
      Routes.shopPending,
    );
    // Préfixe exact : « /catalogue » n'est pas un sous-écran de « /catalog ».
    expect(go(signedIn, '/catalogue', shopState: pending), Routes.shopPending);

    final published = AsyncData<Shop?>(shop('published'));
    expect(go(signedIn, Routes.shopNew, shopState: published), Routes.home);
    for (final location in [
      Routes.home,
      Routes.orders,
      Routes.catalog,
      Routes.account,
      Routes.productPublished,
      Routes.productEdit('p1'),
    ]) {
      expect(
        go(signedIn, location, shopState: published),
        isNull,
        reason: location,
      );
    }
    expect(go(signedIn, Routes.shopPending, shopState: published), Routes.home);
    for (final status in ['rejected', 'suspended']) {
      expect(
        go(signedIn, Routes.home, shopState: AsyncData(shop(status))),
        Routes.shopBlocked,
      );
      expect(
        go(signedIn, Routes.productNew, shopState: AsyncData(shop(status))),
        Routes.shopBlocked,
        reason: 'boutique $status : plus de catalogue',
      );
    }
  });
}
