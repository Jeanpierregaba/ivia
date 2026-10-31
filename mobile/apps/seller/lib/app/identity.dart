import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Identité de l'app marchand dans les écrans communs de connexion.
const sellerIdentity = AppIdentity(
  brand: IviaAppBrand.seller,
  loginTitle: 'Espace marchand',
  loginBody:
      'Connectez-vous avec votre e-mail. Vous avez déjà un compte ivia ? '
      'Utilisez le même.',
  loginBadge: 'Marchand',
  codeHint: _codeHint,
);

String _codeHint(Duration expiresIn) =>
    "Même compte sur toutes les apps ivia : utilisez l'e-mail de votre "
    'compte acheteur si vous en avez un.';
