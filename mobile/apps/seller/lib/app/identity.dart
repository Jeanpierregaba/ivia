import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Identité de l'app Ivia Business dans les écrans communs de connexion.
const sellerIdentity = AppIdentity(
  brand: IviaAppBrand.seller,
  loginTitle: 'Ivia Business',
  loginBody:
      'Connectez-vous avec votre numéro de téléphone. Vous avez déjà un compte '
      'ivia ? Utilisez le même numéro.',
  loginBadge: 'Business',
  codeHint: _codeHint,
  loginMethod: LoginMethod.phone,
  appCode: 'seller',
);

String _codeHint(Duration expiresIn) =>
    'Même compte sur toutes les apps ivia : utilisez le même numéro.';
