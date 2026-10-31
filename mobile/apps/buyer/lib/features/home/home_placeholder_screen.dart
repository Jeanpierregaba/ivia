import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'package:ivia_app_core/ivia_app_core.dart';

/// Accueil provisoire, remplacé par la recherche (fonctionnalité 007).
class HomePlaceholderScreen extends ConsumerWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final firstName = switch (ref.watch(authControllerProvider)) {
      AuthSignedIn(:final user) => user.firstName,
      _ => '',
    };
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            const Align(alignment: Alignment.centerLeft, child: IviaLogoTile()),
            const SizedBox(height: IviaSpacing.xxl),
            Semantics(
              header: true,
              child: Text(
                firstName.isEmpty ? 'Bonjour' : 'Bonjour $firstName',
                style: textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(
              "L'accueil et la recherche arrivent bientôt.",
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
