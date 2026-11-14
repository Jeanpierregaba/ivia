import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/seller_shop.dart';
import '../business/biz_ui.dart';
import '../business/pro_ui.dart' show CountUp;

/// Tableau de bord de la boutique sur 7 ou 30 jours (spec 042).
final sellerStatsProvider = FutureProvider.autoDispose
    .family<SellerStats?, int>((ref, days) async {
      final shopId = ref.watch(sellerShopProvider.select((s) => s.value?.id));
      if (shopId == null) return null;
      return ref.read(apiClientProvider).sellerStats(shopId, days: days);
    }, retry: (_, _) => null);

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

/// « Performances » de l'Accueil : chiffres clés et leur tendance, ventes par
/// jour, heures de pointe, meilleurs produits, retrait ou livraison. Rien
/// d'inventé : sans vente, un état vide l'explique.
class StatsDashboard extends ConsumerStatefulWidget {
  const StatsDashboard({super.key});

  @override
  ConsumerState<StatsDashboard> createState() => _StatsDashboardState();
}

class _StatsDashboardState extends ConsumerState<StatsDashboard> {
  var _days = 7;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final stats = ref.watch(sellerStatsProvider(_days));
    // Lecture en échec (hors ligne, ancienne API) : la section se retire.
    if (stats.hasError && stats.value == null) return const SizedBox.shrink();
    final s = stats.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Performances',
                  style: t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Biz.navy,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in const [7, 30])
                    BizFilterChip(
                      label: '$d jours',
                      active: _days == d,
                      onTap: () => setState(() => _days = d),
                    ),
                ],
              ),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: Biz.medium,
          child: s == null
              ? const _Loading(key: ValueKey('loading'))
              : s.totals.orders == 0 && s.previous.orders == 0
              ? const BizCard(
                  key: ValueKey('empty'),
                  child: BizEmpty(
                    icon: Icons.insights_rounded,
                    title: 'Vos statistiques arrivent',
                    body:
                        'Dès votre première vente, retrouvez ici vos ventes '
                        'jour par jour, vos heures de pointe et vos meilleurs '
                        'produits.',
                  ),
                )
              : _Content(key: ValueKey('stats-$_days'), stats: s),
        ),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({super.key, required this.stats});
  final SellerStats stats;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = stats;
    final peak = s.hours.isEmpty ? 0 : s.hours.reduce(math.max);
    final peakHour = peak == 0 ? null : s.hours.indexOf(peak);
    final topSales = s.topProducts.isEmpty ? 0 : s.topProducts.first.salesXof;
    final pickup = s.totals.orders - s.totals.deliveries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth > 340 ? (c.maxWidth - 10) / 2 : c.maxWidth;
            final tiles = [
              _Kpi(
                icon: Icons.payments_rounded,
                color: Biz.green,
                label: "Chiffre d'affaires",
                value: s.totals.salesXof,
                previous: s.previous.salesXof,
                format: formatXof,
              ),
              _Kpi(
                icon: Icons.receipt_long_rounded,
                color: Biz.blue,
                label: 'Commandes',
                value: s.totals.orders,
                previous: s.previous.orders,
                format: (v) => '$v',
              ),
              _Kpi(
                icon: Icons.shopping_basket_rounded,
                color: const Color(0xFF7A3FD6),
                label: 'Panier moyen',
                value: s.totals.avgBasketXof,
                previous: s.previous.avgBasketXof,
                format: formatXof,
              ),
              _Kpi(
                icon: Icons.people_alt_rounded,
                color: Biz.amber,
                label: 'Clients',
                value: s.totals.buyers,
                previous: s.previous.buyers,
                format: (v) => '$v',
              ),
            ];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (i, k) in tiles.indexed)
                  SizedBox(
                    width: w,
                    child: BizReveal(index: i, child: k),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        BizReveal(
          index: 4,
          child: _ChartCard(
            title: 'Ventes par jour',
            subtitle: 'Touchez ou glissez sur une barre',
            child: IviaBarChart(
              semanticsLabel: 'Ventes par jour',
              values: [for (final d in s.series) d.salesXof],
              labels: [
                for (final d in s.series)
                  s.days <= 7 ? _weekdays[d.date.weekday - 1] : '${d.date.day}',
              ],
              tooltip: (i) {
                final d = s.series[i];
                return '${_day(d.date)} · ${formatXof(d.salesXof)} · '
                    '${d.orders} cmd';
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        BizReveal(
          index: 5,
          child: _ChartCard(
            title: 'Heures de pointe',
            subtitle: peakHour == null
                ? 'Commandes selon l’heure de la journée'
                : 'Le plus de commandes vers $peakHour h',
            child: IviaBarChart(
              semanticsLabel: 'Commandes par heure',
              color: Biz.amber,
              height: 120,
              labelEvery: 6,
              values: s.hours,
              labels: [for (var h = 0; h < 24; h++) '$h h'],
              tooltip: (h) =>
                  '$h h – ${h + 1} h · ${s.hours[h]} commande'
                  '${s.hours[h] > 1 ? 's' : ''}',
            ),
          ),
        ),
        if (s.topProducts.isNotEmpty) ...[
          const SizedBox(height: 12),
          BizReveal(
            index: 6,
            child: _ChartCard(
              title: 'Meilleurs produits',
              subtitle: 'Classés par ventes sur la période',
              child: Column(
                children: [
                  for (final (i, p) in s.topProducts.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: i == 0
                                  ? const Color(0xFFFFF1D6)
                                  : Biz.page,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: t.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: i == 0 ? Biz.amber : Biz.navy,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  spacing: 8,
                                  children: [
                                    Text(
                                      p.name,
                                      style: t.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${formatXof(p.salesXof)} · ${p.quantity} vendu'
                                      '${p.quantity > 1 ? 's' : ''}',
                                      style: t.bodySmall?.copyWith(
                                        color: Biz.muted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                IviaMeter(
                                  ratio: topSales == 0
                                      ? 0
                                      : p.salesXof / topSales,
                                  color: i == 0 ? Biz.amber : Biz.blue,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (s.totals.orders > 0) ...[
          const SizedBox(height: 12),
          BizReveal(
            index: 7,
            child: _ChartCard(
              title: 'Retrait ou livraison',
              subtitle: s.totals.cancelled > 0
                  ? '${s.totals.cancelled} commande'
                        '${s.totals.cancelled > 1 ? 's annulées' : ' annulée'}'
                        ' sur la période'
                  : 'Aucune commande annulée sur la période',
              child: IviaDonut(
                parts: [
                  IviaDonutPart('Retrait', pickup, Biz.blue),
                  IviaDonutPart('Livraison', s.totals.deliveries, Biz.red),
                ],
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${s.totals.orders}',
                      style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Biz.navy,
                      ),
                    ),
                    Text(
                      'commandes',
                      style: t.labelSmall?.copyWith(color: Biz.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Chiffre clé avec sa tendance par rapport à la période précédente.
class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.previous,
    required this.format,
  });
  final IconData icon;
  final Color color;
  final String label;
  final int value, previous;
  final String Function(int) format;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final trend = previous == 0
        ? (value > 0 ? null : 0)
        : ((value - previous) * 100 / previous).round();
    final up = (trend ?? 1) >= 0;
    final trendColor = trend == 0 ? Biz.muted : (up ? Biz.green : Biz.red);
    return BizCard(
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
                    style: t.labelSmall?.copyWith(
                      color: trendColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CountUp(
              value: value,
              format: format,
              style: t.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: Biz.navy,
              ),
            ),
          ),
          Text(label, style: t.bodySmall?.copyWith(color: Biz.muted)),
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
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return BizCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: t.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Biz.navy,
            ),
          ),
          Text(subtitle, style: t.bodySmall?.copyWith(color: Biz.muted)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Row(
        children: [
          Expanded(child: BizSkeleton(height: 96, radius: 22)),
          SizedBox(width: 10),
          Expanded(child: BizSkeleton(height: 96, radius: 22)),
        ],
      ),
      SizedBox(height: 12),
      BizSkeleton(height: 240, radius: 22),
    ],
  );
}
