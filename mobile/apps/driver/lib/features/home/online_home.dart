import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/driver_dossier.dart';
import '../../common/formats.dart';
import '../../common/ui.dart';
import '../earnings/earnings.dart';
import '../work/work_screens.dart';
import '../work/work_state.dart';

/// Position du livreur pour centrer la carte ; Lomé si elle est inconnue.
final _herePosition = FutureProvider.autoDispose<GeoPoint>((ref) async {
  try {
    return (await ref.read(locationServiceProvider).current()).point ?? lome;
  } on Exception {
    return lome;
  }
});

/// Accueil en ligne (D09) : bandeau « En ligne », carte autour de la position,
/// volet « Recherche de missions… » avec les livraisons et gains du jour.
/// « 4 commandes bientôt prêtes » et les km sont masqués (pas de serveur,
/// spec 033).
class OnlineHome extends ConsumerWidget {
  const OnlineHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work = ref.watch(workProvider);
    final here = ref.watch(_herePosition).value ?? lome;
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // La carte passe sous les coins arrondis du volet.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: -32,
                  child: ExcludeSemantics(
                    child: IviaMap(center: here, zoom: 15, interactive: false),
                  ),
                ),
                const Positioned.fill(child: Center(child: _Radar())),
                Positioned(
                  left: 14,
                  right: 14,
                  top: MediaQuery.paddingOf(context).top + 4,
                  child: _OnlineBanner(work: work),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * .62),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1A0B1A33),
                    blurRadius: 24,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: DSheet(
                child: Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: switch (work.offer) {
                      final offer? => OfferCard(offer: offer),
                      null => _Searching(work: work),
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau sombre : point vert, « En ligne », depuis quand, quartier, Pause.
class _OnlineBanner extends ConsumerStatefulWidget {
  const _OnlineBanner({required this.work});
  final WorkState work;

  @override
  ConsumerState<_OnlineBanner> createState() => _OnlineBannerState();
}

class _OnlineBannerState extends ConsumerState<_OnlineBanner> {
  // « Depuis … » avance à la minute.
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final work = widget.work;
    final zone = ref.watch(workZoneNameProvider).value;
    final since = work.onlineSince;
    final subtitle = [
      if (since != null) onlineFor(DateTime.now().difference(since)),
      ?zone,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 10, 10),
      decoration: BoxDecoration(
        color: D.night,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: IviaDriverColors.online.withValues(alpha: .25),
                shape: BoxShape.circle,
              ),
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: IviaDriverColors.online,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'En ligne',
                      style: DText.cardTitle.copyWith(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: DText.body.copyWith(
                        color: D.nightMuted,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: D.nightTile,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: work.busy
                  ? null
                  : () => ref.read(workProvider.notifier).setOnline(false),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                // Bouton court : il laisse la place au texte, même à 200 %.
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.pause_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Pause',
                          style: DText.button.copyWith(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Position au centre de la carte, avec ses cercles de recherche.
class _Radar extends StatelessWidget {
  const _Radar();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox.square(
      dimension: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: D.blue.withValues(alpha: .06),
              shape: BoxShape.circle,
              border: Border.all(color: D.blue.withValues(alpha: .18)),
            ),
          ),
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: D.blue.withValues(alpha: .10),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: D.blue.withValues(alpha: .16),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: D.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Icon(
              Icons.navigation_rounded,
              color: Colors.white,
              size: 14,
            ),
          ),
        ],
      ),
    ),
  );
}

/// « Recherche de missions… » et les chiffres du jour.
class _Searching extends ConsumerWidget {
  const _Searching({required this.work});
  final WorkState work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missions =
        ref.watch(missionHistoryProvider).value ?? const <WorkMission>[];
    final day = today(missions, DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DIconTile(
              Icons.track_changes_rounded,
              bg: D.blueSoft,
              fg: D.blue,
              size: 48,
              circle: true,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recherche de missions…',
                      style: DText.cardTitle.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Gardez l'app ouverte : une proposition dure "
                      '45 secondes.',
                      style: DText.bodyMuted.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (work.error case final error?) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: DText.body.copyWith(color: IviaColors.error),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DayStat(
                value: '${day.deliveries}',
                label: day.deliveries > 1 ? 'Livraisons' : 'Livraison',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DayStat(
                value: formatXof(day.earnedXof),
                label: day.earnedXof > 1 ? 'Gagnés' : 'Gagné',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DayStat extends StatelessWidget {
  const _DayStat({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: D.page,
        borderRadius: BorderRadius.circular(D.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: DText.amount.copyWith(fontSize: 18)),
          Text(label, style: DText.bodyMuted.copyWith(fontSize: 14)),
        ],
      ),
    ),
  );
}
