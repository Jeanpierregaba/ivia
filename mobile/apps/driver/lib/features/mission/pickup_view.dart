import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/ui.dart';
import '../work/work_state.dart';
import 'mission_screen.dart' show MissionPhase;
import 'mission_ui.dart';
import 'navigation.dart';
import 'problem_sheet.dart';

/// Retrait (D12).
///
/// - Boutique : cases du colis, puis « Glisser : colis récupéré ».
/// - Pharmacie avec code (032, ADR 0014) : code de retrait en grand, sans
///   glissière ; la pharmacie valide la remise et la relecture de la mission
///   (toutes les 4 s) fait passer seule à l'étape suivante.
/// - Ancienne course pharmacie sans code : « récupéré » reste proposé.
///
/// Le serveur ne donne que le nombre d'articles d'une commande de boutique :
/// la case « n articles reçus » remplace la liste des maquettes.
class PickupView extends ConsumerStatefulWidget {
  const PickupView({super.key, required this.mission});
  final WorkMission mission;

  @override
  ConsumerState<PickupView> createState() => _PickupViewState();
}

class _PickupViewState extends ConsumerState<PickupView> {
  var _items = false, _sealed = false;

  Future<void> _pickedUp() async {
    final error = await ref
        .read(workProvider.notifier)
        .run((api) => api.missionStep(widget.mission, 'picked-up'));
    if (error != null && mounted) {
      announce(context, error);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _call(String phone) async {
    final ok = await ref.read(linkLauncherProvider)(telUri(phone));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible de lancer l'appel.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final code = m.pickupCode;
    final byCode = m.pharmacy && code != null;
    final ready = m.pharmacy ? !m.awaitingPayment : _items && _sealed;
    final busy = ref.watch(workProvider.select((s) => s.busy));
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(D.gutter, 12, D.gutter, 16),
              children: [
                const StepHeader(title: 'Retrait', step: '1 sur 2'),
                const SizedBox(height: 16),
                DCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: DIconTile(
                          m.pharmacy
                              ? Icons.local_pharmacy_rounded
                              : Icons.storefront_rounded,
                          bg: D.night,
                          fg: Colors.white,
                          size: 44,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MergeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.pickup.name,
                                style: DText.cardTitle.copyWith(fontSize: 17),
                              ),
                              Text(
                                [
                                  if (m.reference.isNotEmpty)
                                    'Commande ${shortRef(m.reference)}',
                                  m.awaitingPayment
                                      ? 'paiement en attente'
                                      : 'payée',
                                ].join(' · '),
                                style: DText.bodyMuted.copyWith(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (m.pickup.phone.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        RoundButton(
                          icon: Icons.call_rounded,
                          tooltip: m.pharmacy
                              ? 'Appeler la pharmacie'
                              : 'Appeler la boutique',
                          bg: D.page,
                          fg: D.ink,
                          onTap: () => _call(m.pickup.phone),
                        ),
                      ],
                    ],
                  ),
                ),
                if (byCode) ...[
                  const SizedBox(height: 12),
                  DCard.dark(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'VOTRE CODE DE RETRAIT',
                            style: DText.overline.copyWith(color: D.nightMuted),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DCodeBoxes(
                          code,
                          length: code.length,
                          style: DCodeStyle.dark,
                          semanticLabel: 'Code de retrait',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Montrez ce code au pharmacien pour récupérer les '
                          'produits.',
                          style: DText.body.copyWith(color: D.nightMuted),
                        ),
                      ],
                    ),
                  ),
                ],
                if (m.awaitingPayment) ...[
                  const SizedBox(height: 12),
                  _Notice(
                    icon: Icons.hourglass_top_rounded,
                    text:
                        "Le client n'a pas encore payé. Les produits vous "
                        'seront remis dès son paiement.',
                    bg: IviaDriverColors.warningSoft,
                    fg: IviaDriverColors.warning,
                  ),
                ],
                const SizedBox(height: 12),
                DCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          m.pharmacy ? 'À récupérer' : 'Vérifiez le colis',
                          style: DText.cardTitle.copyWith(fontSize: 17),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (m.pharmacy)
                        for (final line in m.lines.where((l) => l.available))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '${line.name} ×${line.quantity}',
                              style: DText.body.copyWith(color: D.ink),
                            ),
                          )
                      else ...[
                        CheckRow(
                          label: m.itemsCount > 1
                              ? '${m.itemsCount} articles reçus'
                              : '${m.itemsCount} article reçu',
                          value: _items,
                          onChanged: (v) => setState(() => _items = v),
                        ),
                        CheckRow(
                          label: 'Colis fermé et en bon état',
                          value: _sealed,
                          onChanged: (v) => setState(() => _sealed = v),
                        ),
                      ],
                    ],
                  ),
                ),
                if (byCode && !m.awaitingPayment) ...[
                  const SizedBox(height: 12),
                  const _Notice(
                    icon: Icons.storefront_rounded,
                    text:
                        'La pharmacie valide la remise de son côté : '
                        "l'écran passe seul à la livraison.",
                    bg: D.blueSoft,
                    fg: D.blue,
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              D.gutter,
              8,
              D.gutter,
              MediaQuery.paddingOf(context).bottom + 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!byCode)
                  DSlide(
                    label: 'Glisser pour démarrer ma course vers le client',
                    dark: true,
                    onConfirmed: ready && !busy ? _pickedUp : null,
                  ),
                ProblemButton(mission: m, phase: MissionPhase.atPickup),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    required this.bg,
    required this.fg,
  });
  final IconData icon;
  final String text;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: fg, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: DText.body.copyWith(color: D.ink, fontSize: 14),
          ),
        ),
      ],
    ),
  );
}
