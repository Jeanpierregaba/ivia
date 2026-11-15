import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_buyer/app/router.dart';

void main() {
  group('redirections', () {
    final user = User.fromJson(userBody(complete: true));
    String? go(AuthState s, String location, {bool seen = true}) =>
        redirectFor(s, onboardingSeen: seen, location: location);

    test("écran de localisation : après le splash, avant tout", () {
      for (final s in [const AuthSignedOut(), AuthSignedIn(user)]) {
        expect(
          redirectFor(
            s,
            onboardingSeen: false,
            location: Routes.home,
            locationPromptDone: false,
          ),
          Routes.location,
        );
      }
      expect(
        redirectFor(
          const AuthStarting(),
          onboardingSeen: false,
          location: Routes.home,
          locationPromptDone: false,
        ),
        Routes.splash,
      );
    });

    test('chaque état mène à son écran', () {
      expect(go(const AuthStarting(), Routes.home), Routes.splash);
      expect(
        go(const AuthSignedOut(), Routes.splash, seen: false),
        Routes.onboarding,
      );
      expect(go(const AuthSignedOut(), Routes.splash), Routes.login);
      expect(go(const AuthSignedOut(), Routes.home), Routes.login);
      expect(go(AuthNeedsProfile(user), Routes.login), Routes.welcome);
      expect(go(AuthSignedIn(user), Routes.code), Routes.home);
      expect(go(const AuthOffline(), Routes.home), Routes.offline);
    });

    test('écrans permis : pas de redirection', () {
      expect(go(const AuthStarting(), Routes.splash), isNull);
      expect(go(const AuthSignedOut(), Routes.onboarding, seen: false), isNull);
      expect(go(const AuthSignedOut(), Routes.login), isNull);
      expect(go(const AuthSignedOut(), Routes.code), isNull);
      expect(go(const AuthSignedOut(), Routes.signup), isNull);
      expect(go(AuthNeedsProfile(user), Routes.welcome), isNull);
      expect(
        go(AuthNeedsProfile(user), Routes.profile),
        Routes.welcome,
        reason: 'profil incomplet : onglets fermés',
      );
      expect(go(AuthSignedIn(user), Routes.home), isNull);
    });

    test('connecté : onglets et fiches, préfixe exact', () {
      final signedIn = AuthSignedIn(user);
      for (final location in [
        Routes.home,
        Routes.search,
        Routes.orders,
        Routes.profile,
        Routes.shop('s1'),
        Routes.product('p1'),
      ]) {
        expect(go(signedIn, location), isNull, reason: location);
      }
      expect(go(signedIn, Routes.welcome), Routes.home);
      expect(go(signedIn, '/shopsx'), Routes.home);
      expect(go(const AuthSignedOut(), Routes.product('p1')), Routes.login);
    });
  });
}
