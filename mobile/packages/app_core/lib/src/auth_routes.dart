/// Routes de la connexion, communes aux apps. Tout est sous `/login` :
/// la règle de redirection d'une app déconnectée n'a qu'une entrée.
abstract final class AuthRoutes {
  static const login = '/login';

  // Connexion par numéro (ADR 0012), montée par chaque app.

  /// Sous /login : le retour depuis le code revient au numéro.
  static const code = '/login/code';

  /// Numéro nouveau : prénom, nom et consentement.
  static const signup = '/login/signup';

  // Connexion par e-mail et mot de passe (ADR 0011), montée par
  // `authRoutes()` pour une app en `LoginMethod.email`.

  static const emailSignup = '/login/signup';
  static const signupCode = '/login/signup/code';
  static const signupPassword = '/login/signup/code/password';
  static const forgot = '/login/forgot';
  static const forgotCode = '/login/forgot/code';
  static const forgotPassword = '/login/forgot/code/password';
}
