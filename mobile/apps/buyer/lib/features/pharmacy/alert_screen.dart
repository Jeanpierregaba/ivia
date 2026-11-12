import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../payment/payment_logos.dart';
import '../payment/payment_providers.dart';
import 'med_draft.dart';
import 'med_ui.dart';
import 'pharmacy_hub_screen.dart';
import 'pharmacy_state.dart';

/// P07 (alerte en cours) et P14 (alerte terminée sans réponse).
class AlertScreen extends ConsumerStatefulWidget {
  const AlertScreen({super.key, required this.alertId});
  final String alertId;

  @override
  ConsumerState<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends ConsumerState<AlertScreen> with LivePolling {
  /// Nombre de réponses déjà annoncées par la fenêtre : elle ne s'ouvre qu'à
  /// l'arrivée d'une nouvelle réponse.
  var _announced = 0;

  void _announce(MedAlert alert, int count, MedResponse best) {
    if (count <= _announced) return;
    _announced = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showResponsesSheet(
        context,
        count: count,
        best: best,
        onOpen: () => context.push(Routes.medResponses(alert.id)),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    startPolling(() => ref.invalidate(medAlertProvider(widget.alertId)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(medAlertProvider(widget.alertId));
    final alert = async.value;
    if (alert == null) {
      return MedScaffold(
        top: const MedTopBar(title: 'Alerte'),
        body: Center(
          child: async.hasError
              ? const Text('Alerte indisponible.')
              : const CircularProgressIndicator(),
        ),
      );
    }
    final responded = alert.responses
        .where((r) => r.status != 'withdrawn' || r.unlocked)
        .toList();
    if (!alert.searching && responded.isEmpty) return _EndedView(alert: alert);
    final left = alert.searchEndsAt.difference(
      ref.read(apiClientProvider).now(),
    );
    final t = Theme.of(context).textTheme;
    final best = ([
      ...responded,
    ]..sort((a, b) => a.distanceM.compareTo(b.distanceM))).firstOrNull;
    if (best != null) _announce(alert, responded.length, best);
    return MedScaffold(
      top: MedTopBar(
        title: 'Alerte en cours',
        centered: true,
        icon: Icons.close,
        onBack: () => context.go(Routes.pharmacy),
        trailing: left > Duration.zero
            ? MedPill.minutes(left)
            : const SizedBox(width: 56),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        children: [
          SizedBox(
            height: 330,
            child: _Radar(
              notified: alert.notified,
              responded: responded.length,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Alerte envoyée à ${alert.notified} pharmacie${alert.notified > 1 ? 's' : ''} de garde',
            style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Nous vous prévenons dès qu\'une pharmacie confirme avoir vos produits.',
            style: t.bodyLarge?.copyWith(color: Med.muted),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _Stat(value: alert.notified, label: 'Alertées'),
              const SizedBox(width: 12),
              _Stat(value: alert.seen, label: 'Ont vu'),
              const SizedBox(width: 12),
              _Stat(value: alert.responded, label: 'A répondu', red: true),
            ],
          ),
        ],
      ),
      bottom: best == null
          ? null
          : SafeArea(
              top: false,
              child: IviaReveal(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    IviaSpacing.screen,
                    8,
                    IviaSpacing.screen,
                    IviaSpacing.lg,
                  ),
                  child: GestureDetector(
                    onTap: () => context.push(Routes.medResponses(alert.id)),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: IviaColors.surface,
                        borderRadius: BorderRadius.circular(Med.radius),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F0B1F3A),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const MedIconTile(
                              Icons.check,
                              bg: IviaColors.primary,
                              fg: Colors.white,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _respondedTitle(responded.length),
                                    style: t.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _bestLine(best),
                                    style: t.bodyMedium?.copyWith(
                                      color: Med.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: IviaColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

String _respondedTitle(int n) =>
    n > 1 ? '$n pharmacies ont vos produits' : 'Une pharmacie a vos produits';

String _bestLine(MedResponse best) =>
    '${best.availableCount} sur ${best.lineCount} disponible${best.availableCount > 1 ? 's' : ''} · ${formatDistance(best.distanceM)}';

/// Fenêtre douce à l'arrivée d'une réponse : « Voir les réponses » ou
/// « Plus tard ».
Future<void> _showResponsesSheet(
  BuildContext context, {
  required int count,
  required MedResponse best,
  required VoidCallback onOpen,
}) async {
  final open = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: IviaColors.surface,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 420),
      reverseDuration: Duration(milliseconds: 260),
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      final t = Theme.of(context).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            IviaSpacing.screen,
            0,
            IviaSpacing.screen,
            IviaSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 520),
                curve: Curves.elasticOut,
                builder: (_, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: IviaColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_pharmacy_rounded,
                    color: IviaColors.primary,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: IviaSpacing.lg),
              Text(
                _respondedTitle(count),
                textAlign: TextAlign.center,
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: IviaSpacing.sm),
              Text(
                'La plus proche : ${_bestLine(best)}.',
                textAlign: TextAlign.center,
                style: t.bodyLarge?.copyWith(color: Med.muted),
              ),
              const SizedBox(height: IviaSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Voir les réponses'),
                ),
              ),
              const SizedBox(height: IviaSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Plus tard'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (open == true) onOpen();
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.red = false});
  final int value;
  final String label;
  final bool red;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: MedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: t.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: red ? IviaColors.primary : Med.navy,
              ),
            ),
            Text(label, style: t.bodyMedium?.copyWith(color: Med.muted)),
          ],
        ),
      ),
    );
  }
}

/// Radar animé : pharmacies alertées autour du client, celles qui ont
/// répondu en rouge.
class _Radar extends StatefulWidget {
  const _Radar({required this.notified, required this.responded});
  final int notified, responded;

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = math.min(box.maxWidth, box.maxHeight);
      final dots = math.max(widget.notified, 1).clamp(1, 8);
      return Center(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2E4E8), width: 2),
                ),
              ),
              Container(
                width: size * .68,
                height: size * .68,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFF6E1E4),
                ),
              ),
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, _) => Container(
                  width: size * (.26 + .06 * _pulse.value),
                  height: size * (.26 + .06 * _pulse.value),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFF2C6CD),
                  ),
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: IviaColors.primary,
                  border: Border.all(color: Colors.white, width: 5),
                ),
              ),
              for (var i = 0; i < dots && widget.notified > 0; i++)
                Transform.translate(
                  offset: Offset.fromDirection(
                    -math.pi / 2 + i * 2 * math.pi / dots + .4,
                    size * (i.isEven ? .46 : .36),
                  ),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < widget.responded
                          ? IviaColors.primary
                          : Colors.white,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      i < widget.responded
                          ? Icons.check
                          : Icons.add_box_outlined,
                      color: i < widget.responded ? Colors.white : Med.navy,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// P14 : aucune pharmacie n'a confirmé.
class _EndedView extends ConsumerStatefulWidget {
  const _EndedView({required this.alert});
  final MedAlert alert;

  @override
  ConsumerState<_EndedView> createState() => _EndedViewState();
}

class _EndedViewState extends ConsumerState<_EndedView> {
  var _busy = false;

  int get _next => widget.alert.radiusM >= 10000 ? 20000 : 10000;

  Future<void> _relaunch() async {
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      final next = await api.relaunchAlert(widget.alert.id, _next);
      if (ref.read(devPaymentsProvider)) {
        Timer(
          const Duration(seconds: 8),
          () => api.devAutoRespond(next.id).catchError((_) {}),
        );
      }
      ref.invalidate(myAlertsProvider);
      if (mounted) context.go(Routes.medAlert(next.id));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = widget.alert;
    final cancelled = a.status == 'cancelled';
    return MedScaffold(
      top: MedTopBar(
        title: 'Alerte terminée',
        centered: true,
        onBack: () => context.go(Routes.pharmacy),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        children: [
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search_off, size: 40, color: Med.navy),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            cancelled
                ? 'Alerte annulée'
                : 'Aucune pharmacie n\'a confirmé vos produits',
            style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            cancelled
                ? 'Vous n\'avez rien payé.'
                : 'Les ${a.notified} pharmacies de garde dans un rayon de ${a.radiusM ~/ 1000} km n\'ont pas répondu à temps. Vous n\'avez rien payé.',
            style: t.bodyLarge?.copyWith(color: Med.muted),
          ),
          const SizedBox(height: 20),
          MedCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const MedIconTile(
                    Icons.track_changes,
                    bg: Med.softRed,
                    fg: IviaColors.primary,
                  ),
                  title: Text(
                    'Élargir à ${_next ~/ 1000} km',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('Plus de pharmacies de garde'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _relaunch,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const MedIconTile(Icons.edit_outlined),
                  title: Text(
                    'Modifier les produits',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('Autre dosage, générique'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ref.read(medDraftProvider.notifier).fromAlert(a);
                    context.push(Routes.medItems);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      bottom: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            IviaSpacing.screen,
            8,
            IviaSpacing.screen,
            IviaSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 64,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: IviaColors.primary,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: _busy ? null : _relaunch,
                  icon: const Icon(Icons.campaign_outlined),
                  label: Text(
                    'Relancer à ${_next ~/ 1000} km',
                    style: t.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              MedOutlineButton(
                label: 'Appeler une pharmacie de garde',
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => Consumer(
                    builder: (context, ref, _) {
                      final duty =
                          ref.watch(onDutyPharmaciesProvider).value ??
                          const <OnDutyPharmacy>[];
                      return SafeArea(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          children: [
                            for (final p in duty) OnDutyTile(pharmacy: p),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// P08 : réponses des pharmacies (anonymes avant déblocage).
class ResponsesScreen extends ConsumerStatefulWidget {
  const ResponsesScreen({super.key, required this.alertId});
  final String alertId;

  @override
  ConsumerState<ResponsesScreen> createState() => _ResponsesScreenState();
}

class _ResponsesScreenState extends ConsumerState<ResponsesScreen>
    with LivePolling {
  var _sort = 0; // 0 plus proches, 1 tout disponible, 2 moins cher

  @override
  void initState() {
    super.initState();
    startPolling(() => ref.invalidate(medAlertProvider(widget.alertId)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final alert = ref.watch(medAlertProvider(widget.alertId)).value;
    if (alert == null) {
      return const MedScaffold(
        top: MedTopBar(title: 'Réponses'),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final now = ref.read(apiClientProvider).now();
    final left = alert.searchEndsAt.difference(now);
    var list = alert.responses
        .where((r) => r.status != 'withdrawn' || r.unlocked)
        .toList();
    switch (_sort) {
      case 1:
        list = list.where((r) => r.allAvailable).toList()
          ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
      case 2:
        list.sort((a, b) => a.totalXof.compareTo(b.totalXof));
      default:
        list.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    }
    return MedScaffold(
      top: MedTopBar(
        title: 'Réponses',
        centered: true,
        trailing: left > Duration.zero
            ? MedPill.minutes(left)
            : const SizedBox(width: 56),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          IviaSpacing.screen,
          0,
          IviaSpacing.screen,
          IviaSpacing.xxl,
        ),
        children: [
          Text(
            '${alert.responded} pharmacie${alert.responded > 1 ? 's ont' : ' a'} répondu',
            style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Nom, adresse et numéro sont visibles après déblocage.',
            style: t.bodyLarge?.copyWith(color: Med.muted),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, label) in [
                  'Plus proches',
                  'Tout disponible',
                  'Moins cher',
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  ChoiceChip(
                    label: Text(label),
                    selected: _sort == i,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _sort = i),
                    selectedColor: Med.navy,
                    backgroundColor: Colors.white,
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    labelStyle: t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _sort == i ? Colors.white : Med.navy,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final (i, r) in list.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ResponseCard(
                response: r,
                fee: alert.unlockFeeXof,
                highlight: i == 0,
                now: now,
                onUnlock: () => r.unlocked && r.reservationId != null
                    ? context.push(Routes.medReservation(r.reservationId!))
                    : context.push(Routes.medUnlock(alert.id, r.id)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResponseCard extends StatelessWidget {
  const _ResponseCard({
    required this.response,
    required this.fee,
    required this.highlight,
    required this.now,
    required this.onUnlock,
  });

  final MedResponse response;
  final int fee;
  final bool highlight;
  final DateTime now;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final r = response;
    final t = Theme.of(context).textTheme;
    final all = r.availableCount == r.lineCount;
    return MedCard(
      border: highlight ? IviaColors.primary : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                r.unlocked ? Icons.lock_open : Icons.lock_outline,
                color: Med.navy,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: r.unlocked && r.pharmacy != null
                    ? Text(
                        r.pharmacy!.name,
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 160,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3E5E9),
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                      ),
              ),
              Text(
                formatDistance(r.distanceM),
                style: t.titleMedium?.copyWith(
                  color: Med.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              MedPill(
                '${r.availableCount} / ${r.lineCount} disponible${r.availableCount > 1 ? 's' : ''}',
                bg: all ? const Color(0xFFDDE7F7) : Med.softYellow,
                fg: all ? Med.blue : Med.yellow,
              ),
              const SizedBox(width: 12),
              Text(
                agoLabel(r.respondedAt, now),
                style: t.bodyMedium?.copyWith(color: Med.muted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final l in r.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l.name} ×${l.quantity}',
                      style: t.bodyLarge?.copyWith(
                        decoration: l.available
                            ? null
                            : TextDecoration.lineThrough,
                        color: l.available ? Med.navy : Med.muted,
                      ),
                    ),
                  ),
                  Text(
                    l.available ? formatXof(l.lineTotalXof) : 'Indisponible',
                    style: l.available
                        ? t.titleMedium?.copyWith(fontWeight: FontWeight.w800)
                        : t.bodyLarge?.copyWith(color: Med.muted),
                  ),
                ],
              ),
            ),
          const Divider(height: 28),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total indicatif',
                      style: t.bodyMedium?.copyWith(color: Med.muted),
                    ),
                    Text(
                      formatXof(r.totalXof),
                      style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: highlight ? IviaColors.primary : Med.navy,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                  ),
                  onPressed: onUnlock,
                  icon: Icon(
                    r.unlocked ? Icons.arrow_forward : Icons.lock_outline,
                  ),
                  label: Text(
                    r.unlocked ? 'Voir' : 'Débloquer · ${formatXof(fee)}',
                    style: t.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// P09 : débloquer une pharmacie (forfait d'accès par Mobile Money).
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({
    super.key,
    required this.alertId,
    required this.responseId,
  });
  final String alertId, responseId;

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final alert = ref.watch(medAlertProvider(widget.alertId)).value;
    final fee = alert?.unlockFeeXof ?? 0;
    return MedPaymentPage(
      title: 'Débloquer',
      step: 'Étape 3 sur 3',
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Forfait d\'accès',
            style: t.bodyLarge?.copyWith(color: Med.muted),
          ),
          Text(
            '${groupDigits(fee)} FCFA',
            style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          MedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vous obtenez',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                for (final (icon, text) in [
                  (Icons.place_outlined, 'L\'adresse exacte et l\'itinéraire'),
                  (Icons.call_outlined, 'Le numéro de la pharmacie'),
                  (Icons.inventory_2_outlined, 'Vos produits mis de côté 1 h'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      children: [
                        Icon(icon, color: Med.blue),
                        const SizedBox(width: 14),
                        Expanded(child: Text(text, style: t.bodyLarge)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      amountXof: fee,
      start: (op, phone) async {
        final res = await ref
            .read(apiClientProvider)
            .unlockResponse(
              widget.alertId,
              widget.responseId,
              operator: op,
              phone: phone,
            );
        return (res.payment, res.reservationId);
      },
      onPaid: (reservationId) async {
        var id = reservationId;
        if (id == null) {
          final fresh = await ref
              .read(apiClientProvider)
              .medAlert(widget.alertId);
          id = fresh.responses
              .where((x) => x.id == widget.responseId)
              .firstOrNull
              ?.reservationId;
        }
        ref.invalidate(medAlertProvider(widget.alertId));
        if (id != null && context.mounted) {
          context.pushReplacement(Routes.medReservation(id));
        }
      },
    );
  }
}

/// Page de paiement Mobile Money (P09, P11) : opérateur avec logo, numéro,
/// attente de la validation sur le téléphone.
class MedPaymentPage extends ConsumerStatefulWidget {
  const MedPaymentPage({
    super.key,
    required this.title,
    required this.header,
    required this.amountXof,
    required this.start,
    required this.onPaid,
    this.step,
  });

  final String title;
  final String? step;
  final Widget header;
  final int amountXof;
  final Future<(MedPayment?, String?)> Function(
    PaymentOperator op,
    String phone,
  )
  start;
  final Future<void> Function(String? reservationId) onPaid;

  @override
  ConsumerState<MedPaymentPage> createState() => _MedPaymentPageState();
}

class _MedPaymentPageState extends ConsumerState<MedPaymentPage> {
  var _op = PaymentOperator.flooz;
  final _phone = TextEditingController();
  MedPayment? _payment;
  String? _reservationId;
  String? _error;
  var _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final user = switch (ref.read(authControllerProvider)) {
      AuthSignedIn(:final user) => user,
      _ => null,
    };
    _phone.text = formatTogoPhone(user?.phone ?? '');
  }

  @override
  void dispose() {
    _poll?.cancel();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final digits = togoPhoneDigits(_phone.text);
    if (!isTogoMobile(digits)) {
      setState(() => _error = 'Numéro Mobile Money togolais attendu.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (payment, reservationId) = await widget.start(_op, '+228$digits');
      _reservationId = reservationId;
      if (payment == null || payment.succeeded) {
        await widget.onPaid(reservationId ?? payment?.reservationId);
        return;
      }
      setState(() => _payment = payment);
      // En local, le faux prestataire valide comme le ferait le client sur
      // son téléphone, quelques secondes plus tard.
      if (ref.read(devPaymentsProvider)) {
        Timer(
          const Duration(seconds: 4),
          () => ref
              .read(apiClientProvider)
              .devSimulateMedPayment(payment.id)
              .catchError((_) {}),
        );
      }
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final id = _payment?.id;
    if (id == null) return;
    try {
      final p = await ref.read(apiClientProvider).medPayment(id);
      if (!mounted) return;
      if (p.succeeded) {
        _poll?.cancel();
        await widget.onPaid(_reservationId ?? p.reservationId);
      } else if (!p.pending) {
        _poll?.cancel();
        setState(() {
          _payment = null;
          _error = p.failureReason.isEmpty
              ? 'Paiement non abouti. Réessayez.'
              : p.failureReason;
        });
      }
    } on ApiException {
      // Nouvel essai au prochain tour.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final waiting = _payment != null;
    final opName = _op == PaymentOperator.flooz ? 'Flooz' : 'T-Money';
    return MedScaffold(
      top: MedTopBar(
        title: widget.title,
        centered: true,
        trailing: widget.step == null ? null : MedPill(widget.step!),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        children: [
          widget.header,
          const SizedBox(height: 22),
          if (waiting)
            MedCard(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  const CircularProgressIndicator(color: IviaColors.primary),
                  const SizedBox(height: 18),
                  Text(
                    'Validez le paiement sur votre téléphone',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _payment!.instructions.isNotEmpty
                        ? _payment!.instructions
                        : 'Une demande $opName de ${formatXof(widget.amountXof)} a été envoyée au ${formatMaskedTogoPhone(_payment!.phoneMasked)}. Tapez votre code secret.',
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: Med.muted),
                  ),
                ],
              ),
            )
          else ...[
            Text(
              'Opérateur',
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final op in PaymentOperator.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MedCard(
                  border: _op == op ? IviaColors.primary : null,
                  onTap: () => setState(() => _op = op),
                  child: Row(
                    children: [
                      PaymentLogo.operator(op, size: 52),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              op == PaymentOperator.flooz ? 'Flooz' : 'T-Money',
                              style: t.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              operatorBrand(op),
                              style: t.bodySmall?.copyWith(color: Med.muted),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _op == op
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: _op == op
                            ? IviaColors.primary
                            : const Color(0xFFC9CDD4),
                        size: 30,
                      ),
                    ],
                  ),
                ),
              ),
            const CardPaymentSoon(),
            const SizedBox(height: 20),
            TogoPhoneField(
              label: 'Numéro $opName',
              controller: _phone,
              enabled: !_busy,
              errorText: _error,
            ),
          ],
          if (waiting && _error != null)
            Text(_error!, style: const TextStyle(color: IviaColors.error)),
          const SizedBox(height: 20),
        ],
      ),
      bottom: waiting
          ? null
          : MedBottomButton(
              label: 'Payer ${groupDigits(widget.amountXof)} FCFA',
              busy: _busy,
              onTap: _pay,
            ),
    );
  }
}
