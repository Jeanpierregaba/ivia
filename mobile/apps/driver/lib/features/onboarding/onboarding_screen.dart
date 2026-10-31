import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/onboarding_store.dart';
import '../../app/router.dart';

/// Contenu proposé (à valider) dans docs/specs/027-splash-onboarding/spec.md.
const onboardingSlides = [
  OnboardingSlide(
    illustration: OnboardingIconIllustration(
      brand: IviaAppBrand.driver,
      icon: Icons.two_wheeler_outlined,
    ),
    title: 'Des missions près de vous',
    body: 'Recevez des propositions selon votre position et votre véhicule.',
  ),
  OnboardingSlide(
    illustration: OnboardingIconIllustration(
      brand: IviaAppBrand.driver,
      icon: Icons.route_outlined,
    ),
    title: 'Guidé de la boutique au client',
    body: 'Itinéraire, récupération, puis code du client pour terminer.',
  ),
  OnboardingSlide(
    illustration: OnboardingIconIllustration(
      brand: IviaAppBrand.driver,
      icon: Icons.toggle_on_outlined,
    ),
    title: 'Disponible quand vous le décidez',
    body: 'Votre position n\'est partagée que lorsque vous êtes en service.',
  ),
];

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IviaOnboarding(
      brand: IviaAppBrand.driver,
      slides: onboardingSlides,
      onDone: () async {
        await ref.read(onboardingStoreProvider).markSeen();
        if (context.mounted) context.go(Routes.login);
      },
    );
  }
}
