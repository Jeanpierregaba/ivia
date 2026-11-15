import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'illustrations.dart';

/// Maquettes F01 à F03 (docs/specs/031-ecrans-pharmacie/spec.md).
const onboardingSlides = [
  OnboardingSlide(
    illustration: AlertIllustration(),
    title: 'Les urgences de votre quartier, en direct.',
    highlight: 'en direct.',
    body:
        'Quand vous êtes en service, vous recevez les demandes de médicaments '
        'des clients autour de vous.',
  ),
  OnboardingSlide(
    illustration: ResponseIllustration(),
    title: "Répondez en moins d'une minute.",
    highlight: "en moins d'une minute.",
    body:
        "Indiquez pour chaque produit s'il est disponible et son prix. Le "
        'client reste anonyme.',
  ),
  OnboardingSlide(
    illustration: HandoverIllustration(),
    title: 'Le client confirme, vous préparez.',
    highlight: 'vous préparez.',
    body:
        'Mettez les produits de côté pendant 1 h. Aucune commission sur vos '
        'ventes.',
  ),
];

/// Présentation du premier lancement, montrée une fois sur le téléphone.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Une fois la présentation mémorisée, le routeur ouvre la connexion.
    return IviaOnboarding(
      brand: IviaAppBrand.pharmacy,
      appName: 'Pharmacie',
      slides: onboardingSlides,
      onDone: ref.read(onboardingSeenProvider.notifier).complete,
    );
  }
}
