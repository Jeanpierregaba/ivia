import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/driver_dossier.dart';
import '../../app/router.dart';
import '../../common/ui.dart';

/// Dossier refusé (motif, « Corriger mon dossier »), compléments demandés
/// (« Compléter mon dossier ») ou livreur suspendu.
class DossierBlockedScreen extends ConsumerWidget {
  const DossierBlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dossier = ref.watch(driverDossierProvider).value;
    final suspended = dossier?.suspended ?? false;
    // Compléments demandés par le back-office (spec 033) : pas un refus.
    final changes = dossier?.review == DriverReview.changesRequested;
    return ReviewBlockedView(
      title: suspended
          ? 'Votre compte livreur est suspendu'
          : changes
          ? 'Votre dossier est à compléter'
          : "Votre dossier n'a pas été validé",
      reason: suspended
          ? dossier?.suspensionReason ?? ''
          : dossier?.reviewNote ?? '',
      actions: [
        if (!suspended)
          DButton(
            label: changes ? 'Compléter mon dossier' : 'Corriger mon dossier',
            onTap: () => context.push(Routes.dossierEdit),
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
