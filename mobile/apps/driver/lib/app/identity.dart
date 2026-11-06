import 'package:flutter/material.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Identité de l'app livreur dans les écrans communs de connexion.
const driverIdentity = AppIdentity(
  brand: IviaAppBrand.driver,
  loginTitle: 'Espace livreur',
  loginBody:
      "Connectez-vous avec votre numéro de téléphone. Les courses s'ouvrent "
      'après la validation de votre dossier par ivia.',
  loginBadge: 'Livreur',
  codeHint: _codeHint,
  appCode: 'driver',
  locationPrompt: LocationPromptCopy(
    space: 'Livreur',
    center: Icons.two_wheeler,
    satellites: [
      Icons.storefront,
      Icons.home,
      Icons.home,
      Icons.medical_services,
    ],
    title: 'Des missions',
    titleAccent: 'près de vous',
    body:
        'Activez la localisation pour recevoir les missions proches et guider '
        'le client.',
  ),
);

String _codeHint(Duration expiresIn) =>
    'Même compte sur toutes les apps ivia : utilisez le même numéro.';
