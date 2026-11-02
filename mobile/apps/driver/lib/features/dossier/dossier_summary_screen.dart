import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/driver_dossier.dart';
import 'dossier_labels.dart';

/// Récapitulatif du dossier envoyé : véhicule, immatriculation, types de
/// documents. Les documents eux-mêmes ne sont visibles que par l'équipe ivia.
class DossierSummaryScreen extends ConsumerWidget {
  const DossierSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final dossier = ref.watch(driverDossierProvider).value;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IviaBackButton(onPressed: () => context.pop()),
            ),
            const SizedBox(height: IviaSpacing.lg),
            Semantics(
              header: true,
              child: Text('Mon dossier', style: textTheme.headlineMedium),
            ),
            const SizedBox(height: IviaSpacing.xl),
            if (dossier != null)
              Container(
                padding: const EdgeInsets.all(IviaSpacing.xl),
                decoration: BoxDecoration(
                  color: IviaColors.surface,
                  borderRadius: BorderRadius.circular(IviaRadius.large),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Item(
                      label: 'Véhicule',
                      value: vehicleLabel(dossier.vehicleType),
                    ),
                    _Item(
                      label: 'Immatriculation',
                      value: dossier.vehiclePlate,
                    ),
                    _Item(
                      label: 'Documents envoyés',
                      value: dossier.documents.isEmpty
                          ? 'Aucun'
                          : receivedKinds(dossier)
                                .map(documentLabel)
                                .join(', '),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: IviaSpacing.lg),
            Text(
              "Vos documents sont visibles uniquement par l'équipe ivia.",
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: IviaSpacing.lg),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: textTheme.bodySmall),
            Text(value, style: textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}
