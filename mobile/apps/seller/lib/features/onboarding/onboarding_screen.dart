import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'illustrations.dart';

/// Maquettes du 2026-10-31 (docs/specs/004-espace-marchand/spec.md).
const onboardingSlides = [
  OnboardingSlide(
    illustration: ShopIllustration(),
    title: 'Votre boutique en ligne, sans site web.',
    highlight: 'sans site web.',
    body:
        'Ajoutez vos produits en photo, avec le prix et le stock. Les '
        'acheteurs du quartier vous trouvent.',
  ),
  OnboardingSlide(
    illustration: PaidOrderIllustration(),
    title: 'Des commandes déjà payées.',
    highlight: 'déjà payées.',
    body:
        'Le client paie par Mobile Money avant que vous ne prépariez. Vous '
        'avez 15 minutes pour accepter.',
  ),
  OnboardingSlide(
    illustration: SellerHandoverIllustration(),
    title: 'La remise, en toute sécurité.',
    highlight: 'en toute sécurité.',
    body:
        'Livraison par un livreur ivia ou retrait en boutique : le code à '
        '4 chiffres du client confirme la remise.',
  ),
];

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Une fois la présentation mémorisée, le routeur ouvre la connexion.
    return IviaOnboarding(
      brand: IviaAppBrand.seller,
      appName: 'Marchand',
      slides: onboardingSlides,
      onDone: ref.read(onboardingSeenProvider.notifier).complete,
    );
  }
}
