import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/driver_dossier.dart';
import '../../app/router.dart';
import 'dossier_labels.dart';

/// « Votre dossier est en cours de vérification » : suivi des étapes.
class DossierPendingScreen extends ConsumerWidget {
  const DossierPendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dossier = ref.watch(driverDossierProvider).value;
    return ReviewPendingView(
      title: 'Votre dossier est en cours de vérification',
      body:
          "L'équipe ivia vérifie votre identité et votre véhicule. Vous "
          "recevrez une notification dès l'activation des missions.",
      onRefresh: ref.read(driverDossierProvider.notifier).refresh,
      steps: [
        const IviaStep(title: 'Compte créé', state: IviaStepState.done),
        IviaStep(
          title: 'Dossier envoyé',
          subtitle: dossier == null ? null : dossierLine(dossier),
          state: IviaStepState.done,
        ),
        const IviaStep(
          title: 'Vérification par ivia',
          subtitle: 'En cours',
          state: IviaStepState.current,
        ),
        const IviaStep(
          title: 'Missions activées',
          state: IviaStepState.upcoming,
        ),
      ],
      action: OutlinedButton(
        onPressed: () => context.push(Routes.dossierSummary),
        child: const Text('Voir mon dossier'),
      ),
    );
  }
}
