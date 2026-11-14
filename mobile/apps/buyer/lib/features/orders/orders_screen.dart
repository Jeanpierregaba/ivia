import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import 'orders_providers.dart';

/// Onglet Commandes : en cours (et « Récemment ») / terminées.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  var _tab = 0;

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(myOrdersProvider.notifier).refresh();
    } catch (_) {
      showMessage(
        messenger,
        'Commandes non actualisées. Vérifiez votre connexion.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final orders = ref.watch(myOrdersViewProvider);
    final value = orders.value;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (_tab == 1 && n.depth == 0 && n.metrics.extentAfter < 400) {
              ref.read(myOrdersProvider.notifier).loadMore();
            }
            return false;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              IviaSpacing.screen,
              IviaSpacing.lg,
              IviaSpacing.screen,
              IviaSpacing.huge * 3,
            ),
            children: [
              Semantics(
                header: true,
                child: Text('Commandes', style: textTheme.headlineLarge),
              ),
              const SizedBox(height: IviaSpacing.lg),
              IviaSegmentedTabs(
                segments: [
                  IviaSegment(label: 'En cours', count: value?.active.length),
                  const IviaSegment(label: 'Terminées'),
                ],
                selected: _tab,
                onSelected: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: IviaSpacing.lg),
              ...switch (value) {
                final v? => _tab == 0 ? _active(v) : _finished(v),
                null when orders.hasError => [
                  _Message(
                    'Impossible de charger vos commandes. Vérifiez votre '
                    'connexion.',
                    action: OutlinedButton(
                      onPressed: () => ref.invalidate(myOrdersProvider),
                      child: const Text('Réessayer'),
                    ),
                  ),
                ],
                null => const [
                  Padding(
                    padding: EdgeInsets.all(IviaSpacing.screen),
                    child: IviaListSkeleton(),
                  ),
                ],
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _active(OrdersState state) {
    final active = state.active;
    final recent = state.finished.take(3).toList();
    return [
      if (active.isEmpty)
        _Message(
          'Aucune commande en cours.',
          action: FilledButton(
            onPressed: () => context.go(Routes.search),
            child: const Text('Découvrir les produits'),
          ),
        )
      else
        _OrderList(orders: active),
      if (recent.isNotEmpty) ...[
        const SizedBox(height: IviaSpacing.xl),
        Semantics(
          header: true,
          child: Text(
            // Capitales à l'affichage seulement : lu « Récemment ».
            'Récemment'.toUpperCase(),
            semanticsLabel: 'Récemment',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: IviaColors.textMuted, letterSpacing: 1.2),
          ),
        ),
        const SizedBox(height: IviaSpacing.sm),
        _OrderList(orders: recent),
      ],
    ];
  }

  List<Widget> _finished(OrdersState state) {
    final finished = state.finished;
    return [
      if (finished.isEmpty && state.nextOffset == null)
        const _Message('Aucune commande terminée.')
      else
        _OrderList(orders: finished),
      if (state.loadingMore)
        const Padding(
          padding: EdgeInsets.all(IviaSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (state.loadMoreFailed || state.nextOffset != null)
        Center(
          child: TextButton(
            onPressed: () => ref.read(myOrdersProvider.notifier).loadMore(),
            child: const Text('Afficher plus'),
          ),
        ),
    ];
  }
}

/// Commandes dans une carte blanche, séparées par un trait.
class _OrderList extends StatelessWidget {
  const _OrderList({required this.orders});

  final List<BuyerOrder> orders;

  @override
  Widget build(BuildContext context) => Material(
    color: IviaColors.surface,
    borderRadius: BorderRadius.circular(IviaRadius.large),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (final (i, order) in orders.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _OrderRow(order: order),
        ],
      ],
    ),
  );
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final BuyerOrder order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final detail = order.status.isActive
        ? '#${order.number} · ${fulfillmentLabel(order.fulfillment)} · '
              '${articles(order.articleCount)}'
        : '#${order.number} · ${shortDate(order.createdAt)}';
    final total = formatXof(order.totalXof);
    return Semantics(
      button: true,
      label:
          'Commande ${order.number}, ${order.shop.name}, $detail, $total, '
          '${statusLabel(order.status)}',
      excludeSemantics: true,
      onTap: () => context.push(Routes.order(order.id)),
      child: InkWell(
        onTap: () => context.push(Routes.order(order.id)),
        child: Padding(
          padding: const EdgeInsets.all(IviaSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 56,
                child: IviaNetworkImage(url: order.shop.logoUrl),
              ),
              const SizedBox(width: IviaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Total à droite du nom, ou dessous s'il manque de
                    // place (police agrandie).
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: IviaSpacing.sm,
                      children: [
                        Text(
                          order.shop.name,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          total,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Text(detail, style: textTheme.bodySmall),
                    const SizedBox(height: IviaSpacing.sm),
                    statusPill(order.status),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: IviaSpacing.xxl),
    child: Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: IviaColors.textSecondary),
        ),
        if (action case final a?) ...[
          const SizedBox(height: IviaSpacing.lg),
          a,
        ],
      ],
    ),
  );
}
