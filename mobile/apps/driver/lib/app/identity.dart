import 'package:flutter/material.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Identité de l'app Ivia Driver dans les écrans communs de connexion.
const driverIdentity = AppIdentity(
  brand: IviaAppBrand.driver,
  loginTitle: 'Espace livreur',
  loginBody:
      "Connectez-vous avec votre numéro de téléphone. Les missions s'ouvrent "
      'après la validation de votre dossier par ivia.',
  loginBadge: 'Driver',
  // Maquettes D04 et D05 (spec 033), connexion par numéro (ADR 0012) : badge
  // plein, titre du code selon le canal, encart « Même compte ».
  loginBadgeFilled: true,
  authTips: false,
  codeTitleByChannel: true,
  codeHintCard: true,
  whatsappLabel: 'Recevoir le code',
  codeHint: _codeHint,
  appCode: 'driver',
  locationPrompt: LocationPromptCopy(
    space: 'Driver',
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
