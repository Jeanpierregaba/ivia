import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/cart.dart';
import '../../app/router.dart';
import 'cart_actions.dart';
import 'cart_button.dart' show articlesLabel;

/// Panier : boutique, lignes et quantités, sous-total, « Commander ».
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  @override
  void initState() {
    super.initState();
    // Prix et stock du moment à l'ouverture ; un échec garde le panier
    // connu (tirer vers le bas le signale).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(cartProvider.notifier).refresh().catchError((Object _) {}),
        );
      }
    });
  }

  CartController get _controller => ref.read(cartProvider.notifier);

  ScaffoldMessengerState get _messenger => ScaffoldMessenger.of(context);

  Future<void> _refresh() async {
    final messenger = _messenger;
    try {
      await _controller.refresh();
    } catch (_) {
      showCartMessage(
        messenger,
        'Panier non actualisé. Vérifiez votre connexion.',
      );
    }
  }

  Future<void> _clear(Cart cart) async {
    final controller = _controller;
    final messenger = _messenger;
    final confirmed = await showClearCartSheet(
      context,
      shopName: cart.shop?.name,
      adding: false,
    );
    if (!confirmed) return;
    try {
      await controller.clear();
    } catch (e) {
      showCartMessage(messenger, cartErrorMessage(e));
    }
  }

  void _change(CartItem item, int quantity, {int? undoTo}) => unawaited(
    setCartLine(_controller, _messenger, item, quantity, undoTo: undoTo),
  );

  void _order() => context.push(Routes.checkout);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cartViewProvider);
    final value = state.value;
    final cart = value?.cart;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IviaSpacing.screen,
                IviaSpacing.screen,
                IviaSpacing.sm,
                IviaSpacing.sm,
              ),
              child: Row(
                children: [
                  IviaBackButton(onPressed: () => context.pop()),
                  const Spacer(),
                  if (cart != null && !cart.isEmpty)
                    TextButton(
                      onPressed: value!.clearing ? null : () => _clear(cart),
                      child: const Text('Vider'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: IviaSpacing.screen,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  'Panier',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            Expanded(
              child: switch (value) {
                final v? when _visible(v).isEmpty => _Empty(
                  onRefresh: _refresh,
                ),
                final v? => _content(v),
                null when state.hasError => _LoadError(
                  onRetry: () => ref.invalidate(cartProvider),
                ),
                null => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: switch (value) {
        final v? when _visible(v).isNotEmpty => _Summary(
          state: v,
          onOrder: _order,
        ),
        _ => null,
      },
    );
  }

  /// Lignes affichées : celles qui ne sont pas en cours de retrait.
  static List<CartItem> _visible(CartState state) => [
    for (final item in state.cart.items)
      if (state.quantityOf(item.productId) > 0) item,
  ];

  Widget _content(CartState state) {
    final textTheme = Theme.of(context).textTheme;
    final cart = state.cart;
    final shop = cart.shop;
    final items = _visible(state);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          IviaSpacing.screen,
          IviaSpacing.sm,
          IviaSpacing.screen,
          IviaSpacing.xxl,
        ),
        children: [
          if (shop != null) ...[
            _ShopTile(shop: shop),
            if (!shop.acceptingOrders) ...[
              const SizedBox(height: IviaSpacing.md),
              _Warning(
                '${shop.name} ne prend pas de commandes pour l’instant.',
              ),
            ],
          ] else
            const _Warning('Cette boutique n’est plus disponible.'),
          const SizedBox(height: IviaSpacing.lg),
          DecoratedBox(
            decoration: BoxDecoration(
              color: IviaColors.surface,
              borderRadius: BorderRadius.circular(IviaRadius.large),
            ),
            child: Column(
              children: [
                for (final (i, item) in items.indexed)
                  _CartLine(
                    key: ValueKey(item.productId),
                    item: item,
                    quantity: state.quantityOf(item.productId),
                    last: i == items.length - 1,
                    enabled: !state.clearing,
                    // « Annuler » remet la quantité enregistrée avant le
                    // retrait (la ligne revient en fin de liste : le serveur
                    // range les lignes par date d'ajout).
                    onChanged: (q) => _change(
                      item,
                      q,
                      undoTo: q == 0
                          ? state.cart.quantityOf(item.productId).clamp(1, 99)
                          : null,
                    ),
                    onRemove: () => _change(item, 0),
                    onAdjust: (q) => _change(item, q),
                  ),
              ],
            ),
          ),
          if (cart.items.any((i) => i.hasIssue)) ...[
            const SizedBox(height: IviaSpacing.md),
            Text(
              'Corrigez les produits signalés pour commander.',
              style: textTheme.bodyMedium?.copyWith(
                color: IviaColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: IviaSpacing.md),
          Text(
            'Frais de livraison calculés à l’étape suivante.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: IviaSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline,
                size: 20,
                color: IviaColors.textSecondary,
              ),
              const SizedBox(width: IviaSpacing.sm),
              Expanded(
                child: Text(
                  'Un panier contient les produits d’une seule boutique. '
                  'Ajouter un produit d’une autre boutique vous proposera de '
                  'vider ce panier.',
                  style: textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nouvelle quantité d'une ligne ; 0 la retire, avec « Annuler » qui remet
/// [undoTo]. Hors de l'écran : « Annuler » marche encore après un retour.
Future<void> setCartLine(
  CartController controller,
  ScaffoldMessengerState messenger,
  CartItem item,
  int quantity, {
  int? undoTo,
}) async {
  try {
    await controller.setQuantity(item.productId, quantity);
  } catch (e) {
    showCartMessage(messenger, cartErrorMessage(e));
    return;
  }
  if (quantity != 0) return;
  showCartMessage(
    messenger,
    '${item.name} retiré du panier',
    action: undoTo == null
        ? null
        : SnackBarAction(
            label: 'Annuler',
            onPressed: () => setCartLine(controller, messenger, item, undoTo),
          ),
  );
}

/// Boutique du panier : ouvre sa fiche.
class _ShopTile extends StatelessWidget {
  const _ShopTile({required this.shop});

  final PublicShop shop;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Boutique ${shop.name}, ${shop.neighborhoodName}',
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
                      if (shop.neighborhoodName.isNotEmpty)
                        Text(shop.neighborhoodName, style: textTheme.bodySmall),
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

/// Avertissement qui empêche de commander.
class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(IviaSpacing.md),
    decoration: BoxDecoration(
      color: IviaColors.surface,
      borderRadius: BorderRadius.circular(IviaRadius.large),
      border: Border.all(color: IviaColors.error),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: IviaColors.error, fontWeight: FontWeight.w700),
    ),
  );
}

/// Ligne du panier : photo, nom, prix, quantité ; en erreur, la raison et
/// « Retirer » ou « Ajuster ».
class _CartLine extends StatelessWidget {
  const _CartLine({
    super.key,
    required this.item,
    required this.quantity,
    required this.last,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
    required this.onAdjust,
  });

  final CartItem item;
  final int quantity;
  final bool last;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final VoidCallback onRemove;
  final ValueChanged<int> onAdjust;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final left = item.stockLeft;
    final canAdjust = left != null && left > 0 && left < item.quantity;
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: IviaColors.border)),
      ),
      padding: const EdgeInsets.all(IviaSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 64,
            child: IviaNetworkImage(url: item.imageUrl),
          ),
          const SizedBox(width: IviaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  formatXof(item.unitPriceXof),
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: IviaSpacing.xs),
                if (item.hasIssue) ...[
                  Text(
                    left == 0 ? 'Épuisé pour l’instant.' : item.issue,
                    style: textTheme.bodyMedium?.copyWith(
                      color: IviaColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Wrap(
                    spacing: IviaSpacing.sm,
                    children: [
                      TextButton(
                        onPressed: enabled ? onRemove : null,
                        child: Text(
                          'Retirer',
                          semanticsLabel: 'Retirer ${item.name} du panier',
                        ),
                      ),
                      if (canAdjust)
                        TextButton(
                          onPressed: enabled ? () => onAdjust(left) : null,
                          child: Text(
                            'Ajuster à $left',
                            semanticsLabel: 'Ajuster ${item.name} à $left',
                          ),
                        ),
                    ],
                  ),
                ] else
                  IviaQuantityStepper(
                    label: 'Quantité de ${item.name}',
                    value: quantity,
                    max: cartMaxQuantity,
                    editable: false,
                    enabled: enabled,
                    addLabel: 'Ajouter un ${item.name}',
                    minusLabel: 'Retirer un ${item.name}',
                    removeLabel: 'Retirer ${item.name} du panier',
                    onChanged: onChanged,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre du bas : sous-total et « Commander ».
class _Summary extends StatelessWidget {
  const _Summary({required this.state, required this.onOrder});

  final CartState state;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cart = state.cart;
    // Les lignes en erreur ne comptent pas dans le sous-total.
    final articles = cart.items
        .where((i) => !i.hasIssue)
        .fold(0, (n, i) => n + i.quantity);
    final sending = state.pending.isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(IviaRadius.large),
        ),
        boxShadow: IviaShadows.sheet,
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          IviaSpacing.screen,
          IviaSpacing.md,
          IviaSpacing.screen,
          IviaSpacing.screen,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: IviaSpacing.md,
                children: [
                  Text(
                    'Sous-total · ${articlesLabel(articles)}',
                    style: textTheme.bodyLarge,
                  ),
                  Text(
                    formatXof(cart.subtotalXof),
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: IviaSpacing.sm),
            FilledButton(
              onPressed: cart.orderable && !sending && !state.clearing
                  ? onOrder
                  : null,
              child: const Text('Commander'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(IviaSpacing.xxl),
        children: [
          const SizedBox(height: IviaSpacing.xxl),
          Icon(
            Icons.shopping_bag_outlined,
            size: 64,
            color: IviaAppBrand.of(context).accent,
          ),
          const SizedBox(height: IviaSpacing.lg),
          Text(
            'Votre panier est vide.',
            textAlign: TextAlign.center,
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: IviaSpacing.sm),
          Text(
            'Ajoutez des produits depuis une boutique ou la recherche.',
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(
              color: IviaColors.textSecondary,
            ),
          ),
          const SizedBox(height: IviaSpacing.xl),
          Center(
            child: FilledButton(
              onPressed: () => context.go(Routes.search),
              child: const Text('Découvrir les produits'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(IviaSpacing.xxl),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Impossible de charger le panier. Vérifiez votre connexion.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: IviaSpacing.lg),
        OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    ),
  );
}
