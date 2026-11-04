import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_driver/app/router.dart';

void main() {
  final user = User.fromJson(userBody(complete: true));
  DriverDossier dossier({String review = 'pending_review', String? status}) =>
      DriverDossier.fromJson(
        driverBody(review: review, status: status ?? review),
      );

  String? go(
    AuthState auth,
    String location, {
    AsyncValue<DriverDossier?> state = const AsyncData(null),
    bool seen = true,
  }) => redirectFor(auth, state, onboardingSeen: seen, location: location);

  test('session : splash, présentation, connexion, hors ligne', () {
    expect(go(const AuthStarting(), Routes.home), Routes.splash);
    expect(
      go(const AuthSignedOut(), Routes.splash, seen: false),
      Routes.onboarding,
    );
    expect(go(const AuthSignedOut(), Routes.home), Routes.login);
    // Connexion : /login et ses sous-écrans seulement.
    expect(go(const AuthSignedOut(), AuthRoutes.signupCode), isNull);
    expect(go(const AuthSignedOut(), AuthRoutes.forgotPassword), isNull);
    expect(go(const AuthOffline(), Routes.home), Routes.offline);
  });

  test('connecté : écran selon le dossier', () {
    final signedIn = AuthSignedIn(user);
    expect(
      go(signedIn, Routes.home, state: const AsyncLoading()),
      Routes.splash,
    );
    expect(
      go(
        signedIn,
        Routes.home,
        state: AsyncError<DriverDossier?>(Exception(), StackTrace.empty),
      ),
      Routes.offline,
    );
    expect(go(signedIn, Routes.home), Routes.dossierNew);
    expect(
      go(AuthNeedsProfile(user), Routes.home),
      Routes.dossierNew,
      reason: 'profil incomplet : demandé dans le dossier',
    );
    final pending = AsyncData<DriverDossier?>(dossier());
    expect(go(signedIn, Routes.home, state: pending), Routes.dossierPending);
    expect(go(signedIn, Routes.dossierSummary, state: pending), isNull);
    // Dossier en vérification : il reste modifiable (pièces manquantes).
    expect(go(signedIn, Routes.dossierEdit, state: pending), isNull);
    final rejected = AsyncData<DriverDossier?>(dossier(review: 'rejected'));
    expect(go(signedIn, Routes.home, state: rejected), Routes.dossierBlocked);
    expect(go(signedIn, Routes.dossierEdit, state: rejected), isNull);
    expect(
      go(
        signedIn,
        Routes.home,
        state: AsyncData(dossier(review: 'approved', status: 'suspended')),
      ),
      Routes.dossierBlocked,
    );
    expect(
      go(
        signedIn,
        Routes.dossierNew,
        state: AsyncData(dossier(review: 'approved', status: 'offline')),
      ),
      Routes.home,
    );
  });
}
