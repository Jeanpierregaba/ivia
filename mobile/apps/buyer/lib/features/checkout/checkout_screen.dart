import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/cart.dart';
import '../../app/router.dart';
import '../orders/order_parts.dart';
import '../orders/orders_providers.dart';
import '../shop/shop_screen.dart' show publicShopProvider;

/// Récapitulatif du retrait, calculé par le serveur à l'ouverture.
final checkoutQuoteProvider = FutureProvider.autoDispose<OrderQuote>(
  (ref) => ref.read(apiClientProvider).quoteOrder(),
  retry: (_, _) => null,
);

/// Refus qui viennent du panier : « Revenir au panier » le relit.
const _cartRefusals = {
  'cart_empty',
  'shop_unavailable',
  'shop_closed',
  'product_unavailable',
  'insufficient_stock',
};

/// Commande : mode de remise, boutique, récapitulatif, « Payer ».
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  /// Identifiant de cette commande, renvoyé à chaque essai : le serveur
  /// rend la même commande au lieu d'en créer une seconde.
  final _requestId = newRequestId();
  var _placing = false;

  /// Issue inconnue (réseau coupé, réponse inattendue) : la commande a pu
  /// être créée et le panier vidé. Le panier est relu à la sortie de
  /// l'écran, pour ne jamais recommander un panier périmé.
  var _uncertain = false;

  late final CartController _cart = ref.read(cartProvider.notifier);
  late final ProviderContainer _container = ProviderScope.containerOf(
    context,
    listen: false,
  );

  @override
  void initState() {
    super.initState();
    // Lus ici : ils servent encore après la fermeture de l'écran.
    _cart;
    _container;
  }

  @override
  void dispose() {
    if (_uncertain) _refreshCart();
    super.dispose();
  }

  void _refreshCart() => unawaited(_cart.refresh().catchError((Object _) {}));

  /// « Revenir au panier » : panier relu ; l'écran se ferme s'il est encore
  /// ouvert, sinon le panier s'ouvre.
  void _backToCart(GoRouter router) {
    _refreshCart();
    if (mounted) {
      context.pop();
    } else if (router.state.matchedLocation != Routes.cart) {
      router.push(Routes.cart);
    }
  }

  Future<void> _pay() async {
    final client = ref.read(apiClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _placing = true);
    try {
      BuyerOrder order;
      try {
        order = await client.createOrder(clientRequestId: _requestId);
      } on ApiException catch (e) {
        // Même requête encore en cours de création : elle est rendue
        // au nouvel essai.
        if (e.code != 'duplicate_request') rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
        order = await client.createOrder(clientRequestId: _requestId);
      }
      _uncertain = false;
      // Même si l'écran a été quitté : panier vidé par le serveur, liste
      // des commandes à jour.
      _refreshCart();
      if (_container.exists(myOrdersProvider)) {
        _container.read(myOrdersProvider.notifier).put(order);
      }
      // Paiement au-dessus du suivi : le retour mène à la commande, qui
      // reste à payer jusqu'à l'heure limite.
      if (mounted) {
        router.go(Routes.pay(order.id));
      } else {
        showMessage(
          messenger,
          'Commande #${order.number} passée.',
          action: SnackBarAction(
            label: 'Payer',
            onPressed: () => router.go(Routes.pay(order.id)),
          ),
        );
      }
    } on ApiException catch (e) {
      if (e.isNetwork) _uncertain = true;
      showMessage(
        messenger,
        e.code == 'shop_closed'
            ? 'Cette boutique ne prend pas de commandes pour l’instant.'
            : e.message,
        action: _cartRefusals.contains(e.code)
            ? SnackBarAction(
                label: 'Revenir au panier',
                onPressed: () => _backToCart(router),
              )
            : null,
      );
    } catch (_) {
      _uncertain = true;
      showMessage(messenger, const ApiException.unknown().message);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = ref.watch(checkoutQuoteProvider);
    final textTheme = Theme.of(context).textTheme;
    // Pas de retour pendant l'envoi : l'issue de « Payer » doit être connue.
    return PopScope(
      canPop: !_placing,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              IviaSpacing.screen,
              IviaSpacing.screen,
              IviaSpacing.screen,
              IviaSpacing.xxl,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IviaBackButton(
                  onPressed: _placing ? null : () => context.pop(),
                ),
              ),
              const SizedBox(height: IviaSpacing.md),
              Semantics(
                header: true,
                child: Text('Commande', style: textTheme.headlineSmall),
              ),
              const SizedBox(height: IviaSpacing.lg),
              ...switch (quote) {
                AsyncData(:final value) => _content(value),
                AsyncError(:final error) => [
                  _QuoteError(
                    error: error,
                    onRetry: () => ref.invalidate(checkoutQuoteProvider),
                    onBack: () => _backToCart(GoRouter.of(context)),
                  ),
                ],
                _ => const [
                  Padding(
                    padding: EdgeInsets.all(IviaSpacing.xxl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              },
            ],
          ),
        ),
        bottomNavigationBar: switch (quote) {
          AsyncData(:final value) => SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(
              IviaSpacing.screen,
              IviaSpacing.sm,
              IviaSpacing.screen,
              IviaSpacing.screen,
            ),
            child: FilledButton(
              onPressed: _placing ? null : _pay,
              child: _placing
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Commande en cours',
                      ),
                    )
                  : Text('Payer ${formatXof(value.totalXof)}'),
            ),
          ),
          _ => null,
        },
      ),
    );
  }

  List<Widget> _content(OrderQuote quote) {
    final textTheme = Theme.of(context).textTheme;
    final shop = ref.watch(publicShopProvider(quote.shopId)).value;
    final place = shop == null || shop.neighborhoodName.isEmpty
        ? 'en boutique'
        : 'en boutique à ${shop.neighborhoodName}';
    final stacked =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final modes = [
      const _ModeCard(
        title: 'Livraison',
        body: 'Un livreur ivia vous apporte la commande',
        selected: false,
        soon: true,
      ),
      _ModeCard(title: 'Retrait', body: 'Gratuit, $place', selected: true),
    ];
    return [
      Semantics(
        container: true,
        label: 'Mode de remise',
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  modes[0],
                  const SizedBox(height: IviaSpacing.md),
                  modes[1],
                ],
              )
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: modes[0]),
                    const SizedBox(width: IviaSpacing.md),
                    Expanded(child: modes[1]),
                  ],
                ),
              ),
      ),
      const SizedBox(height: IviaSpacing.lg),
      if (shop != null) ...[
        OrderCard(
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
                      'Retrait chez ${shop.name}',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        shop.addressText,
                        shop.neighborhoodName,
                      ].where((s) => s.isNotEmpty).join(', '),
                      style: textTheme.bodySmall,
                    ),
                    const SizedBox(height: IviaSpacing.xs),
                    Text(
                      'Vous retirez la commande ici, avec votre code.',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: IviaSpacing.lg),
      ],
      OrderCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in quote.items)
              IviaAmountRow(
                label: '${item.quantity} × ${item.name}',
                amount: formatXof(item.lineTotalXof),
              ),
            const Divider(height: IviaSpacing.xl),
            IviaAmountRow(
              label: 'Produits · ${articles(quote.articleCount)}',
              amount: formatXof(quote.subtotalXof),
            ),
            IviaAmountRow(label: 'Retrait en boutique', amount: 'Gratuit'),
            const SizedBox(height: IviaSpacing.sm),
            IviaAmountRow(
              label: 'Total',
              amount: formatXof(quote.totalXof),
              strong: true,
            ),
          ],
        ),
      ),
      const SizedBox(height: IviaSpacing.lg),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.timer_outlined,
            size: 20,
            color: IviaColors.textSecondary,
          ),
          const SizedBox(width: IviaSpacing.sm),
          Expanded(
            child: Text(
              'Vos produits sont réservés ${quote.paymentTimeout.inMinutes} '
              'minutes, le temps de payer.',
              style: textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ];
  }
}

/// Mode de remise : titre, rond de sélection, description ; « Bientôt »
/// pour un mode pas encore ouvert.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.body,
    required this.selected,
    this.soon = false,
  });

  final String title;
  final String body;
  final bool selected;
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: !soon,
      label: [title, body, if (soon) 'bientôt disponible'].join(', '),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(IviaSpacing.lg),
        decoration: BoxDecoration(
          color: IviaColors.surface,
          borderRadius: BorderRadius.circular(IviaRadius.large),
          border: Border.all(
            color: selected ? brand.action : IviaColors.surface,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: soon ? IviaColors.textMuted : null,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? brand.action : IviaColors.border,
                ),
              ],
            ),
            const SizedBox(height: IviaSpacing.xs),
            Text(
              body,
              style: textTheme.bodySmall?.copyWith(
                color: soon ? IviaColors.textMuted : null,
              ),
            ),
            if (soon) ...[
              const SizedBox(height: IviaSpacing.sm),
              const IviaStatusPill(
                label: 'Bientôt',
                tone: IviaPillTone.neutral,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Récapitulatif refusé ou injoignable.
class _QuoteError extends StatelessWidget {
  const _QuoteError({
    required this.error,
    required this.onRetry,
    required this.onBack,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    // Refus venu du panier : on y retourne ; autre erreur : nouvel essai.
    final refused =
        error is ApiException &&
        _cartRefusals.contains((error as ApiException).code);
    final message = switch (error) {
      ApiException(code: 'shop_closed') =>
        'Cette boutique ne prend pas de commandes pour l’instant.',
      ApiException(isNetwork: false, :final message) => message,
      _ => 'Impossible de préparer la commande. Vérifiez votre connexion.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IviaSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: IviaSpacing.lg),
          if (refused)
            FilledButton(
              onPressed: onBack,
              child: const Text('Revenir au panier'),
            )
          else
            OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}
