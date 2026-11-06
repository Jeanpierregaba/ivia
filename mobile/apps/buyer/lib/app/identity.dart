import 'package:flutter/material.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Identité de l'app acheteur dans les écrans communs de connexion.
const buyerIdentity = AppIdentity(
  brand: IviaAppBrand.buyer,
  loginTitle: 'Bienvenue sur ivia',
  loginBody:
      'Connectez-vous ou créez votre compte avec votre numéro de '
      'téléphone. Nous vous envoyons un code sur WhatsApp.',
  codeHint: _codeHint,
  // Connexion par numéro (spec 001 v2, ADR 0012).
  appCode: 'buyer',
  locationPrompt: LocationPromptCopy(
    center: Icons.person_pin_circle,
    satellites: [
      Icons.storefront,
      Icons.local_pharmacy,
      Icons.local_taxi,
      Icons.restaurant,
    ],
    title: "Tout ce qu'il vous faut,",
    titleAccent: 'près de vous',
    body:
        'Activez la localisation pour voir ce qui est autour de vous et être '
        'livré.',
  ),
);

String _codeHint(Duration expiresIn) =>
    'Rien reçu ? Regardez dans les courriers indésirables. Le code est '
    'valable ${expiresIn.inMinutes} minutes.';
