import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Identité de l'app acheteur dans les écrans communs de connexion.
const buyerIdentity = AppIdentity(
  brand: IviaAppBrand.buyer,
  loginTitle: 'Bienvenue sur ivia',
  loginBody:
      'Connectez-vous ou créez votre compte avec votre e-mail. '
      'Pas de mot de passe : nous vous envoyons un code.',
  codeHint: _codeHint,
);

String _codeHint(Duration expiresIn) =>
    'Rien reçu ? Regardez dans les courriers indésirables. Le code est '
    'valable ${expiresIn.inMinutes} minutes.';
