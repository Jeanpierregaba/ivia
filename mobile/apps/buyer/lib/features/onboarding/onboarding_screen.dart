import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/onboarding_store.dart';
import '../../app/router.dart';

/// Contenu proposé (à valider) dans docs/specs/027-splash-onboarding/spec.md.
const onboardingSlides = [
  OnboardingSlide(
    icon: Icons.storefront_outlined,
    title: 'Les boutiques de Lomé dans votre poche',
    body:
        'Trouvez un produit près de chez vous, avec son prix et sa '
        'disponibilité.',
  ),
  OnboardingSlide(
    icon: Icons.account_balance_wallet_outlined,
    title: 'Payez par Flooz ou T-Money',
    body:
        'Votre paiement est confirmé avant que la boutique prépare votre '
        'commande.',
  ),
  OnboardingSlide(
    icon: Icons.local_shipping_outlined,
    title: 'Retrait ou livraison, à vous de choisir',
    body:
        'Suivez votre commande étape par étape et remettez votre code à la '
        'réception.',
  ),
];

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IviaOnboarding(
      brand: IviaAppBrand.buyer,
      slides: onboardingSlides,
      onDone: () async {
        await ref.read(onboardingStoreProvider).markSeen();
        if (context.mounted) context.go(Routes.login);
      },
    );
  }
}
