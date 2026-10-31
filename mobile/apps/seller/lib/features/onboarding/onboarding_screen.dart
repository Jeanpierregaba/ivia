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
      brand: IviaAppBrand.seller,
      icon: Icons.add_business_outlined,
    ),
    title: 'Votre boutique en ligne',
    body: 'Créez-la en quelques minutes ; ivia la vérifie avant de la publier.',
  ),
  OnboardingSlide(
    illustration: OnboardingIconIllustration(
      brand: IviaAppBrand.seller,
      icon: Icons.receipt_long_outlined,
    ),
    title: 'Des commandes déjà payées',
    body: 'Acceptez-les en un geste, l\'acheteur a payé par Mobile Money.',
  ),
  OnboardingSlide(
    illustration: OnboardingIconIllustration(
      brand: IviaAppBrand.seller,
      icon: Icons.verified_user_outlined,
    ),
    title: 'Une remise sans litige',
    body:
        'Le code de l\'acheteur confirme chaque remise ; vos relevés sont '
        'tenus pour vous.',
  ),
];

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IviaOnboarding(
      brand: IviaAppBrand.seller,
      slides: onboardingSlides,
      onDone: () async {
        await ref.read(onboardingStoreProvider).markSeen();
        if (context.mounted) context.go(Routes.login);
      },
    );
  }
}
