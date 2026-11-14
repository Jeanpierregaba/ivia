/// Routes de la connexion par numéro (ADR 0012), communes aux apps. Tout est
/// sous `/login` : la règle de redirection d'une app déconnectée n'a qu'une
/// entrée.
abstract final class AuthRoutes {
  static const login = '/login';

  /// Sous /login : le retour depuis le code revient au numéro.
  static const code = '/login/code';

  /// Numéro nouveau : prénom, nom et consentement.
  static const signup = '/login/signup';
}
