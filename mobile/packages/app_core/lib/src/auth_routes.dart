/// Routes de la connexion, communes aux 3 apps.
abstract final class AuthRoutes {
  static const login = '/login';

  /// Sous /login : le retour depuis le code revient à l'e-mail.
  static const code = '/login/code';

  /// Connexion par numéro, numéro nouveau : prénom, nom et consentement.
  static const signup = '/login/signup';
}
