import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../home/home_tab.dart';
import 'alert_logic.dart';
import 'history_row.dart';

/// Onglet Alertes (F21) : en cours, commandes, historique groupé par jour.
class AlertsTab extends ConsumerStatefulWidget {
  const AlertsTab({super.key});

  @override
  ConsumerState<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends ConsumerState<AlertsTab> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    final inboxValue = ref.watch(inboxProvider);
    final ordersValue = ref.watch(ordersProvider);
    final inbox = inboxValue.value ?? const <InboxAlert>[];
    final orders = ordersValue.value ?? const <PharmacyOrder>[];
    final now = DateTime.now();
    final open = inbox.where((a) => isOpenAlert(a, now)).toList()
      ..sort((a, b) => a.searchEndsAt.compareTo(b.searchEndsAt));
    final active = orders.where((o) => o.active).toList();
    final history = [
      for (final a in inbox)
        if (!isOpenAlert(a, now)) HistoryEntry.alert(a),
      for (final o in orders)
        if (!o.active) HistoryEntry.order(o),
    ];
    final error = errorOf(_tab == 1 ? ordersValue : inboxValue);
    return RefreshIndicator(
      color: P.green,
      onRefresh: () async {
        ref
          ..invalidate(inboxProvider)
          ..invalidate(ordersProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(P.gutter, 16, P.gutter, 120),
        children: [
          Semantics(
            header: true,
            child: Text('Alertes', style: IviaTextStyles.display),
          ),
          const SizedBox(height: 16),
          IviaSegmentedTabs(
            segments: [
              IviaSegment(label: 'En cours · ${open.length}'),
              const IviaSegment(label: 'Commandes'),
              const IviaSegment(label: 'Historique'),
            ],
            selected: _tab,
            onSelected: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 4),
          if (error != null) ...[
            const SizedBox(height: 14),
            PErrorRetry(message: error),
          ] else
            ...switch (_tab) {
              0 => [
                const SizedBox(height: 14),
                if (open.isEmpty)
                  const PEmpty(
                    icon: Icons.notifications_none,
                    text:
                        'Aucune alerte en cours. Les nouvelles alertes '
                        'apparaissent ici en direct.',
                  ),
                for (final a in open)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AlertCard(alert: a),
                  ),
              ],
              1 => [
                if (active.isEmpty) ...[
                  const SizedBox(height: 14),
                  const PEmpty(
                    icon: Icons.inventory_2_outlined,
                    text: 'Aucune commande en cours.',
                  ),
                ] else
                  HistoryList(
                    entries: [for (final o in active) HistoryEntry.order(o)],
                  ),
              ],
              _ => [
                if (history.isEmpty) ...[
                  const SizedBox(height: 14),
                  const PEmpty(
                    icon: Icons.history,
                    text:
                        'Rien pour le moment : les alertes et commandes '
                        'terminées apparaîtront ici.',
                  ),
                ] else
                  HistoryList(entries: history),
              ],
            },
        ],
      ),
    );
  }
}
