import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import 'order_screen.dart';

class OrdersTab extends ConsumerWidget {
  const OrdersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final items = ref.watch(ordersProvider).value ?? const <PharmacyOrder>[];
    final active = items.where((o) => o.active).toList();
    final done = items.where((o) => !o.active).toList();
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(ordersProvider),
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          const PTitle('Réservations ', 'à préparer'),
          const SizedBox(height: 12),
          if (active.isEmpty)
            PCard(
              child: Text('Aucune réservation en cours.', style: t.bodyMedium),
            ),
          for (final o in active)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OrderTile(order: o),
            ),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Terminées',
              style: t.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: P.muted,
              ),
            ),
            const SizedBox(height: 8),
            for (final o in done.take(20))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OrderTile(order: o),
              ),
          ],
        ],
      ),
    );
  }
}

String orderStatusLabel(PharmacyOrder o) => switch (o.status) {
  'reserved' when o.preparedAt != null => 'Prête · client attendu',
  'reserved' => 'À préparer',
  'courier_search' => 'Recherche d\'un livreur',
  'awaiting_payment' => 'Livreur trouvé · paiement du client',
  'courier_assigned' => 'Livreur en route vers vous',
  'picked_up' => 'Récupérée par le livreur',
  'completed' => 'Remise',
  'expired' => 'Expirée',
  'cancelled' => 'Annulée',
  _ => o.status,
};

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});
  final PharmacyOrder order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = order;
    return PCard(
      border: o.status == 'reserved' && o.preparedAt == null ? P.green : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => OrderScreen(orderId: o.id)),
      ),
      child: Row(
        children: [
          PIcon(o.delivery ? Icons.delivery_dining : Icons.storefront_outlined),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${o.number} · ${o.buyerFirstName.isEmpty ? 'Patient' : o.buyerFirstName}',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${o.delivery ? 'Livraison ivia' : 'Retrait sur place'} · ${formatXof(o.itemsXof)}',
                  style: t.bodySmall?.copyWith(color: P.muted),
                ),
                const SizedBox(height: 6),
                PPill(orderStatusLabel(o)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: P.muted),
        ],
      ),
    );
  }
}
