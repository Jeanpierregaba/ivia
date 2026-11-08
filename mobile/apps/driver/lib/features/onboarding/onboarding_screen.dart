import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'illustrations.dart';

/// Maquettes du 2026-10-31 (docs/specs/018-espace-livreur/spec.md).
const onboardingSlides = [
  OnboardingSlide(
    illustration: MissionOfferIllustration(),
    title: 'Des missions près de vous.',
    highlight: 'près de vous.',
    body:
        'Restez disponible et recevez des propositions avec la boutique, la '
        'distance et le gain indicatif.',
  ),
  OnboardingSlide(
    illustration: MissionStepsIllustration(),
    title: 'Guidé à chaque étape.',
    highlight: 'à chaque étape.',
    body:
        "L'itinéraire s'ouvre dans votre application de cartes : la "
        'boutique, puis le client.',
  ),
  OnboardingSlide(
    illustration: CustomerCodeIllustration(),
    title: 'Le code du client valide la livraison.',
    highlight: 'valide la livraison.',
    body:
        'Saisissez le code à 4 chiffres. La mission est terminée et vous '
        'redevenez disponible.',
  ),
];

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Une fois la présentation mémorisée, le routeur ouvre la connexion.
    return IviaOnboarding(
      brand: IviaAppBrand.driver,
      appName: 'Driver',
      slides: onboardingSlides,
      onDone: ref.read(onboardingSeenProvider.notifier).complete,
    );
  }
}
