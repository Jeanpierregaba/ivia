import 'package:flutter/material.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../features/business/pro_ui.dart';

/// Identité de l'app Ivia Business dans les écrans communs de connexion.
const sellerIdentity = AppIdentity(
  brand: IviaAppBrand.seller,
  loginTitle: 'Ivia Business',
  loginBody:
      'Connectez-vous avec votre numéro de téléphone. Vous avez déjà un compte '
      'ivia ? Utilisez le même numéro.',
  loginBadge: 'Business',
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
  authHero: _hero,
);

String _codeHint(Duration expiresIn) =>
    'Même compte sur toutes les apps ivia : utilisez le même numéro.';

Widget _hero(BuildContext context) {
  final t = Theme.of(context).textTheme;
  return Reveal(
    child: Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Pro.ink,
        borderRadius: BorderRadius.all(Radius.circular(Pro.radius)),
        border: Border(
          bottom: BorderSide(color: IviaColors.cobaltBlue, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IviaLogoTile(size: 44, color: IviaColors.cobaltBlue),
              const SizedBox(width: 10),
              Text(
                'Business',
                style: t.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Semantics(
            header: true,
            child: Text(
              'Votre activité vous attend',
              style: t.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Connectez-vous avec votre numéro. Même compte que l\'app ivia.',
            style: t.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}
