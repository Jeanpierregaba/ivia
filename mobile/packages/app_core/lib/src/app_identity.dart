import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Ce qui distingue une app dans les écrans communs (connexion).
class AppIdentity {
  const AppIdentity({
    required this.brand,
    required this.loginTitle,
    required this.loginBody,
    required this.codeHint,
    this.loginBadge,
    this.loginMethod = LoginMethod.email,
    this.appCode = 'buyer',
    this.authHero,
  });

  /// Connexion par e-mail (v1) ou par numéro (v2, ADR 0012).
  final LoginMethod loginMethod;

  /// Code de l'app envoyé au serveur (alertes de sécurité) : buyer, seller,
  /// driver ou pharmacy.
  final String appCode;

  /// En-tête de l'écran de connexion à la place du logo et du titre communs.
  final WidgetBuilder? authHero;

  final IviaAppBrand brand;

  /// Titre et texte de l'écran e-mail (« Bienvenue sur ivia »…).
  final String loginTitle;
  final String loginBody;

  /// Pastille à côté du logo (« Marchand ») ; aucune pour l'acheteur.
  final String? loginBadge;

  /// Encart de l'écran du code, selon la validité du code.
  final String Function(Duration expiresIn) codeHint;
}

/// Mode de connexion d'une app.
enum LoginMethod { email, phone }

/// Fourni par chaque app (`main()` et tests).
final appIdentityProvider = Provider<AppIdentity>(
  (ref) => throw UnimplementedError('appIdentityProvider non fourni'),
);
