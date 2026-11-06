import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_app_core/testing.dart';
import 'package:ivia_pharmacy/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Titre de l'écran de localisation de la pharmacie (spec 030).
const locationTitle = 'Les alertes de votre quartier';

/// App pharmacie branchée sur un serveur factice.
class PharmacyHarness {
  PharmacyHarness({LocationAccess location = LocationAccess.askable})
    : location = FakeLocationService(state: location);

  final server = FakeApiServer();
  final FakeLocationService location;

  /// Réglages du téléphone et session vides (à appeler dans `setUp`).
  static void resetDevice({Map<String, Object> prefs = const {}}) {
    SharedPreferences.setMockInitialValues(prefs);
    FlutterSecureStorage.setMockInitialValues({});
  }

  /// Compte connecté, profil complet, écran de localisation déjà passé.
  Future<void> signIn() async {
    SharedPreferences.setMockInitialValues({'location_prompt_done': true});
    await SessionStore().save(
      'jeton-secret',
      User.fromJson(userBody(complete: true)),
    );
    server.on(
      'GET',
      '/v1/me',
      (_) => FakeResponse.json(200, userBody(complete: true)),
    );
  }

  Future<void> launch(WidgetTester tester) async {
    final locationPrompt = await LocationPromptStore.open(location);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appIdentityProvider.overrideWithValue(pharmacyIdentity),
          locationServiceProvider.overrideWithValue(location),
          locationPromptStoreProvider.overrideWithValue(locationPrompt),
          apiClientProvider.overrideWithValue(
            IviaApiClient(
              config: ApiConfig(baseUrl: Uri.parse('http://api.test')),
              adapter: server,
            ),
          ),
          authTimingsProvider.overrideWithValue(
            const AuthTimings(
              minSplash: Duration.zero,
              meTimeout: Duration(seconds: 1),
            ),
          ),
        ],
        child: const PharmacyApp(),
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// Touche un texte, en faisant défiler la liste s'il le faut.
Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text);
  // Liste longue : l'élément n'est construit qu'en s'en approchant.
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}
