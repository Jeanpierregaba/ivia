import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/formats.dart';
import '../../common/ui.dart';
import '../earnings/earnings.dart';
import '../work/work_screens.dart';
import '../work/work_state.dart';

/// Onglet Accueil : hors ligne (maquette D08) ou en ligne (proposition,
/// recherche).
class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work = ref.watch(workProvider);
    if (work.online || work.offer != null) return const OnlineHome();
    return const _OfflineHome();
  }
}

/// Accueil hors ligne (D08) : salutation, carte du jour, « Glisser pour
/// passer en ligne ». Objectif, km, temps en ligne et demande par quartier
/// sont masqués (pas de serveur, spec 033).
class _OfflineHome extends ConsumerWidget {
  const _OfflineHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work = ref.watch(workProvider);
    final user = switch (ref.watch(authControllerProvider)) {
      AuthSignedIn(:final user) => user,
      _ => null,
    };
    final name = [
      user?.firstName ?? '',
      user?.lastName ?? '',
    ].where((s) => s.isNotEmpty).join(' ');
    final missions =
        ref.watch(missionHistoryProvider).value ?? const <WorkMission>[];
    final now = DateTime.now();
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(missionHistoryProvider);
          await ref.read(workProvider.notifier).refresh();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(D.gutter, 18, D.gutter, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(greeting(now), style: DText.bodyMuted),
                      Semantics(
                        header: true,
                        child: Text(
                          name.isEmpty ? 'Ivia Driver' : name,
                          style: DText.heading.copyWith(fontSize: 28),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _Avatar(initials: initials(name), online: false),
              ],
            ),
            const SizedBox(height: 16),
            _TodayCard(
              today: today(missions, now),
              week: thisWeek(missions, now),
            ),
            const SizedBox(height: 16),
            DCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DIconTile(
                        Icons.power_settings_new_rounded,
                        bg: D.page,
                        fg: D.muted,
                        size: 52,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vous êtes hors ligne',
                              style: DText.cardTitle.copyWith(fontSize: 20),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Passez en ligne pour recevoir des missions.',
                              style: DText.bodyMuted,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DSlide(
                    label: 'Glisser pour passer en ligne',
                    onConfirmed: work.busy
                        ? null
                        : () async {
                            // Écran d'autorisation d'abord s'il le faut ;
                            // refusée, on passe quand même en ligne.
                            await askForLocation(context, ref);
                            if (!context.mounted) return;
                            await ref
                                .read(workProvider.notifier)
                                .setOnline(true);
                          },
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Initiales sur pastille bleue, point d'état (gris hors ligne, vert en
/// ligne).
class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.online});
  final String initials;
  final bool online;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: 48,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: D.blue,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: MediaQuery.withNoTextScaling(
                  child: Text(
                    initials,
                    style: DText.cardTitle.copyWith(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: online
                    ? IviaDriverColors.online
                    : IviaDriverColors.checkOff,
                shape: BoxShape.circle,
                border: Border.all(color: D.page, width: 2),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Carte sombre du jour : livraisons dans l'anneau, gains du jour, gains de
/// la semaine.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.today, required this.week});
  final Totals today, week;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: DCard.dark(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Row(
        children: [
          _Ring(count: today.deliveries),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "AUJOURD'HUI",
                  style: DText.overline.copyWith(color: D.nightMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  formatXof(today.earnedXof),
                  style: DText.amount.copyWith(
                    color: Colors.white,
                    fontSize: 32,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _NightChip('Semaine : ${formatXof(week.earnedXof)}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _NightChip extends StatelessWidget {
  const _NightChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(IviaRadius.pill),
      border: Border.all(color: IviaDriverColors.nightOutline),
    ),
    child: Text(text, style: DText.pill.copyWith(color: Colors.white)),
  );
}

/// Anneau des livraisons du jour (l'objectif « 5/8 » des maquettes n'existe
/// pas côté serveur : l'anneau est plein dès la première livraison).
class _Ring extends StatelessWidget {
  const _Ring({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 90,
    child: CustomPaint(
      painter: _RingPainter(filled: count > 0),
      child: Center(
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: DText.amount.copyWith(color: Colors.white, fontSize: 24),
              ),
              Text(
                count > 1 ? 'livraisons' : 'livraison',
                style: DText.small.copyWith(color: D.nightMuted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.filled});
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = IviaDriverColors.nightTile;
    canvas.drawArc(arc, 0, 2 * math.pi, false, track);
    if (filled) {
      canvas.drawArc(
        arc,
        -math.pi / 2,
        2 * math.pi,
        false,
        track..color = D.blueOnDark,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.filled != filled;
}
