import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/driver_dossier.dart';
import '../../app/router.dart';

/// Dossier refusé (motif, « Corriger mon dossier ») ou livreur suspendu.
class DossierBlockedScreen extends ConsumerWidget {
  const DossierBlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dossier = ref.watch(driverDossierProvider).value;
    final suspended = dossier?.suspended ?? false;
    return ReviewBlockedView(
      title: suspended
          ? 'Votre compte livreur est suspendu'
          : "Votre dossier n'a pas été validé",
      reason: suspended
          ? dossier?.suspensionReason ?? ''
          : dossier?.reviewNote ?? '',
      actions: [
        if (!suspended)
          FilledButton(
            onPressed: () => context.push(Routes.dossierEdit),
            child: const Text('Corriger mon dossier'),
          ),
        AsyncButton.outlined(
          label: 'Actualiser',
          onPressed: () => refreshOrWarn(
            context,
            ref.read(driverDossierProvider.notifier).refresh,
          ),
        ),
        AsyncButton.text(
          label: 'Se déconnecter',
          onPressed: ref.read(authControllerProvider.notifier).signOut,
        ),
      ],
    );
  }
}
