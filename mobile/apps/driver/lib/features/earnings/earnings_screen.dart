import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../common/ui.dart';
import 'earnings.dart';

/// Onglet Gains (maquette D18) : semaine en cours, calculée depuis
/// l'historique. Barres par jour, mois et compte de versement : tâche 18.
class EarningsTab extends ConsumerWidget {
  const EarningsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missions =
        ref.watch(missionHistoryProvider).value ?? const <WorkMission>[];
    final week = thisWeek(missions, DateTime.now());
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(D.gutter, 18, D.gutter, 24),
        children: [
          Semantics(
            header: true,
            child: Text('Gains', style: DText.heading.copyWith(fontSize: 30)),
          ),
          const SizedBox(height: 16),
          MergeSemantics(
            child: DCard.dark(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CETTE SEMAINE',
                    style: DText.overline.copyWith(color: D.nightMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatXof(week.earnedXof),
                    style: DText.amount.copyWith(
                      color: Colors.white,
                      fontSize: 36,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${week.deliveries} livraison${week.deliveries > 1 ? 's' : ''}',
                    style: DText.body.copyWith(color: D.nightMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
