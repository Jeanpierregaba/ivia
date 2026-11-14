import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/ui.dart';

/// Tableau de bord de la pharmacie sur 7 ou 30 jours (spec 042).
final pharmacyStatsProvider = FutureProvider.autoDispose
    .family<PharmacyStats, int>(
      (ref, days) => ref.read(apiClientProvider).pharmacyStats(days: days),
      retry: (_, _) => null,
    );

const _weekdays = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _months = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _day(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// « Activité » de l'accueil : taux de réponse, temps de réponse, ventes,
/// alertes jour par jour, heures d'affluence, médicaments les plus demandés.
/// Tout vient des vraies alertes et réservations de la pharmacie.
class PharmacyDashboard extends ConsumerStatefulWidget {
  const PharmacyDashboard({super.key});

  @override
  ConsumerState<PharmacyDashboard> createState() => _PharmacyDashboardState();
}

class _PharmacyDashboardState extends ConsumerState<PharmacyDashboard> {
  var _days = 7;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(pharmacyStatsProvider(_days));
    if (stats.hasError && stats.value == null) return const SizedBox.shrink();
    final s = stats.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Votre activité',
                style: PText.figure.copyWith(fontSize: 20),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in const [7, 30])
                  _PeriodChip(
                    label: '$d jours',
                    on: _days == d,
                    onTap: () => setState(() => _days = d),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          child: s == null
              ? const Center(
                  key: ValueKey('loading'),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: P.green),
                  ),
                )
              : s.totals.received == 0 && s.previous.received == 0
              ? const PEmpty(
                  key: ValueKey('empty'),
                  icon: Icons.insights_rounded,
                  text:
                      'Vos statistiques apparaîtront ici dès vos premières '
                      'alertes : taux de réponse, ventes, heures '
                      "d'affluence et médicaments les plus demandés.",
                )
              : _Content(key: ValueKey('stats-$_days'), stats: s),
        ),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({super.key, required this.stats});
  final PharmacyStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final peak = s.hours.isEmpty ? 0 : s.hours.reduce(math.max);
    final peakHour = peak == 0 ? null : s.hours.indexOf(peak);
    final topCount = s.topMedicines.isEmpty
        ? 0
        : s.topMedicines.first.responses;
    final missed = s.totals.received - s.totals.responded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth > 340 ? (c.maxWidth - 10) / 2 : c.maxWidth;
            final tiles = [
              _Kpi(
                icon: Icons.notifications_active_rounded,
                color: P.green,
                label: 'Alertes reçues',
                value: s.totals.received,
                previous: s.previous.received,
                text: (v) => '$v',
              ),
              _Kpi(
                icon: Icons.verified_rounded,
                color: P.blue,
                label: 'Taux de réponse',
                value: s.totals.responseRate,
                previous: s.previous.responseRate,
                text: (v) => '$v %',
              ),
              _Kpi(
                icon: Icons.timer_rounded,
                color: P.yellow,
                label: 'Temps de réponse moyen',
                value: s.totals.avgResponseMin,
                previous: s.previous.avgResponseMin,
                text: (v) => '$v min',
                lowerIsBetter: true,
              ),
              _Kpi(
                icon: Icons.payments_rounded,
                color: P.greenDeep,
                label: 'Ventes terminées',
                value: s.totals.salesXof,
                previous: s.previous.salesXof,
                text: formatXof,
              ),
            ];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final k in tiles) SizedBox(width: w, child: k)],
            );
          },
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'Alertes par jour',
          subtitle: 'Touchez ou glissez sur une barre',
          child: IviaBarChart(
            semanticsLabel: 'Alertes reçues par jour',
            color: P.green,
            values: [for (final d in s.series) d.received],
            labels: [
              for (final d in s.series)
                s.days <= 7 ? _weekdays[d.date.weekday - 1] : '${d.date.day}',
            ],
            tooltip: (i) {
              final d = s.series[i];
              return '${_day(d.date)} · ${d.received} reçue'
                  '${d.received > 1 ? 's' : ''} · ${d.responded} répondue'
                  '${d.responded > 1 ? 's' : ''}';
            },
          ),
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'Réponses',
          subtitle: s.totals.reservations > 0
              ? '${s.totals.reservations} réservation'
                    '${s.totals.reservations > 1 ? 's' : ''} · '
                    '${s.totals.completed} terminée'
                    '${s.totals.completed > 1 ? 's' : ''}'
              : 'Aucune réservation sur la période',
          child: IviaDonut(
            parts: [
              IviaDonutPart('Disponible', s.totals.responded, P.green),
              IviaDonutPart('Sans réponse', math.max(0, missed), P.line),
            ],
            center: Text(
              '${s.totals.responseRate} %',
              style: PText.figure.copyWith(color: P.green),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: "Heures d'affluence",
          subtitle: peakHour == null
              ? 'Alertes selon l’heure de la journée'
              : 'Le plus d’alertes vers $peakHour h',
          child: IviaBarChart(
            semanticsLabel: 'Alertes par heure',
            color: P.blue,
            height: 120,
            labelEvery: 6,
            values: s.hours,
            labels: [for (var h = 0; h < 24; h++) '$h h'],
            tooltip: (h) =>
                '$h h – ${h + 1} h · ${s.hours[h]} alerte'
                '${s.hours[h] > 1 ? 's' : ''}',
          ),
        ),
        if (s.topMedicines.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Médicaments les plus demandés',
            subtitle: 'Parmi les alertes auxquelles vous avez répondu',
            child: Column(
              children: [
                for (final (i, m) in s.topMedicines.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 8,
                          children: [
                            Text(
                              '${i + 1}. ${m.name}',
                              style: PText.body.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${m.responses} réponse'
                              '${m.responses > 1 ? 's' : ''} · '
                              '${m.reservations} réservé'
                              '${m.reservations > 1 ? 's' : ''}',
                              style: PText.small,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        IviaMeter(
                          ratio: topCount == 0 ? 0 : m.responses / topCount,
                          color: i == 0 ? P.green : P.blue,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.previous,
    required this.text,
    this.lowerIsBetter = false,
  });
  final IconData icon;
  final Color color;
  final String label;
  final int value, previous;
  final String Function(int) text;
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) {
    final trend = previous == 0
        ? (value > 0 ? null : 0)
        : ((value - previous) * 100 / previous).round();
    final up = (trend ?? 1) >= 0;
    final good = lowerIsBetter ? !up : up;
    final trendColor = trend == 0 ? P.muted : (good ? P.green : P.red);
    return PCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const Spacer(),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    trend == null
                        ? 'nouveau'
                        : '${up ? '▲' : '▼'} ${trend.abs()} %',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PText.pill.copyWith(color: trendColor),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                begin: IviaMotion.reduced(context) ? value.toDouble() : 0,
                end: value.toDouble(),
              ),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Text(text(v.round()), style: PText.figure),
            ),
          ),
          Text(label, style: PText.small),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title, subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => PCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: PText.cardTitle),
        Text(subtitle, style: PText.small),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.on,
    required this.onTap,
  });
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? P.green : Colors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: on ? P.green : P.line),
        ),
        child: Text(
          label,
          style: PText.label.copyWith(color: on ? Colors.white : P.ink),
        ),
      ),
    ),
  );
}
