import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/onboarding_store.dart';
import 'illustrations.dart';

/// Maquettes du 2026-10-31 (docs/specs/027-splash-onboarding/spec.md).
const onboardingSlides = [
  OnboardingSlide(
    illustration: NearbyIllustration(),
    title: "Trouvez ce qu'il vous faut, tout près.",
    highlight: 'tout près.',
    body:
        'Les produits des boutiques de votre quartier, avec le prix et la '
        'disponibilité.',
  ),
  OnboardingSlide(
    illustration: PaymentIllustration(),
    title: 'Payez en confiance avec Mobile Money.',
    highlight: 'Mobile Money.',
    body:
        "Flooz ou T-Money, directement dans l'app. La commande est confirmée "
        'dès que le paiement est reçu.',
  ),
  OnboardingSlide(
    illustration: HandoverIllustration(),
    title: 'Retrait ou livraison, vous choisissez.',
    highlight: 'livraison,',
    body:
        'Suivez chaque étape de votre commande. Votre code à 4 chiffres '
        'garantit la remise.',
  ),
];

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Une fois la présentation mémorisée, le routeur ouvre la connexion.
    return IviaOnboarding(
      brand: IviaAppBrand.buyer,
      slides: onboardingSlides,
      onDone: ref.read(onboardingSeenProvider.notifier).complete,
    );
  }
}
