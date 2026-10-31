import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Identité de l'app livreur dans les écrans communs de connexion.
const driverIdentity = AppIdentity(
  brand: IviaAppBrand.driver,
  loginTitle: 'Espace livreur',
  loginBody:
      'Connectez-vous avec votre e-mail. Les missions s\'ouvrent après la '
      'validation de votre dossier par ivia.',
  loginBadge: 'Livreur',
  codeHint: _codeHint,
);

String _codeHint(Duration expiresIn) =>
    "Même compte sur toutes les apps ivia : utilisez l'e-mail de votre "
    'compte acheteur si vous en avez un.';
