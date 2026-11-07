import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/business_state.dart';
import '../../app/router.dart';
import '../business/business_screens.dart';
import '../business/pro_ui.dart';
import '../orders/order_labels.dart';
import '../orders/orders_providers.dart';

/// Pilotage d'une boutique ou d'un restaurant : chiffres du jour, commandes à
/// accepter avec leur délai, travail en cours. Rien d'inventé : tout vient des
/// commandes lues.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final space = ref.watch(businessGateProvider).value?.opened;
    final orders = ref.watch(sellerOrdersProvider);
    final v = orders.value ?? SellerOrders.empty;
    final now = DateTime.now();
    final today = v.orders.where((o) {
      final at = (o.paidAt ?? o.createdAt).toLocal();
      return at.year == now.year &&
          at.month == now.month &&
          at.day == now.day &&
          o.paidAt != null &&
          o.status != OrderStatus.cancelled;
    }).toList();
    final sales = today.fold<int>(0, (a, o) => a + o.subtotalXof);
    final fresh = v.of(OrderTab.fresh);
    final active = v.of(OrderTab.active);
    final ready = active
        .where((o) => o.status == OrderStatus.readyForPickup)
        .length;
    final accent = Pro.accent(space?.sector);
    final restaurant = space?.sector == 'restaurant';
    return Column(
      children: [
        ProPanel(
          accent: accent,
          child: Column(
            children: [
              if (space != null) SpaceHeader(space: space),
              const SizedBox(height: 18),
              KpiStrip(
                items: [
                  Kpi('Ventes du jour', sales, formatXof),
                  Kpi('Commandes', today.length),
                  Kpi(restaurant ? 'En cuisine' : 'En cours', active.length),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              try {
                await ref.read(sellerOrdersProvider.notifier).refresh();
              } on ApiException {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Commandes non actualisées. Vérifiez votre connexion.',
                      ),
                    ),
                  );
                }
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (orders.hasError && orders.value == null)
                  ProEmpty(
                    icon: Icons.cloud_off_outlined,
                    title: 'Commandes indisponibles',
                    body: 'Tirez vers le bas pour réessayer.',
                  ),
                for (final (i, o) in fresh.take(3).indexed)
                  Reveal(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FreshOrder(
                        order: o,
                        now: ref.watch(apiClientProvider).now,
                      ),
                    ),
                  ),
                if (fresh.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ProButton(
                      outlined: true,
                      color: Pro.urgent,
                      label: 'Voir les ${fresh.length} commandes à accepter',
                      onPressed: () =>
                          context.go(Routes.ordersTab(OrderTab.fresh)),
                    ),
                  ),
                if (fresh.isEmpty &&
                    active.isEmpty &&
                    !orders.isLoading &&
                    !orders.hasError)
                  Reveal(
                    child: ProEmpty(
                      icon: Icons.task_alt_rounded,
                      title: 'Tout est à jour',
                      body: 'Les nouvelles commandes payées arrivent ici, avec leur délai.',
                    ),
                  ),
                if (active.isNotEmpty) ...[
                  ProSection(
                    ready > 0
                        ? 'À traiter · $ready prête${ready > 1 ? 's' : ''}'
                        : 'À traiter',
                    action: 'Tout voir',
                    onAction: () =>
                        context.go(Routes.ordersTab(OrderTab.active)),
                  ),
                  for (final (i, o) in active.take(5).indexed)
                    Reveal(
                      index: i + 1,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ProCard(
                          onTap: () => context.go('${Routes.orders}/${o.id}'),
                          child: Row(
                            children: [
                              Icon(
                                o.fulfillment == Fulfillment.delivery
                                    ? Icons.two_wheeler_rounded
                                    : Icons.storefront_outlined,
                                color: accent,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '#${o.number} · ${o.buyerFirstName}',
                                      style: t.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      sellerStatusLabel(o.status),
                                      style: t.bodySmall?.copyWith(
                                        color: Pro.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Souple : à 200 %, le montant passe à la ligne
                              // au lieu de déborder.
                              Flexible(
                                child: Text(
                                  formatXof(o.subtotalXof),
                                  textAlign: TextAlign.end,
                                  style: t.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: Pro.tabular,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
                const ProSection('Raccourcis'),
                Reveal(
                  index: 6,
                  child: ProButton(
                    outlined: true,
                    icon: restaurant
                        ? Icons.restaurant_menu_rounded
                        : Icons.inventory_2_outlined,
                    label: restaurant
                        ? 'Gérer mon menu'
                        : 'Gérer mon catalogue',
                    onPressed: () => context.go(Routes.catalog),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Commande payée à accepter : seul le rouge de l'écran, le délai bien visible.
class _FreshOrder extends StatelessWidget {
  const _FreshOrder({required this.order, required this.now});
  final SellerOrder order;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = order;
    return ProCard(
      border: Pro.urgent,
      onTap: () => context.go('${Routes.orders}/${o.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulseDot(color: Pro.urgent, size: 7),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'NOUVELLE COMMANDE PAYÉE',
                  style: t.labelSmall?.copyWith(
                    color: Pro.urgent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (o.sellerDeadlineAt case final deadline?)
                IviaCountdown(
                  deadline: deadline,
                  now: now,
                  label: (v) => v,
                  style: t.labelLarge?.copyWith(
                    color: Pro.urgent,
                    fontWeight: FontWeight.w800,
                    fontFeatures: Pro.tabular,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${o.number} · ${o.buyerFirstName}',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  formatXof(o.subtotalXof),
                  textAlign: TextAlign.end,
                  style: t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: Pro.tabular,
                  ),
                ),
              ),
            ],
          ),
          Text(
            o.fulfillment == Fulfillment.delivery
                ? 'Livraison par un livreur ivia'
                : 'Retrait sur place',
            style: t.bodySmall?.copyWith(color: Pro.muted),
          ),
          const SizedBox(height: 12),
          ProButton(
            color: Pro.urgent,
            label: 'Examiner et accepter',
            onPressed: () => context.go('${Routes.orders}/${o.id}'),
          ),
        ],
      ),
    );
  }
}
