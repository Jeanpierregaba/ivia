import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

/// Client de l'API, créé par `main()` (URL fixée à la compilation).
final apiClientProvider = Provider<IviaApiClient>(
  (ref) => throw UnimplementedError('apiClientProvider non fourni'),
);

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// Délais du démarrage (réduits dans les tests).
class AuthTimings {
  const AuthTimings({
    this.minSplash = const Duration(milliseconds: 800),
    this.meTimeout = const Duration(seconds: 5),
  });

  /// Durée minimale du splash de chargement : le slogan doit se lire.
  final Duration minSplash;

  /// Au-delà, le profil gardé sur le téléphone est utilisé.
  final Duration meTimeout;
}

final authTimingsProvider = Provider<AuthTimings>((ref) => const AuthTimings());
