import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../alerts/history_row.dart';

/// Onglet Commandes : en cours, puis terminées, dans le style de F21.
class OrdersTab extends ConsumerWidget {
  const OrdersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(ordersProvider);
    final orders = value.value ?? const <PharmacyOrder>[];
    final active = orders.where((o) => o.active).toList();
    final done = orders.where((o) => !o.active).toList();
    final error = errorOf(value);
    return RefreshIndicator(
      color: P.green,
      onRefresh: () async => ref.invalidate(ordersProvider),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(P.gutter, 16, P.gutter, 120),
        children: [
          Semantics(
            header: true,
            child: Text('Commandes', style: IviaTextStyles.display),
          ),
          const SizedBox(height: 4),
          if (error != null) ...[
            const SizedBox(height: 14),
            PErrorRetry(message: error),
          ] else if (orders.isEmpty) ...[
            const SizedBox(height: 14),
            const PEmpty(
              icon: Icons.inventory_2_outlined,
              text:
                  'Aucune commande pour le moment. Quand un client confirme '
                  'votre pharmacie, sa commande arrive ici.',
            ),
          ] else ...[
            if (active.isNotEmpty) ...[
              _Title('En cours'),
              _Card([for (final o in active) HistoryEntry.order(o)]),
            ],
            if (done.isNotEmpty) ...[
              _Title('Terminées'),
              _Card([for (final o in done) HistoryEntry.order(o)]),
            ],
          ],
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: PText.label.copyWith(
          fontSize: 13,
          letterSpacing: 1.2,
          color: P.muted,
        ),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card(this.entries);
  final List<HistoryEntry> entries;

  @override
  Widget build(BuildContext context) => PCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (i, e) in entries.indexed) ...[
          if (i > 0) const Divider(height: 1, color: P.line),
          HistoryRow(entry: e),
        ],
      ],
    ),
  );
}
