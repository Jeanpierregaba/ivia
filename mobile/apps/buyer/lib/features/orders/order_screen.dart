import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../cart/cart_actions.dart' show showCartMessage;
import '../shop/shop_screen.dart' show UnavailableView;
import 'order_labels.dart';
import 'orders_providers.dart';

/// Intervalle de relecture d'une commande en cours affichée.
const orderRefreshInterval = Duration(seconds: 20);

/// Suivi d'une commande : en-tête de l'étape, code de remise, boutique,
/// frise, articles. Relu toutes les 20 s tant qu'elle est en cours.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(orderRefreshInterval, (_) => _poll());
    _lifecycle = AppLifecycleListener(onResume: _poll);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  OrderController get _controller =>
      ref.read(orderProvider(widget.orderId).notifier);

  /// Relecture silencieuse d'une commande en cours ; une commande terminée
  /// n'est plus relue.
  void _poll() {
    final order = ref.read(orderProvider(widget.orderId)).value;
    if (order == null || !order.status.isActive) return;
    unawaited(_controller.refresh().catchError((Object _) {}));
  }

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _controller.refresh();
    } catch (_) {
      showCartMessage(
        messenger,
        'Commande non actualisée. Vérifiez votre connexion.',
      );
    }
  }

  void _pay() => showCartMessage(
    ScaffoldMessenger.of(context),
    'Le paiement arrive bientôt.',
  );

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (order) {
          AsyncValue(value: final value?) => _content(value),
          AsyncError(:final error) => UnavailableView(
            error: error,
            gone: 'Cette commande n’est plus disponible.',
            onRetry: () => ref.invalidate(orderProvider(widget.orderId)),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _content(BuyerOrder order) {
    final textTheme = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          IviaSpacing.screen,
          IviaSpacing.screen,
          IviaSpacing.screen,
          IviaSpacing.xxl,
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IviaBackButton(onPressed: () => context.pop()),
          ),
          const SizedBox(height: IviaSpacing.md),
          Semantics(
            header: true,
            child: Text(
              'Commande #${order.number}',
              style: textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: IviaSpacing.lg),
          _Header(order: order, onPay: _pay),
          const SizedBox(height: IviaSpacing.lg),
          _ShopTile(shop: order.shop),
          const SizedBox(height: IviaSpacing.lg),
          _Card(child: IviaTimeline(steps: timelineOf(order))),
          const SizedBox(height: IviaSpacing.lg),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${fulfillmentLabel(order.fulfillment)} · '
                  '${articles(order.articleCount)}',
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: IviaSpacing.sm),
                for (final item in order.items)
                  _AmountRow(
                    label: '${item.quantity} × ${item.name}',
                    amount: formatXof(item.lineTotalXof),
                  ),
                const Divider(height: IviaSpacing.xl),
                _AmountRow(
                  label: 'Total',
                  amount: formatXof(order.totalXof),
                  strong: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// En-tête de l'étape : en Cornell tant que la commande est en cours (texte
/// blanc lisible), vert une fois retirée, blanc pour une fin anormale.
class _Header extends StatelessWidget {
  const _Header({required this.order, required this.onPay});

  final BuyerOrder order;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final status = order.status;
    final shop = order.shop.name;
    final (String? kicker, String title, String? body) = switch (status) {
      OrderStatus.pendingPayment => (
        'En attente de paiement',
        'À payer avant ${timeOfDay(order.paymentDeadlineAt)}',
        'Sinon la commande est annulée et vos produits libérés.',
      ),
      OrderStatus.awaitingSeller => (
        'Paiement reçu',
        'En attente de la boutique',
        '$shop confirme votre commande.',
      ),
      OrderStatus.accepted => (
        'Acceptée par $shop',
        'Bientôt en préparation',
        null,
      ),
      OrderStatus.preparing => ('Acceptée par $shop', 'En préparation', null),
      OrderStatus.readyForPickup => (
        'Prête à retirer',
        'Chez $shop',
        [
          order.shop.addressText,
          order.shop.neighborhoodName,
        ].where((s) => s.isNotEmpty).join(', '),
      ),
      OrderStatus.completed => (
        null,
        'Retirée',
        switch (order.reachedAt(OrderStatus.completed)) {
          final at? => 'Le ${shortDate(at)} à ${timeOfDay(at)}. Merci !',
          null => null,
        },
      ),
      OrderStatus.expired => (
        null,
        'Paiement expiré',
        'La commande n’a pas été payée à temps : vos produits ont été libérés.',
      ),
      OrderStatus.cancelled => (
        null,
        'Annulée',
        order.cancelReason.isEmpty ? null : order.cancelReason,
      ),
      OrderStatus.refunded => (
        null,
        'Remboursée',
        'Le montant a été renvoyé sur votre compte Mobile Money.',
      ),
      _ => (null, statusLabel(status), null),
    };
    final (background, foreground) = switch (status) {
      OrderStatus.completed ||
      OrderStatus.delivered => (IviaColors.success, IviaColors.surface),
      _ when status.isActive => (IviaColors.primaryStrong, IviaColors.surface),
      _ => (IviaColors.surface, IviaColors.text),
    };
    final code = order.handoverCode;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(IviaSpacing.xl),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(IviaRadius.large),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kicker != null)
              Text(
                kicker,
                style: textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            Text(
              title,
              style: textTheme.headlineSmall?.copyWith(color: foreground),
            ),
            if (body != null && body.isNotEmpty) ...[
              const SizedBox(height: IviaSpacing.xs),
              Text(
                body,
                style: textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ],
            if (code != null) ...[
              const SizedBox(height: IviaSpacing.lg),
              Text(
                'Votre code de remise',
                style: textTheme.bodyMedium?.copyWith(color: foreground),
              ),
              const SizedBox(height: IviaSpacing.sm),
              IviaHandoverCode(code: code),
              const SizedBox(height: IviaSpacing.sm),
              Text(
                'Donnez-le à la boutique uniquement au retrait de vos '
                'produits.',
                style: textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ],
            if (status == OrderStatus.pendingPayment) ...[
              const SizedBox(height: IviaSpacing.lg),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: IviaColors.surface,
                  foregroundColor: IviaColors.primaryStrong,
                ),
                onPressed: onPay,
                child: Text('Payer ${formatXof(order.totalXof)}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Boutique de la commande : ouvre sa fiche.
class _ShopTile extends StatelessWidget {
  const _ShopTile({required this.shop});

  final PublicShop shop;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final address = [
      shop.addressText,
      shop.neighborhoodName,
    ].where((s) => s.isNotEmpty).join(', ');
    return Semantics(
      button: true,
      label: 'Boutique ${shop.name}, $address',
      excludeSemantics: true,
      onTap: () => context.push(Routes.shop(shop.id)),
      child: Material(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
        child: InkWell(
          borderRadius: BorderRadius.circular(IviaRadius.large),
          onTap: () => context.push(Routes.shop(shop.id)),
          child: Padding(
            padding: const EdgeInsets.all(IviaSpacing.md),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 48,
                  child: IviaNetworkImage(url: shop.logoUrl),
                ),
                const SizedBox(width: IviaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (address.isNotEmpty)
                        Text(address, style: textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: IviaColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(IviaSpacing.lg),
    decoration: BoxDecoration(
      color: IviaColors.surface,
      borderRadius: BorderRadius.circular(IviaRadius.large),
    ),
    child: child,
  );
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.strong = false,
  });

  final String label;
  final String amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = strong
        ? textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)
        : textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IviaSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: IviaSpacing.md),
          Text(amount, style: style?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
