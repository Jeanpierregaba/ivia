import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/driver_dossier.dart';
import '../../common/ui.dart';
import 'dossier_labels.dart';

/// Récapitulatif du dossier envoyé : véhicule, immatriculation, modèle,
/// types de documents, compte de versement (numéro masqué). Les documents
/// eux-mêmes ne sont visibles que par l'équipe ivia.
class DossierSummaryScreen extends ConsumerWidget {
  const DossierSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dossier = ref.watch(driverDossierProvider).value;
    final delivery = dossier?.delivery;
    final plate = delivery?.plate ?? dossier?.vehiclePlate ?? '';
    final model = [
      delivery?.brand ?? '',
      delivery?.model ?? '',
    ].where((s) => s.isNotEmpty).join(' ');
    return Scaffold(
      backgroundColor: D.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(D.gutter, 8, D.gutter, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: DRound.back(onTap: () => context.pop()),
            ),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text('Mon dossier', style: DText.heading),
            ),
            const SizedBox(height: 16),
            if (dossier != null)
              DCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Item(
                      label: 'Véhicule',
                      value: vehicleLabel(
                        delivery?.vehicleType ?? dossier.vehicleType,
                      ),
                    ),
                    if (plate.isNotEmpty)
                      _Item(label: 'Immatriculation', value: plate),
                    if (model.isNotEmpty) _Item(label: 'Modèle', value: model),
                    _Item(
                      label: 'Documents envoyés',
                      value: dossier.documents.isEmpty
                          ? 'Aucun'
                          : receivedKinds(dossier)
                                .map(documentLabel)
                                .join(', '),
                    ),
                    if (dossier.payout case final p?)
                      _Item(
                        label: 'Compte de versement',
                        value: '${p.operator.label} · ${p.phoneMasked}',
                        last: true,
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Text(
              "Vos documents sont visibles uniquement par l'équipe ivia.",
              style: DText.small,
            ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 16),
    child: MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: DText.small),
          const SizedBox(height: 2),
          Text(value, style: DText.cardTitle),
        ],
      ),
    ),
  );
}
