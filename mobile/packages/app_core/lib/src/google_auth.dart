import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Connexion avec Google côté téléphone : obtient le jeton d'identité que le
/// serveur vérifie (ADR 0011). Implémentation réelle ([PluginGoogleAuth]) et
/// fausse pour les tests (règle 7 d'AGENTS.md).
abstract interface class GoogleAuth {
  /// Identifiants fournis à la compilation : sinon le bouton est masqué.
  bool get available;

  /// Ouvre la fenêtre Google ; renvoie le jeton d'identité, ou `null` si
  /// l'utilisateur la ferme. Lève [GoogleAuthException] en cas d'échec.
  Future<String?> signIn();
}

/// Échec de la connexion Google côté téléphone (service absent, réseau,
/// configuration).
class GoogleAuthException implements Exception {
  const GoogleAuthException();
}

/// `google_sign_in` 7 : identifiants lus dans `--dart-define`
/// (`GOOGLE_SERVER_CLIENT_ID` : client OAuth « web » que vérifie le
/// serveur ; `GOOGLE_IOS_CLIENT_ID` : client iOS). Sans eux, indisponible.
class PluginGoogleAuth implements GoogleAuth {
  PluginGoogleAuth({required this.serverClientId, this.clientId});

  factory PluginGoogleAuth.fromEnvironment() => PluginGoogleAuth(
    serverClientId: const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
    clientId: switch (const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID')) {
      '' => null,
      final id => id,
    },
  );

  final String serverClientId;
  final String? clientId;
  Future<void>? _initialized;

  /// Android : le client « web » suffit. iOS : le client iOS aussi (sans
  /// lui, le SDK Google s'arrête au premier appui).
  @override
  bool get available =>
      serverClientId.isNotEmpty &&
      (defaultTargetPlatform != TargetPlatform.iOS || clientId != null);

  @override
  Future<String?> signIn() async {
    if (!available) throw const GoogleAuthException();
    final google = GoogleSignIn.instance;
    try {
      try {
        await (_initialized ??= google.initialize(
          clientId: clientId,
          serverClientId: serverClientId,
        ));
      } on Object {
        // Échec gardé sinon jusqu'au redémarrage : nouvel essai au prochain
        // appui.
        _initialized = null;
        rethrow;
      }
      if (!google.supportsAuthenticate()) throw const GoogleAuthException();
      final account = await google.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) throw const GoogleAuthException();
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw const GoogleAuthException();
    } on GoogleAuthException {
      rethrow;
    } on Exception {
      // Erreur du système (service Google absent…) : même message.
      throw const GoogleAuthException();
    }
  }
}

/// Connexion Google de l'app (remplacée par un faux dans les tests).
final googleAuthProvider = Provider<GoogleAuth>(
  (ref) => PluginGoogleAuth.fromEnvironment(),
);
