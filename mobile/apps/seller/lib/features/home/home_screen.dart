import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/business_state.dart';
import '../../app/router.dart';
import '../../app/seller_shop.dart';
import '../business/biz_ui.dart';
import '../business/pro_ui.dart' show CountUp, PulseDot, Pro;
import '../catalog/catalog_providers.dart';
import '../orders/order_labels.dart';
import '../orders/orders_providers.dart';
import '../orders/reject_sheet.dart';

/// Accueil d'une boutique ou d'un restaurant (maquette B10) : chiffres du
/// jour, commandes payées à accepter (Accepter / Refuser sur place), état de
/// la préparation, stock bas, commandes en cours avec leur prochaine étape.
/// Rien d'inventé : tout vient des commandes et des produits lus.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(businessGateProvider).value?.opened;
    final shop = ref.watch(sellerShopProvider).value;
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
    final preparing = active.length - ready;
    final restaurant = space?.sector == 'restaurant';
    final low = ref.watch(lowStockProvider).value;

    return ColoredBox(
      color: Biz.page,
      child: RefreshIndicator(
        color: Biz.navy,
        onRefresh: () async {
          ref.invalidate(lowStockProvider);
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
          padding: EdgeInsets.zero,
          children: [
            _Header(
              name: space?.name ?? shop?.name ?? '',
              logoUrl: space?.logoUrl ?? shop?.logoUrl,
              online: space == null || space.status == 'active',
              place: shop?.neighborhoodName ?? '',
              sector: space?.sector,
              sales: sales,
              count: today.length,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (orders.hasError && orders.value == null)
                    const BizEmpty(
                      icon: Icons.cloud_off_rounded,
                      color: Biz.red,
                      title: 'Commandes indisponibles',
                      body: 'Tirez vers le bas pour réessayer.',
                    ),
                  for (final (i, o) in fresh.take(3).indexed)
                    BizReveal(
                      key: ValueKey('fresh-${o.id}'),
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _FreshOrder(
                          order: o,
                          now: ref.watch(apiClientProvider).now,
                        ),
                      ),
                    ),
                  if (fresh.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BizButton(
                        outlined: true,
                        color: Biz.red,
                        label: 'Voir les ${fresh.length} commandes à accepter',
                        onPressed: () =>
                            context.go(Routes.ordersTab(OrderTab.fresh)),
                      ),
                    ),
                  BizReveal(
                    index: 3,
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatTile(
                            value: preparing,
                            label: restaurant ? 'En cuisine' : 'En préparation',
                            color: Biz.blue,
                            onTap: () =>
                                context.go(Routes.ordersTab(OrderTab.active)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatTile(
                            value: ready,
                            label: ready > 1 ? 'Prêtes' : 'Prête',
                            color: IviaColors.cornellRed,
                            onTap: () =>
                                context.go(Routes.ordersTab(OrderTab.active)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatTile(
                            value: low?.length,
                            label: 'Stock bas',
                            color: Biz.amber,
                            onTap: () => context.go(Routes.catalog),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (fresh.isEmpty &&
                      active.isEmpty &&
                      !orders.isLoading &&
                      !orders.hasError)
                    const BizReveal(
                      index: 4,
                      child: BizEmpty(
                        icon: Icons.task_alt_rounded,
                        color: Biz.green,
                        title: 'Tout est à jour',
                        body:
                            'Les nouvelles commandes payées arrivent ici, '
                            'avec leur délai.',
                      ),
                    ),
                  if (active.isNotEmpty) ...[
                    _SectionTitle(
                      ready > 0
                          ? 'À traiter · $ready prête${ready > 1 ? 's' : ''}'
                          : 'À traiter',
                      action: 'Tout voir',
                      onAction: () =>
                          context.go(Routes.ordersTab(OrderTab.active)),
                    ),
                    for (final (i, o) in active.take(5).indexed)
                      BizReveal(
                        key: ValueKey('active-${o.id}'),
                        index: i + 4,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ActiveOrder(order: o),
                        ),
                      ),
                  ],
                  if (low != null && low.isNotEmpty) ...[
                    const _SectionTitle('À réapprovisionner'),
                    BizReveal(
                      index: 9,
                      child: SizedBox(
                        height: 132,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: low.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, i) =>
                              _LowStockCard(product: low[i]),
                        ),
                      ),
                    ),
                  ],
                  const _SectionTitle('Raccourcis'),
                  BizReveal(
                    index: 10,
                    child: BizButton(
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
          ],
        ),
      ),
    );
  }
}

/// En-tête bleu nuit arrondi : boutique, état, chiffres du jour.
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.logoUrl,
    required this.online,
    required this.place,
    required this.sector,
    required this.sales,
    required this.count,
  });
  final String name;
  final String? logoUrl;
  final bool online;
  final String place;
  final String? sector;
  final int sales, count;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kpiValue = t.headlineSmall?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w800,
    );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Biz.navy2, Biz.navy],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: logoUrl == null
                        ? Icon(Pro.icon(sector), color: Colors.white)
                        : Image.network(
                            logoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Icon(Pro.icon(sector), color: Colors.white),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Row(
                          children: [
                            PulseDot(
                              color: online
                                  ? const Color(0xFF3DD68C)
                                  : const Color(0xFFF5B942),
                              size: 6,
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                [
                                  online ? 'En ligne' : 'Validation en cours',
                                  if (place.isNotEmpty) place,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Grande police : la pastille du secteur laisse la place au nom.
                  if (MediaQuery.textScalerOf(context).scale(10) <= 13) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Pro.icon(sector), size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            switch (sector) {
                              'restaurant' => 'Restaurant',
                              _ => 'Boutique',
                            },
                            style: t.labelLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _Kpi(
                      label: 'Ventes du jour',
                      child: CountUp(
                        value: sales,
                        format: formatXof,
                        style: kpiValue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Kpi(
                      label: 'Commandes',
                      child: CountUp(
                        value: count,
                        format: (v) => '$v',
                        style: kpiValue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ],
    ),
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final int? value;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      button: true,
      label: '$label : ${value ?? 'inconnu'}',
      excludeSemantics: true,
      onTap: onTap,
      child: BizCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            value == null
                ? const BizSkeleton(width: 28, height: 26)
                : CountUp(
                    value: value!,
                    format: (v) => '$v',
                    style: t.headlineSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              style: t.bodySmall?.copyWith(color: Biz.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Biz.navy,
                ),
              ),
            ),
          ),
          if (action != null)
            Flexible(
              child: GestureDetector(
                onTap: onAction,
                child: Text(
                  action!,
                  textAlign: TextAlign.end,
                  style: t.labelLarge?.copyWith(
                    color: Biz.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Envoie une action sur une commande depuis l'Accueil ; la commande rendue
/// remplace l'ancienne dans la liste. Erreur : message.
Future<bool> _act(
  BuildContext context,
  WidgetRef ref,
  Future<SellerOrder> Function(IviaApiClient c) call, {
  required String done,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final list = ref.read(sellerOrdersProvider.notifier);
  try {
    final order = await call(ref.read(apiClientProvider));
    list.replace(order);
    showMessage(messenger, done);
    return true;
  } on ApiException catch (e) {
    showMessage(
      messenger,
      e.isNetwork ? 'Pas de connexion. Réessayez.' : e.message,
    );
    unawaited(list.refresh().catchError((Object _) {}));
  } on Exception {
    showMessage(messenger, 'Une erreur est survenue. Réessayez.');
  }
  return false;
}

/// Commande payée à accepter : le seul rouge de l'écran, délai bien visible,
/// Accepter et Refuser sur place.
class _FreshOrder extends ConsumerStatefulWidget {
  const _FreshOrder({required this.order, required this.now});
  final SellerOrder order;
  final DateTime Function() now;

  @override
  ConsumerState<_FreshOrder> createState() => _FreshOrderState();
}

class _FreshOrderState extends ConsumerState<_FreshOrder> {
  var _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _act(
      context,
      ref,
      (c) => c.acceptOrder(widget.order.id),
      done: 'Commande #${widget.order.number} acceptée',
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reject() async {
    if (_busy) return;
    final reason = await showRejectSheet(context);
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    await _act(
      context,
      ref,
      (c) => c.rejectOrder(widget.order.id, reason),
      done: 'Commande #${widget.order.number} refusée',
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = widget.order;
    final items = o.items
        .map((i) => i.quantity > 1 ? '${i.name} ×${i.quantity}' : i.name)
        .join(', ');
    return BizCard(
      border: Biz.red,
      onTap: () => context.go('${Routes.orders}/${o.id}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PulseDot(color: Biz.red, size: 7),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'NOUVELLE COMMANDE PAYÉE',
                  style: t.labelSmall?.copyWith(
                    color: Biz.red,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (o.sellerDeadlineAt case final deadline?)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: IviaColors.primarySoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 15,
                        color: Biz.red,
                      ),
                      const SizedBox(width: 4),
                      IviaCountdown(
                        deadline: deadline,
                        now: widget.now,
                        label: (v) => v,
                        style: t.labelLarge?.copyWith(
                          color: Biz.red,
                          fontWeight: FontWeight.w800,
                          fontFeatures: Biz.tabular,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
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
                    fontFeatures: Biz.tabular,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (items.isNotEmpty) items,
              o.fulfillment == Fulfillment.delivery
                  ? 'Livraison par un livreur ivia'
                  : 'Retrait sur place',
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: Biz.muted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: BizButton(
                  outlined: true,
                  color: Biz.navy,
                  height: 50,
                  label: 'Refuser',
                  onPressed: _busy ? null : _reject,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: BizButton(
                  color: Biz.red,
                  height: 50,
                  busy: _busy,
                  label: 'Accepter',
                  onPressed: _accept,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Commande en cours : prochaine étape en un geste (« Préparer », « Prête ? »).
class _ActiveOrder extends ConsumerStatefulWidget {
  const _ActiveOrder({required this.order});
  final SellerOrder order;

  @override
  ConsumerState<_ActiveOrder> createState() => _ActiveOrderState();
}

class _ActiveOrderState extends ConsumerState<_ActiveOrder> {
  var _busy = false;

  Future<void> _next() async {
    final o = widget.order;
    if (_busy) return;
    setState(() => _busy = true);
    await _act(
      context,
      ref,
      (c) => o.status == OrderStatus.accepted
          ? c.startPreparingOrder(o.id)
          : c.markOrderReady(o.id),
      done: o.status == OrderStatus.accepted
          ? 'Préparation de #${o.number} commencée'
          : 'Commande #${o.number} prête',
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = widget.order;
    final next = switch (o.status) {
      OrderStatus.accepted => 'Préparer',
      OrderStatus.preparing => 'Prête ?',
      _ => null,
    };
    final delivery = o.fulfillment == Fulfillment.delivery;
    return BizCard(
      onTap: () => context.go('${Routes.orders}/${o.id}'),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: IviaColors.secondarySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              delivery ? Icons.two_wheeler_rounded : Icons.inventory_2_outlined,
              color: Biz.navy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${o.number} · ${o.buyerFirstName}',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  [
                    sellerStatusLabel(o.status),
                    formatXof(o.subtotalXof),
                  ].join(' · '),
                  style: t.bodySmall?.copyWith(color: Biz.muted),
                ),
              ],
            ),
          ),
          if (next != null) ...[
            const SizedBox(width: 8),
            Semantics(
              container: true,
              button: true,
              label: '$next, commande ${o.number}',
              excludeSemantics: true,
              onTap: _busy ? null : _next,
              child: BizPressable(
                onTap: _busy ? null : _next,
                child: AnimatedContainer(
                  duration: Biz.fast,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Biz.page,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          next,
                          style: t.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Biz.navy,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  const _LowStockCard({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = product.stockQuantity ?? 0;
    final url = product.images.firstOrNull?.url;
    return SizedBox(
      width: 160,
      child: BizCard(
        onTap: () => context.push(Routes.productEdit(product.id)),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox.square(
                    dimension: 44,
                    child: url == null
                        ? const IviaImagePlaceholder()
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const IviaImagePlaceholder(),
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: BizBadge(
                      q <= 0 ? 'Épuisé' : 'Reste $q',
                      color: q <= 0 ? Biz.red : Biz.amber,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
