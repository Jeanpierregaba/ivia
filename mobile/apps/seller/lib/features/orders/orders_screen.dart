import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../business/biz_ui.dart';
import 'order_labels.dart';
import 'orders_providers.dart';

/// Onglet Commandes : Nouvelles (à accepter, la plus urgente en haut), En
/// cours, Terminées. Relu par le cadre toutes les 30 s ; tirer vers le bas
/// actualise.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key, this.tab = OrderTab.fresh});

  /// Onglet ouvert (paramètre `tab` de l'URL, depuis l'Accueil).
  final OrderTab tab;

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  var _loadingMore = false;

  /// Onglet affiché : celui de l'URL, seule source (l'Accueil y mène, un
  /// appui sur un onglet la change).
  OrderTab get _tab => widget.tab;

  void _select(OrderTab tab) {
    if (tab != _tab) context.go(Routes.ordersTab(tab));
  }

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(sellerOrdersProvider.notifier).refresh();
    } catch (_) {
      showMessage(
        messenger,
        'Commandes non actualisées. Vérifiez votre connexion.',
      );
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final messenger = ScaffoldMessenger.of(context);
    final orders = ref.read(sellerOrdersProvider.notifier);
    setState(() => _loadingMore = true);
    try {
      await orders.loadMore();
    } catch (_) {
      showMessage(
        messenger,
        'Commandes non chargées. Vérifiez votre connexion.',
      );
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(sellerOrdersProvider);
    final value = orders.value;
    final fresh = value?.count(OrderTab.fresh) ?? 0;
    final active = value?.count(OrderTab.active) ?? 0;
    return ColoredBox(
      color: Biz.page,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: Biz.navy,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              IviaSpacing.screen,
              IviaSpacing.lg,
              IviaSpacing.screen,
              IviaSpacing.huge * 3,
            ),
            children: [
              BizHeader(
                title: 'Commandes',
                subtitle: value == null
                    ? null
                    : [
                        if (fresh > 0)
                          fresh == 1 ? '1 à accepter' : '$fresh à accepter',
                        if (active > 0) '$active à suivre',
                        if (fresh == 0 && active == 0) 'Rien à traiter',
                      ].join(' · '),
              ),
              const SizedBox(height: IviaSpacing.lg),
              // Trois onglets : à la ligne plutôt que hors de l'écran.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tab in OrderTab.values)
                    BizFilterChip(
                      label: tab.label,
                      count: tab == OrderTab.done ? null : value?.count(tab),
                      active: tab == _tab,
                      onTap: () => _select(tab),
                    ),
                ],
              ),
              const SizedBox(height: IviaSpacing.lg),
              ...switch (value) {
                final v? => _list(v),
                null when orders.hasError => [
                  _Message(
                    'Impossible de charger les commandes. Vérifiez votre '
                    'connexion.',
                    action: OutlinedButton(
                      onPressed: () => ref.invalidate(sellerOrdersProvider),
                      child: const Text('Réessayer'),
                    ),
                  ),
                ],
                null => [
                  for (var i = 0; i < 4; i++)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: BizCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BizSkeleton(width: 140, height: 18),
                            SizedBox(height: 10),
                            BizSkeleton(height: 14),
                            SizedBox(height: 10),
                            BizSkeleton(width: 90, height: 22, radius: 11),
                          ],
                        ),
                      ),
                    ),
                ],
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _list(SellerOrders state) {
    final list = state.of(_tab);
    final more = _tab == OrderTab.done && state.nextOffset != null;
    return [
      if (list.isEmpty && !more)
        _Message(switch (_tab) {
          OrderTab.fresh => 'Aucune nouvelle commande.',
          OrderTab.active => 'Aucune commande en cours.',
          OrderTab.done => 'Aucune commande terminée.',
        })
      else if (list.isNotEmpty)
        _OrderList(orders: list),
      if (_tab == OrderTab.done)
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.all(IviaSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (more)
          Center(
            child: TextButton(
              onPressed: _loadMore,
              child: const Text('Afficher plus'),
            ),
          ),
    ];
  }
}

/// Commandes en cartes arrondies qui apparaissent en cascade.
class _OrderList extends StatelessWidget {
  const _OrderList({required this.orders});

  final List<SellerOrder> orders;

  @override
  Widget build(BuildContext context) => Column(
    // Cartes sur toute la largeur (montant à droite).
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, order) in orders.indexed)
        Padding(
          key: ValueKey(order.id),
          padding: const EdgeInsets.only(bottom: 10),
          child: BizReveal(
            index: i % 10,
            child: OrderRow(order: order),
          ),
        ),
    ],
  );
}

/// Ligne d'une commande : « #1042 · Koffi », mode et articles (ou date pour
/// une terminée), montant des produits, statut ; compte à rebours pour une
/// nouvelle.
class OrderRow extends ConsumerWidget {
  const OrderRow({super.key, required this.order});

  final SellerOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final client = ref.watch(apiClientProvider);
    final done = tabOf(order.status) == OrderTab.done;
    final title = order.buyerFirstName.isEmpty
        ? '#${order.number}'
        : '#${order.number} · ${order.buyerFirstName}';
    final finishedAt = order.completedAt ?? order.updatedAt;
    final day = shortDate(finishedAt, now: client.now());
    // Aujourd'hui et hier : avec l'heure ; plus ancien : la date seule.
    final when = day == "aujourd'hui" || day == 'hier'
        ? '${_capitalized(day)} ${timeOfDay(finishedAt)}'
        : day;
    final kind =
        '${fulfillmentLabel(order.fulfillment)} · '
        '${articles(order.articleCount)}';
    final detail = done ? '$kind · $when' : kind;
    final amount = formatXof(order.subtotalXof);
    final label = sellerStatusLabel(order.status);
    final deadline = order.status == OrderStatus.awaitingSeller
        ? order.sellerDeadlineAt
        : null;
    void open() => context.push(Routes.order(order.id));
    return Semantics(
      button: true,
      label: [
        'Commande ${order.number}',
        if (order.buyerFirstName.isNotEmpty) order.buyerFirstName,
        detail,
        amount,
        label,
      ].join(', '),
      onTap: open,
      child: BizCard(
        onTap: open,
        // Nouvelle commande : filet rouge, comme sur l'Accueil.
        border: deadline != null ? Biz.red : null,
        padding: const EdgeInsets.all(IviaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Montant à droite du titre, ou dessous s'il manque de place
            // (police agrandie).
            ExcludeSemantics(
              // Sans largeur imposée, spaceBetween n'écarterait rien.
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: IviaSpacing.sm,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      amount,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: IviaSpacing.xs),
            ExcludeSemantics(
              child: Text(
                detail,
                style: textTheme.bodyMedium?.copyWith(
                  color: IviaColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: IviaSpacing.sm),
            Wrap(
              spacing: IviaSpacing.md,
              runSpacing: IviaSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ExcludeSemantics(child: statusPill(order.status, label: label)),
                if (deadline != null)
                  IviaCountdown(
                    deadline: deadline,
                    now: client.now,
                    style: textTheme.titleSmall,
                    // Délai passé : la commande est relue (annulée par le
                    // serveur).
                    onExpired: () => ref
                        .read(sellerOrdersProvider.notifier)
                        .poll()
                        .catchError((Object _) {}),
                  ),
              ],
            ),
          ],
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
  Widget build(BuildContext context) => BizEmpty(
    icon: action == null
        ? Icons.receipt_long_outlined
        : Icons.cloud_off_rounded,
    color: action == null ? Biz.blue : Biz.red,
    title: text,
    action: action,
  );
}

/// « Aujourd'hui » en début de ligne.
String _capitalized(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
