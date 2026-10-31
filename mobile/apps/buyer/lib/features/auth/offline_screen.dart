import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/auth_controller.dart';
import 'async_button.dart';

/// Session gardée mais serveur injoignable au démarrage, sans profil connu.
class OfflineScreen extends ConsumerWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final auth = ref.read(authControllerProvider.notifier);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            const SizedBox(height: IviaSpacing.huge),
            const Icon(Icons.wifi_off, size: 56, color: IviaColors.textMuted),
            const SizedBox(height: IviaSpacing.xxl),
            Semantics(
              header: true,
              child: Text(
                'Pas de connexion',
                style: textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(
              'Vérifiez votre réseau, puis réessayez.',
              style: textTheme.bodyLarge?.copyWith(
                color: IviaColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: IviaSpacing.xxxl),
            AsyncButton.filled(label: 'Réessayer', onPressed: auth.retry),
            const SizedBox(height: IviaSpacing.sm),
            AsyncButton.text(label: 'Se déconnecter', onPressed: auth.signOut),
          ],
        ),
      ),
    );
  }
}
