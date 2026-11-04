/// Outils de test des écrans communs : faux Google (règle 7 d'AGENTS.md).
library;

import 'src/google_auth.dart';

/// Connexion Google simulée : [token] renvoyé (`null` : fenêtre fermée),
/// ou [error] levée.
class FakeGoogleAuth implements GoogleAuth {
  FakeGoogleAuth({this.available = true, this.token = 'jeton-google'});

  @override
  bool available;

  String? token;
  GoogleAuthException? error;
  var calls = 0;

  @override
  Future<String?> signIn() async {
    calls++;
    if (error case final e?) throw e;
    return token;
  }
}
