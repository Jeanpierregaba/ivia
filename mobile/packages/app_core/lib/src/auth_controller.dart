import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

import 'providers.dart';

/// État de la session : il décide de l'écran affiché (voir router.dart).
sealed class AuthState {
  const AuthState();
}

/// Démarrage en cours (splash de chargement).
final class AuthStarting extends AuthState {
  const AuthStarting();
}

final class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

/// Connecté, profil ou consentement manquant : « Faisons connaissance ».
final class AuthNeedsProfile extends AuthState {
  const AuthNeedsProfile(this.user);

  final User user;
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);

  final User user;
}

/// Session gardée mais serveur injoignable, sans profil sur le téléphone.
final class AuthOffline extends AuthState {
  const AuthOffline();
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  IviaApiClient get _client => ref.read(apiClientProvider);
  SessionStore get _store => ref.read(sessionStoreProvider);

  /// Change à chaque ouverture ou fermeture de session : une réponse arrivée
  /// après coup (retour pendant l'envoi du profil…) est ignorée.
  var _generation = 0;

  @override
  AuthState build() {
    final client = _client
      ..onUnauthorized = _onUnauthorized
      ..onTokensRefreshed = _onTokensRefreshed;
    ref.onDispose(() {
      client
        ..onUnauthorized = null
        ..onTokensRefreshed = null;
    });
    unawaited(_start());
    return const AuthStarting();
  }

  /// Hors ligne : nouvelle tentative de démarrage.
  Future<void> retry() async {
    state = const AuthStarting();
    await _start();
  }

  /// Code vérifié : la session est gardée sur le téléphone.
  Future<void> signedIn(Session session) async {
    _generation++;
    await _store.save(
      session.token,
      session.user,
      refreshToken: session.refreshToken,
    );
    _client
      ..token = session.token
      ..refreshToken = session.refreshToken;
    state = _fromUser(session.user);
  }

  /// Sans effet si la session a été fermée pendant l'envoi.
  Future<void> profileUpdated(User user) async {
    if (state is! AuthNeedsProfile && state is! AuthSignedIn) return;
    final generation = _generation;
    await _store.saveUser(user);
    if (generation == _generation && ref.mounted) state = _fromUser(user);
  }

  /// Révoque la session côté serveur si possible, puis l'efface du téléphone
  /// dans tous les cas.
  Future<void> signOut() async {
    try {
      await _client.logout();
    } on ApiException {
      // Serveur injoignable : la session expirera d'elle-même.
    }
    await _clear();
  }

  Future<void> _start() async {
    final generation = _generation;
    final timings = ref.read(authTimingsProvider);
    final results = await Future.wait([
      _restore(timings.meTimeout),
      Future<AuthState?>.delayed(timings.minSplash),
    ]);
    if (generation == _generation && ref.mounted) state = results.first!;
  }

  Future<AuthState> _restore(Duration meTimeout) async {
    final stored = await _store.read();
    if (stored == null) return const AuthSignedOut();
    _client
      ..token = stored.token
      ..refreshToken = stored.refreshToken;
    try {
      final user = await _client.getMe().timeout(meTimeout);
      await _store.saveUser(user);
      return _fromUser(user);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _clearStorage();
        return const AuthSignedOut();
      }
      return _offline(stored.user);
    } on TimeoutException {
      return _offline(stored.user);
    } on Exception {
      // Réponse inattendue : comme un serveur injoignable, sans bloquer.
      return _offline(stored.user);
    }
  }

  static AuthState _offline(User? cached) =>
      cached == null ? const AuthOffline() : _fromUser(cached);

  static AuthState _fromUser(User user) =>
      user.profileComplete ? AuthSignedIn(user) : AuthNeedsProfile(user);

  /// Jetons renouvelés par le client : gardés pour le prochain démarrage.
  void _onTokensRefreshed(Session session) {
    unawaited(_store.saveTokens(session.token, session.refreshToken));
  }

  void _onUnauthorized() {
    // Au démarrage, _restore traite lui-même le refus.
    if (state is! AuthStarting) unawaited(_clear());
  }

  Future<void> _clear() async {
    _generation++;
    await _clearStorage();
    if (ref.mounted) state = const AuthSignedOut();
  }

  Future<void> _clearStorage() async {
    _client
      ..token = null
      ..refreshToken = null;
    await _store.clear();
  }
}
