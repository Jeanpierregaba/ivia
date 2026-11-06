import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';

class BalanceTab extends ConsumerWidget {
  const BalanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final e = ref.watch(earningsProvider).value;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(earningsProvider),
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          const PTitle('Mon ', 'solde'),
          const SizedBox(height: 14),
          PCard(
            color: P.navy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'À recevoir d\'ivia',
                  style: t.bodyMedium?.copyWith(color: Colors.white70),
                ),
                Text(
                  formatXof(e?.balanceXof ?? 0),
                  style: t.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Ventes livrées payées dans l\'app, sans commission.',
                  style: t.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Num(
                  label: 'Livrées',
                  value: '${e?.deliveredCount ?? 0}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Num(label: 'Retraits', value: '${e?.pickupCount ?? 0}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Num(
                  label: 'Déjà versé',
                  value: formatXof(e?.paidOutXof ?? 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Reversements',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (e == null || e.payouts.isEmpty)
            PCard(
              child: Text(
                'Aucun reversement pour l\'instant.',
                style: t.bodyMedium,
              ),
            ),
          for (final p
              in e?.payouts ??
                  const <({int amountXof, String reference, DateTime at})>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PCard(
                child: Row(
                  children: [
                    const PIcon(Icons.payments_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${p.at.toLocal().day}/${p.at.toLocal().month} · ${p.reference}',
                        style: t.titleSmall,
                      ),
                    ),
                    Text(
                      '+${formatXof(p.amountXof)}',
                      style: t.titleMedium?.copyWith(
                        color: P.green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return PCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(label, style: t.bodySmall?.copyWith(color: P.muted)),
        ],
      ),
    );
  }
}
