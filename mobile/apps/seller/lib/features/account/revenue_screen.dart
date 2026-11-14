import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/seller_shop.dart';

final settlementsProvider = FutureProvider.autoDispose<List<Settlement>>((
  ref,
) async {
  final shop = ref.watch(sellerShopProvider).value;
  if (shop == null) return const [];
  return ref.read(apiClientProvider).sellerSettlements(shop.id);
});

String _day(DateTime d) {
  const m = [
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
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String period(Settlement s) =>
    'Du ${_day(s.periodStart)} au ${_day(s.periodEnd)}';

/// Revenus : relevés de reversement établis par ivia (ventes livrées moins
/// la commission), reversés ou à reverser.
class RevenueScreen extends ConsumerWidget {
  const RevenueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final list = ref.watch(settlementsProvider);
    final items = list.value ?? const <Settlement>[];
    final pending = items
        .where((s) => !s.settled)
        .fold<int>(0, (a, s) => a + s.netXof);
    final paid = items
        .where((s) => s.settled)
        .fold<int>(0, (a, s) => a + s.netXof);
    final gross = items.fold<int>(0, (a, s) => a + s.grossXof);
    return Scaffold(
      backgroundColor: IviaColors.background,
      appBar: AppBar(
        backgroundColor: IviaColors.background,
        title: const Text('Revenus'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(settlementsProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: IviaColors.berkeleyBlue,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'À recevoir',
                    style: t.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                  Text(
                    formatXof(pending),
                    style: t.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Reversé par ivia sur votre Mobile Money à chaque relevé.',
                    style: t.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: IviaSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _Kpi(label: 'Déjà reversé', value: formatXof(paid)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Kpi(label: 'Ventes brutes', value: formatXof(gross)),
                ),
              ],
            ),
            const SizedBox(height: IviaSpacing.xxl),
            Text(
              'Relevés',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: IviaSpacing.md),
            if (list.isLoading && items.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (list.hasError && items.isEmpty)
              const Text(
                'Relevés indisponibles. Tirez vers le bas pour réessayer.',
              )
            else if (items.isEmpty)
              _Box(
                child: Text(
                  'Aucun relevé pour l\'instant. ivia établit un relevé des '
                  'commandes livrées à chaque période de reversement.',
                  style: t.bodyMedium,
                ),
              ),
            for (final s in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _Box(
                  onTap: () => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettlementScreen(id: s.id),
                    ),
                  ),
                  child: Row(
                    children: [
                      _StatusIcon(settled: s.settled),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              period(s),
                              style: t.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${s.ordersCount} commande${s.ordersCount > 1 ? 's' : ''} · '
                              '${s.settled ? 'reversé' : 'à reverser'}',
                              style: t.bodySmall?.copyWith(
                                color: IviaColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatXof(s.netXof),
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: s.settled ? IviaColors.success : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Détail d'un relevé : commande par commande.
class SettlementScreen extends ConsumerWidget {
  const SettlementScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final future = ref.watch(_settlementProvider(id));
    final s = future.value;
    Widget row(String a, String b, {bool bold = false, Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(a, style: t.bodyLarge)),
              Text(
                b,
                style: (bold ? t.titleLarge : t.titleSmall)?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        );
    return Scaffold(
      backgroundColor: IviaColors.background,
      appBar: AppBar(
        backgroundColor: IviaColors.background,
        title: const Text('Relevé'),
      ),
      body: s == null
          ? Center(
              child: future.hasError
                  ? const Text('Relevé indisponible.')
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(IviaSpacing.screen),
              children: [
                Text(
                  period(s),
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: s.settled
                          ? IviaColors.successSoft
                          : IviaColors.warningSoft,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      s.settled
                          ? 'Reversé le ${_day(s.settledAt!.toLocal())}'
                                '${s.reference.isEmpty ? '' : ' · ${s.reference}'}'
                          : 'À reverser',
                      style: t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: s.settled
                            ? IviaColors.success
                            : IviaColors.warning,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: IviaSpacing.xl),
                _Box(
                  child: Column(
                    children: [
                      row(
                        'Ventes livrées (${s.ordersCount})',
                        formatXof(s.grossXof),
                      ),
                      row(
                        'Commission ivia',
                        '− ${formatXof(s.commissionXof)}',
                        color: IviaColors.textMuted,
                      ),
                      const Divider(height: 24),
                      row('Net reversé', formatXof(s.netXof), bold: true),
                    ],
                  ),
                ),
                if (s.note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _Box(child: Text(s.note, style: t.bodyMedium)),
                ],
                const SizedBox(height: IviaSpacing.xl),
                Text(
                  'Commandes',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                _Box(
                  child: Column(
                    children: [
                      for (final l in s.lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.reference,
                                      style: t.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      'Livrée le ${_day(l.completedAt.toLocal())} · '
                                      'commission ${formatXof(l.commissionXof)}',
                                      style: t.bodySmall?.copyWith(
                                        color: IviaColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                formatXof(l.netXof),
                                style: t.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (s.lines.isEmpty) const Text('Aucune commande.'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

final _settlementProvider = FutureProvider.autoDispose
    .family<Settlement, String>(
      (ref, id) => ref.read(apiClientProvider).sellerSettlement(id),
    );

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.settled});
  final bool settled;

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: settled ? IviaColors.successSoft : IviaColors.warningSoft,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(
      settled ? Icons.check : Icons.schedule,
      color: settled ? IviaColors.success : IviaColors.warning,
    ),
  );
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _Box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: t.bodySmall?.copyWith(color: IviaColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: IviaColors.surface,
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    ),
  );
}
