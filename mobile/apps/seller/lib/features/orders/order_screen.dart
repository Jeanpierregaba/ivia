import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';
import 'handover_screen.dart';
import 'order_labels.dart';
import 'orders_providers.dart';
import 'reject_sheet.dart';

/// Message d'une commande disparue (autre boutique, lien ancien).
const orderNotFoundMessage = 'Commande introuvable.';

/// Détail d'une commande (« Commande #1042 ») : statut, compte à rebours
/// d'une nouvelle, articles, montants, et l'action de l'étape. Relu toutes
/// les 30 s au premier plan et au retour dans l'app ; tirer vers le bas
/// actualise.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;

  /// Action en cours d'envoi : boutons désactivés (une seule requête).
  var _busy = false;

  /// Délai pour accepter dépassé, écran ouvert : plus d'acceptation.
  var _expired = false;

  @override
  void initState() {
    super.initState();
    _start();
    _lifecycle = AppLifecycleListener(
      onHide: _stop,
      onShow: () {
        _reload();
        _start();
      },
    );
  }

  @override
  void dispose() {
    _stop();
    unawaited(_live?.cancel());
    _lifecycle.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(ordersRefreshInterval, (_) => _tick());
    // Temps réel (spec 036) : la commande est relue dès qu'elle change.
    _live ??= ref.read(iviaRealtimeProvider('seller')).events.listen((e) {
      if (e.orderId == widget.orderId || e.kind == RealtimeEvent.reconnected) {
        _reload();
      }
    });
  }

  StreamSubscription<RealtimeEvent>? _live;

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  SellerOrderController get _controller =>
      ref.read(sellerOrderProvider(widget.orderId).notifier);

  /// Relecture régulière : seulement si le détail est au premier plan
  /// (pas sous la saisie du code).
  void _tick() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _reload();
  }

  void _reload() {
    if (!mounted) return;
    unawaited(_controller.refresh().catchError((Object _) {}));
  }

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await _controller.refresh();
    } on ApiException catch (e) {
      if (e.code == 'order_not_found') {
        showMessage(messenger, orderNotFoundMessage);
        router.go(Routes.orders);
      } else {
        showMessage(
          messenger,
          e.isNetwork
              ? 'Commande non actualisée. Vérifiez votre connexion.'
              : e.message,
        );
      }
    } on Exception {
      showMessage(messenger, 'Commande non actualisée. Réessayez.');
    }
  }

  /// Refus de la dernière action, affiché au-dessus du bouton (un message
  /// en bas d'écran le cacherait).
  String? _error;

  /// Envoie une action ; la commande rendue remplace l'ancienne (détail et
  /// liste, même si l'écran a été quitté pendant la requête). Refus du
  /// serveur : message au-dessus du bouton, et commande relue pour montrer
  /// son vrai statut.
  Future<void> _run(
    Future<SellerOrder> Function(IviaApiClient client) call,
  ) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    // Lus avant l'envoi : utilisables même après la fermeture de l'écran.
    final client = ref.read(apiClientProvider);
    final list = ref.read(sellerOrdersProvider.notifier);
    final shop = ref.read(sellerShopProvider.notifier);
    final detail = _controller;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      final order = await call(client);
      list.replace(order);
      if (mounted) detail.set(order);
    } on ApiException catch (e) {
      if (e.isNetwork) {
        error = 'Pas de connexion. Réessayez.';
      } else if (e.code == 'order_not_found') {
        showMessage(messenger, orderNotFoundMessage);
        router.go(Routes.orders);
      } else {
        error = e.message;
        if (e.code == 'shop_suspended' || e.code == 'shop_not_found') {
          unawaited(shop.refresh());
        } else {
          _reload();
        }
      }
    } on Exception {
      error = 'Une erreur est survenue. Réessayez.';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
    }
  }

  /// « Refuser » : motif choisi dans la feuille, puis refus envoyé.
  Future<void> _reject(String id) async {
    final reason = await showRejectSheet(context);
    if (reason == null || !mounted) return;
    await _run((c) => c.rejectOrder(id, reason));
  }

  void _onExpired() {
    if (!mounted || _expired) return;
    setState(() => _expired = true);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(sellerOrderProvider(widget.orderId));
    return Scaffold(
      body: SafeArea(
        child: switch (order) {
          AsyncValue(value: final value?) => _content(value),
          AsyncError(:final error) => _Unavailable(
            gone: error is ApiException && error.code == 'order_not_found',
            onRetry: () => ref.invalidate(sellerOrderProvider(widget.orderId)),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _content(SellerOrder order) {
    final textTheme = Theme.of(context).textTheme;
    final action = _action(order);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(IviaSpacing.screen),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IviaBackButton(onPressed: _back),
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
                _Header(order: order, onExpired: _onExpired),
                const SizedBox(height: IviaSpacing.lg),
                if (order.fulfillment == Fulfillment.delivery &&
                    (order.status == OrderStatus.driverAssigned ||
                        order.status == OrderStatus.pickedUp))
                  DeliveryProgress(
                    key: ValueKey('livraison-${order.id}'),
                    orderId: order.id,
                    app: 'seller',
                    customerView: false,
                    load: (api, id) => api.sellerOrderDelivery(id),
                  ),
                _Items(order: order),
                const SizedBox(height: IviaSpacing.lg),
                _Amounts(order: order),
                if (order.status == OrderStatus.delivered) ...[
                  const SizedBox(height: IviaSpacing.lg),
                  _DriverRating(orderId: order.id),
                ],
              ],
            ),
          ),
        ),
        if (action != null || _error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              IviaSpacing.screen,
              IviaSpacing.sm,
              IviaSpacing.screen,
              IviaSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error case final error?) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: IviaColors.error,
                      ),
                    ),
                  ),
                  if (action != null) const SizedBox(height: IviaSpacing.sm),
                ],
                ?action,
              ],
            ),
          ),
      ],
    );
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.orders);
    }
  }

  /// Bouton(s) de l'étape ; `null` : aucune action (terminée, livraison en
  /// cours).
  Widget? _action(SellerOrder order) {
    final id = order.id;
    Widget primary(String label, VoidCallback? onPressed) => FilledButton(
      onPressed: _busy ? null : onPressed,
      child: _busy ? const ButtonProgress() : Text(label),
    );
    return switch (order.status) {
      OrderStatus.awaitingSeller => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary(
            'Accepter la commande',
            _expired || _deadlinePassed(order)
                ? null
                : () => _run((c) => c.acceptOrder(id)),
          ),
          const SizedBox(height: IviaSpacing.sm),
          OutlinedButton(
            onPressed: _busy || _expired || _deadlinePassed(order)
                ? null
                : () => _reject(id),
            child: const Text('Refuser'),
          ),
        ],
      ),
      OrderStatus.accepted => primary(
        'Commencer la préparation',
        () => _run((c) => c.startPreparingOrder(id)),
      ),
      OrderStatus.readyForPickup when order.isHandoverLocked => Semantics(
        liveRegion: true,
        child: Text(
          handoverLockedMessage,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: IviaColors.error),
        ),
      ),
      OrderStatus.readyForPickup => primary(
        "Saisir le code de l'acheteur",
        () => context.push(Routes.handover(id)),
      ),
      OrderStatus.preparing => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            order.fulfillment == Fulfillment.pickup
                ? "L'acheteur sera prévenu qu'il peut venir."
                : 'Un livreur sera recherché.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: IviaColors.textSecondary),
          ),
          const SizedBox(height: IviaSpacing.sm),
          primary('Commande prête', () => _run((c) => c.markOrderReady(id))),
        ],
      ),
      _ => null,
    };
  }

  bool _deadlinePassed(SellerOrder order) => switch (order.sellerDeadlineAt) {
    final at? => !at.isAfter(ref.read(apiClientProvider).now()),
    null => false,
  };
}

/// En-tête : statut, « Pour Koffi · Retrait en boutique », heure du
/// paiement ; compte à rebours d'une nouvelle ; motif d'une annulation.
class _Header extends ConsumerWidget {
  const _Header({required this.order, required this.onExpired});

  final SellerOrder order;
  final VoidCallback onExpired;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final client = ref.watch(apiClientProvider);
    final mode = switch (order.fulfillment) {
      Fulfillment.pickup => 'Retrait en boutique',
      Fulfillment.delivery => 'Livraison',
    };
    final who = order.buyerFirstName.isEmpty
        ? mode
        : 'Pour ${order.buyerFirstName} · $mode';
    final deadline = order.status == OrderStatus.awaitingSeller
        ? order.sellerDeadlineAt
        : null;
    final paidAt = order.paidAt;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: statusPill(
              order.status,
              label: sellerStatusLabel(order.status),
            ),
          ),
          const SizedBox(height: IviaSpacing.md),
          Text(who, style: textTheme.titleMedium),
          if (paidAt != null) ...[
            const SizedBox(height: IviaSpacing.xs),
            Text(
              'Payée à ${timeOfDay(paidAt)}',
              style: textTheme.bodyMedium?.copyWith(
                color: IviaColors.textSecondary,
              ),
            ),
          ],
          if (deadline != null) ...[
            const SizedBox(height: IviaSpacing.lg),
            IviaCountdown(
              deadline: deadline,
              now: client.now,
              onExpired: onExpired,
              label: (t) => 'Il vous reste $t pour répondre',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: IviaSpacing.xs),
            Text(
              "Sans réponse, la commande est annulée et l'acheteur remboursé.",
              style: textTheme.bodyMedium?.copyWith(
                color: IviaColors.textSecondary,
              ),
            ),
          ],
          if (order.status == OrderStatus.cancelled &&
              order.cancelReason.isNotEmpty) ...[
            const SizedBox(height: IviaSpacing.sm),
            Text(order.cancelReason, style: textTheme.bodyMedium),
          ],
          if (order.status == OrderStatus.awaitingDriver ||
              order.status == OrderStatus.driverAssigned ||
              order.status == OrderStatus.pickedUp) ...[
            const SizedBox(height: IviaSpacing.sm),
            Text(
              'La suite de la livraison est gérée par ivia.',
              style: textTheme.bodyMedium?.copyWith(
                color: IviaColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Articles : « 2 × Pagne wax … 9 000 F » ; un produit à stock non suivi
/// porte « Vérifiez que vous l'avez ».
class _Items extends StatelessWidget {
  const _Items({required this.order});

  final SellerOrder order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final check =
        order.status == OrderStatus.awaitingSeller ||
        order.status == OrderStatus.accepted;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(articles(order.articleCount), style: textTheme.titleSmall),
          const SizedBox(height: IviaSpacing.sm),
          for (final item in order.items) ...[
            IviaAmountRow(
              label: '${item.quantity} × ${item.name}',
              amount: formatXof(item.lineTotalXof),
            ),
            if (check && item.stockMode == StockMode.untracked)
              Padding(
                padding: const EdgeInsets.only(bottom: IviaSpacing.xs),
                child: Text(
                  "Stock non suivi : vérifiez que vous l'avez.",
                  style: textTheme.bodySmall?.copyWith(
                    color: IviaColors.warning,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Montants : produits, commission ivia, « Vous recevez ».
/// Note du livreur par le marchand (facultative), une fois la commande livrée.
final _driverRatingProvider = FutureProvider.autoDispose
    .family<OrderRating, String>(
      (ref, id) => ref.read(apiClientProvider).sellerDriverRating(id),
    );

class _DriverRating extends ConsumerWidget {
  const _DriverRating({required this.orderId});

  final String orderId;

  Future<void> _rate(BuildContext context, WidgetRef ref) async {
    final client = ref.read(apiClientProvider);
    final ok = await showRatingSheet(
      context,
      title: 'Comment était le livreur ?',
      subtitle: 'Ponctualité, soin du colis, politesse…',
      leading: const CircleAvatar(
        radius: 30,
        backgroundColor: IviaColors.secondarySoft,
        child: Icon(
          Icons.delivery_dining_rounded,
          color: IviaColors.secondary,
          size: 32,
        ),
      ),
      praiseTags: driverPraiseTags,
      issueTags: driverIssueTags,
      onSubmit: (r) async {
        try {
          await client.rateDriverAsSeller(
            orderId,
            stars: r.stars,
            tags: r.tags,
            comment: r.comment,
          );
          return null;
        } on ApiException catch (e) {
          return e.message;
        }
      },
    );
    if (ok) ref.invalidate(_driverRatingProvider(orderId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_driverRatingProvider(orderId)).value;
    if (state == null || (!state.canRate && state.rating == null)) {
      return const SizedBox.shrink();
    }
    final stars = state.rating?.stars ?? 0;
    return _Card(
      child: InkWell(
        onTap: state.canRate ? () => _rate(context, ref) : null,
        child: Row(
          children: [
            const Icon(
              Icons.delivery_dining_rounded,
              color: IviaColors.secondary,
            ),
            const SizedBox(width: IviaSpacing.md),
            Expanded(
              child: Text(
                state.canRate ? 'Noter le livreur' : 'Livreur noté, merci !',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (var i = 1; i <= 5; i++)
              Icon(
                i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 20,
                color: i <= stars
                    ? const Color(0xFFF5B301)
                    : IviaColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

class _Amounts extends StatelessWidget {
  const _Amounts({required this.order});

  final SellerOrder order;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IviaAmountRow(label: 'Produits', amount: formatXof(order.subtotalXof)),
        if (order.discountPaidByShop)
          IviaAmountRow(
            label: 'Code promo (${order.promoCode ?? ''})',
            amount: '− ${formatXof(order.discountXof)}',
          ),
        IviaAmountRow(
          label: 'Commission ivia',
          amount: '− ${formatXof(order.commissionXof)}',
        ),
        const Divider(height: IviaSpacing.xl),
        IviaAmountRow(
          label: 'Vous recevez',
          amount: formatXof(order.netXof),
          strong: true,
        ),
      ],
    ),
  );
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

/// Commande introuvable, ou impossible à charger (réseau).
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.gone, required this.onRetry});

  final bool gone;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(IviaSpacing.screen),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IviaBackButton(onPressed: () => context.go(Routes.orders)),
        ),
        const Spacer(),
        Text(
          gone
              ? orderNotFoundMessage
              : 'Impossible de charger la commande. Vérifiez votre connexion.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: IviaSpacing.lg),
        if (gone)
          FilledButton(
            onPressed: () => context.go(Routes.orders),
            child: const Text('Voir les commandes'),
          )
        else
          OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
        const Spacer(),
      ],
    ),
  );
}
