/// Routes de la connexion, communes aux 3 apps. Tout est sous `/login` :
/// la règle de redirection d'une app déconnectée n'a qu'une entrée.
abstract final class AuthRoutes {
  static const login = '/login';

  /// Ancienne connexion par code (001), retirée avec ses écrans (029).
  static const code = '/login/code';

  static const signup = '/login/signup';
  static const signupCode = '/login/signup/code';
  static const signupPassword = '/login/signup/password';
  static const forgot = '/login/forgot';
  static const forgotCode = '/login/forgot/code';
  static const forgotPassword = '/login/forgot/password';
}
