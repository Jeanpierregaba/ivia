import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/formats.dart';
import '../../common/ui.dart';
import '../earnings/earnings.dart';
import '../work/work_state.dart';
import 'mission_ui.dart';

/// Livraison terminée (D15) : remise, gain de la course, totaux du jour
/// (calculés depuis l'historique), « Rester en ligne », « Faire une pause ».
/// Les km parcourus sont masqués (pas de serveur, spec 033).
class DeliveredView extends ConsumerWidget {
  const DeliveredView({super.key, required this.delivered});
  final Delivered delivered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = delivered.mission;
    final busy = ref.watch(workProvider.select((s) => s.busy));
    final history =
        ref.watch(missionHistoryProvider).value ?? const <WorkMission>[];
    // L'historique relu peut ne pas encore contenir cette livraison.
    var day = today(history, DateTime.now());
    if (!history.any((h) => h.id == m.id && h.deliveredAt != null)) {
      day = Totals(day.earnedXof + m.feeXof, day.deliveries + 1);
    }
    final client = m.client?.name ?? '';
    final order = m.reference.isEmpty
        ? 'Commande'
        : 'Commande ${shortRef(m.reference)}';
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(D.gutter, 48, D.gutter, 16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ExcludeSemantics(
                    child: Container(
                      width: 120,
                      height: 120,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: D.blue.withValues(alpha: .16),
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: const BoxDecoration(
                          color: D.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text('Livraison terminée', style: DText.hero),
                ),
                const SizedBox(height: 8),
                Text(
                  client.isEmpty
                      ? '$order remise à ${hhmm(delivered.at)}.'
                      : '$order remise à $client à ${hhmm(delivered.at)}.',
                  style: DText.body.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 24),
                MergeSemantics(
                  child: DCard.dark(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'GAIN DE LA COURSE',
                          style: DText.overline.copyWith(color: D.nightMuted),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '+${formatXof(m.feeXof)}',
                          style: DText.amount.copyWith(
                            color: D.blueOnDark,
                            fontSize: 44,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Divider(
                          height: 1,
                          color: IviaDriverColors.nightOutline,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _NightFigure(
                                formatXof(day.earnedXof),
                                "Aujourd'hui",
                              ),
                            ),
                            Expanded(
                              child: _NightFigure(
                                '${day.deliveries}',
                                day.deliveries > 1 ? 'Livraisons' : 'Livraison',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              D.gutter,
              8,
              D.gutter,
              MediaQuery.paddingOf(context).bottom + 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DButton(
                  label: 'Rester en ligne',
                  busy: busy,
                  onTap: () => ref
                      .read(workProvider.notifier)
                      .afterDelivery(stayOnline: true),
                ),
                const SizedBox(height: 10),
                DButton(
                  label: 'Faire une pause',
                  style: DButtonStyle.outline,
                  onTap: busy
                      ? null
                      : () => ref
                            .read(workProvider.notifier)
                            .afterDelivery(stayOnline: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NightFigure extends StatelessWidget {
  const _NightFigure(this.value, this.label);
  final String value, label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: DText.amount.copyWith(color: Colors.white, fontSize: 20),
      ),
      Text(label, style: DText.body.copyWith(color: D.nightMuted)),
    ],
  );
}
