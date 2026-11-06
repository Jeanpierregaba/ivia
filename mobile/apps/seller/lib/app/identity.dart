import 'package:flutter/material.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Identité de l'app marchand dans les écrans communs de connexion.
const sellerIdentity = AppIdentity(
  brand: IviaAppBrand.seller,
  loginTitle: 'Espace marchand',
  loginBody:
      'Connectez-vous avec votre numéro de téléphone. Vous avez déjà un compte '
      'ivia ? Utilisez le même numéro.',
  loginBadge: 'Marchand',
  codeHint: _codeHint,
  appCode: 'seller',
  locationPrompt: LocationPromptCopy(
    space: 'Business',
    center: Icons.storefront,
    satellites: [
      Icons.storefront,
      Icons.apartment,
      Icons.restaurant,
      Icons.construction,
    ],
    title: 'Soyez visible',
    titleAccent: 'dans votre quartier',
    body: 'Activez la localisation pour placer votre activité sur la carte.',
  ),
);

String _codeHint(Duration expiresIn) =>
    'Même compte sur toutes les apps ivia : utilisez le même numéro.';
