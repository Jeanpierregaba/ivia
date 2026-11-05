import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Accueil provisoire du livreur validé, remplacé par la disponibilité et
/// les missions (fonctionnalités 019 à 022).
class HomePlaceholderScreen extends ConsumerWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IviaLogoTile(color: IviaAppBrand.driver.accent),
            ),
            const SizedBox(height: IviaSpacing.xxl),
            Semantics(
              header: true,
              child: Text(
                'Vous êtes livreur ivia',
                style: textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(
              'Votre dossier est validé. La disponibilité et les missions '
              'arrivent bientôt ici.',
              style: textTheme.bodyLarge?.copyWith(
                color: IviaColors.textSecondary,
              ),
            ),
            const SizedBox(height: IviaSpacing.xxxl),
            AsyncButton.outlined(
              label: 'Se déconnecter',
              onPressed: ref.read(authControllerProvider.notifier).signOut,
            ),
          ],
        ),
      ),
    );
  }
}
