import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/ui.dart';
import '../profile/settings.dart';
import 'mission_ui.dart';
import 'navigation.dart';
import 'problem_sheet.dart' show driverSupportPhone;

/// Retour à la boutique : livraison impossible déclarée (client
/// injoignable), le serveur garde la mission « returning » jusqu'à ce que la
/// boutique confirme la réception du colis ; elle disparaît alors seule
/// (relecture toutes les 4 s).
class ReturnView extends ConsumerWidget {
  const ReturnView({super.key, required this.mission});
  final WorkMission mission;

  Future<void> _launch(BuildContext context, WidgetRef ref, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(linkLauncherProvider)(uri);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Impossible d'ouvrir le lien.")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = mission;
    final shop = m.pickup;
    final nav = ref.watch(navAppProvider).value ?? NavApp.google;
    final to = shop.location;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(D.gutter, 12, D.gutter, 16),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Retour à la boutique',
                    style: DText.heading.copyWith(fontSize: 26),
                  ),
                ),
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: IviaDriverColors.warningSoft,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.assignment_return_rounded,
                          color: IviaDriverColors.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            [
                              if (m.failureReason.isNotEmpty)
                                'Livraison impossible : ${m.failureReason}.',
                              'Rapportez le colis à ${shop.name.isEmpty ? 'la boutique' : shop.name}. '
                                  'La mission se termine quand la boutique '
                                  'confirme la réception.',
                            ].join(' '),
                            style: DText.body.copyWith(
                              color: D.ink,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const DIconTile(
                        Icons.storefront_rounded,
                        bg: D.night,
                        fg: Colors.white,
                        size: 44,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MergeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shop.name,
                                style: DText.cardTitle.copyWith(fontSize: 17),
                              ),
                              if (placeAddress(shop) case final address?)
                                Text(
                                  address,
                                  style: DText.bodyMuted.copyWith(fontSize: 13),
                                ),
                              if (m.reference.isNotEmpty)
                                Text(
                                  'Commande ${shortRef(m.reference)}',
                                  style: DText.bodyMuted.copyWith(fontSize: 13),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (shop.phone.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        RoundButton(
                          icon: Icons.call_rounded,
                          tooltip: 'Appeler la boutique',
                          bg: D.page,
                          fg: D.ink,
                          onTap: () => _launch(
                            context,
                            ref,
                            Uri.parse('tel:${shop.phone}'),
                          ),
                        ),
                      ],
                    ],
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
              MediaQuery.paddingOf(context).bottom + 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DButton(
                  label: 'Ouvrir dans ${nav.shortLabel}',
                  icon: Icons.map_outlined,
                  onTap: to == null
                      ? null
                      : () => _launch(context, ref, nav.route(to)),
                ),
                TextButton(
                  onPressed: () => _launch(
                    context,
                    ref,
                    Uri.parse('tel:$driverSupportPhone'),
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    'Appeler le support',
                    style: DText.button.copyWith(color: D.label, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
