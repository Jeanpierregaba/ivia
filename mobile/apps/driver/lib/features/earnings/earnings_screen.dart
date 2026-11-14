import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/driver_dossier.dart';
import '../../common/ui.dart';
import 'earnings.dart';

/// Onglet Gains (D18) : « Semaine » et « Mois », calculés depuis
/// l'historique des missions (jours de Lomé). Total, variation, barres,
/// nombre de livraisons, compte de versement (numéro masqué), liste par
/// jour. Km, temps en ligne et versement prévu : masqués (spec 033).
class EarningsTab extends ConsumerStatefulWidget {
  const EarningsTab({super.key});

  @override
  ConsumerState<EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends ConsumerState<EarningsTab> {
  var _period = EarningsPeriod.week;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(missionHistoryProvider);
    final missions = history.value ?? const <WorkMission>[];
    final s = summarize(missions, _period, ref.read(apiClientProvider).now());
    final payout = ref.watch(driverDossierProvider).value?.payout;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(missionHistoryProvider);
        await ref.read(missionHistoryProvider.future).catchError((_) {
          return const <WorkMission>[];
        });
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          D.gutter,
          MediaQuery.paddingOf(context).top + 12,
          D.gutter,
          24,
        ),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 10,
            spacing: 12,
            children: [
              Semantics(
                header: true,
                child: Text('Gains', style: DText.hero.copyWith(fontSize: 34)),
              ),
              _PeriodSwitch(
                period: _period,
                onSelect: (p) => setState(() => _period = p),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Summary(summary: s, period: _period),
          if (history.hasError && !history.hasValue) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Impossible de charger les gains.',
                    style: DText.body.copyWith(color: IviaColors.error),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(missionHistoryProvider),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ],
          if (payout != null) ...[
            const SizedBox(height: 12),
            _PayoutCard(payout: payout),
          ],
          const SizedBox(height: 12),
          _DayList(days: s.days),
        ],
      ),
    );
  }
}

/// « Semaine » / « Mois » : pilule sombre sur fond blanc.
class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({required this.period, required this.onSelect});
  final EarningsPeriod period;
  final ValueChanged<EarningsPeriod> onSelect;

  @override
  Widget build(BuildContext context) {
    // Grande police : toute la largeur, sous le titre.
    final big = MediaQuery.textScalerOf(context).scale(10) > 15;
    Widget item(EarningsPeriod p, String label) => Semantics(
      button: true,
      selected: p == period,
      child: Material(
        color: p == period ? D.night : Colors.transparent,
        borderRadius: BorderRadius.circular(IviaRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onSelect(p),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, minWidth: 84),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Center(
                widthFactor: 1,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: DText.button.copyWith(
                      fontSize: 15,
                      color: p == period ? Colors.white : D.label,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final items = [
      item(EarningsPeriod.week, 'Semaine'),
      item(EarningsPeriod.month, 'Mois'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(IviaRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: big ? MainAxisSize.max : MainAxisSize.min,
          children: [for (final w in items) big ? Expanded(child: w) : w],
        ),
      ),
    );
  }
}

/// Carte sombre : période, total, variation, barres, livraisons.
class _Summary extends StatelessWidget {
  const _Summary({required this.summary, required this.period});
  final PeriodSummary summary;
  final EarningsPeriod period;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final n = s.totals.deliveries;
    return DCard.dark(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        periodTitle(s, period),
                        style: DText.overline.copyWith(color: D.nightMuted),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          formatXof(s.totals.earnedXof),
                          style: DText.amount.copyWith(
                            color: Colors.white,
                            fontSize: 44,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (s.changePercent case final change?) ...[
                  const SizedBox(width: 8),
                  _Change(percent: change, period: period),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Bars(summary: s),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _NightPill('$n livraison${n > 1 ? 's' : ''}'),
          ),
        ],
      ),
    );
  }
}

class _Change extends StatelessWidget {
  const _Change({required this.percent, required this.period});
  final int percent;
  final EarningsPeriod period;

  @override
  Widget build(BuildContext context) {
    final previous = period == EarningsPeriod.week
        ? 'la semaine dernière'
        : 'le mois dernier';
    return Semantics(
      label: '${changeLabel(percent)} par rapport à $previous',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: D.nightTile,
          borderRadius: BorderRadius.circular(IviaRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              percent < 0
                  ? Icons.trending_down_rounded
                  : Icons.trending_up_rounded,
              size: 16,
              color: D.blueOnDark,
            ),
            const SizedBox(width: 6),
            Text(
              changeLabel(percent),
              style: DText.pill.copyWith(color: D.blueOnDark, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barres des gains ; la meilleure est en bleu clair.
class _Bars extends StatelessWidget {
  const _Bars({required this.summary});
  final PeriodSummary summary;

  static const _height = 76.0, _stub = 18.0;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final max = s.bars.fold<int>(0, (m, v) => v > m ? v : m);
    final best = s.best;
    final reading = [
      for (final (i, v) in s.bars.indexed) '${s.barNames[i]} ${formatXof(v)}',
    ].join(', ');
    return Semantics(
      label: 'Gains : $reading',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, v) in s.bars.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: _height,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: max == 0
                            ? _stub
                            : _stub + (_height - _stub) * v / max,
                        decoration: BoxDecoration(
                          color: i == best ? D.blueOnDark : D.nightTile,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.4,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        s.barLabels[i],
                        style: DText.pill.copyWith(
                          fontSize: 13,
                          color: i == best ? Colors.white : D.nightMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NightPill extends StatelessWidget {
  const _NightPill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: D.nightTile,
      borderRadius: BorderRadius.circular(IviaRadius.pill),
    ),
    child: Text(
      text,
      style: DText.pill.copyWith(color: Colors.white, fontSize: 14),
    ),
  );
}

/// Compte de versement : opérateur et numéro masqué, sans date ni montant.
class _PayoutCard extends StatelessWidget {
  const _PayoutCard({required this.payout});
  final DriverPayout payout;

  @override
  Widget build(BuildContext context) => DCard(
    padding: const EdgeInsets.all(16),
    child: MergeSemantics(
      child: Row(
        children: [
          const DIconTile(Icons.account_balance_wallet_rounded, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compte de versement',
                  style: DText.cardTitle.copyWith(fontSize: 17),
                ),
                Text(
                  [
                    switch (payout.operator) {
                      PayoutOperator.flooz => 'Flooz',
                      PayoutOperator.tmoney => 'T-Money',
                    },
                    if (payout.phoneMasked.isNotEmpty) payout.phoneMasked,
                  ].join(' · '),
                  style: DText.bodyMuted.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Jours livrés de la période, du plus récent au plus ancien.
class _DayList extends StatelessWidget {
  const _DayList({required this.days});
  final List<DayTotals> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Aucune livraison sur cette période.',
          textAlign: TextAlign.center,
          style: DText.body.copyWith(fontSize: 15),
        ),
      );
    }
    return DCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, d) in days.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == days.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: D.line)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: MergeSemantics(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dayTitle(d.day),
                              style: DText.cardTitle.copyWith(fontSize: 17),
                            ),
                            Text(
                              '${d.totals.deliveries} livraison'
                              '${d.totals.deliveries > 1 ? 's' : ''}',
                              style: DText.bodyMuted.copyWith(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatXof(d.totals.earnedXof),
                        style: DText.amount.copyWith(fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
