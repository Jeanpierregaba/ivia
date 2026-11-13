import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../common/unavailable_view.dart';
import 'cancel_sheet.dart';
import 'order_labels.dart';
import 'invoice.dart';
import 'receipt_screen.dart';
import 'order_parts.dart';
import 'rating_card.dart';
import 'orders_providers.dart';

/// Intervalle de relecture d'une commande en cours affichée.
const orderRefreshInterval = Duration(seconds: 20);

/// Suivi d'une commande : en-tête de l'étape, code de remise, boutique,
/// frise, articles. Relu toutes les 20 s tant qu'il est au premier plan et
/// que la commande peut changer.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

/// Après l'heure limite, une commande expirée peut encore être reprise par
/// un paiement arrivé en retard : elle reste relue ce temps-là.
const latePaymentWindow = Duration(minutes: 10);

/// La commande peut encore changer d'elle-même : on la relit.
bool shouldPoll(BuyerOrder order, {DateTime? now}) =>
    order.status.isActive ||
    (order.status == OrderStatus.expired &&
        (now ?? DateTime.now()).isBefore(
          order.paymentDeadlineAt.add(latePaymentWindow),
        ));

class _OrderScreenState extends ConsumerState<OrderScreen> {
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _start();
    // App en arrière-plan : aucune relecture ; au retour, relue aussitôt
    // (quel que soit son statut), puis toutes les 20 s.
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
    _timer = Timer.periodic(orderRefreshInterval, (_) => _tick());
    // Temps réel (spec 036) : la commande est relue dès qu'elle change.
    _live ??= ref.read(iviaRealtimeProvider('buyer')).events.listen((e) {
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

  OrderController get _controller =>
      ref.read(orderProvider(widget.orderId).notifier);

  /// Relecture régulière : seulement si le suivi est au premier plan et la
  /// commande susceptible de changer ; arrêtée sinon.
  void _tick() {
    if (!mounted) return;
    final order = ref.read(orderProvider(widget.orderId)).value;
    if (order == null) return;
    if (!shouldPoll(order, now: ref.read(apiClientProvider).now())) {
      _stop();
      return;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _reload();
  }

  void _reload() {
    if (!mounted) return;
    unawaited(_controller.refresh().catchError((Object _) {}));
  }

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _controller.refresh();
    } catch (_) {
      showMessage(
        messenger,
        'Commande non actualisée. Vérifiez votre connexion.',
      );
    }
  }

  /// Annulation en cours d'envoi : bouton désactivé (une seule requête).
  var _cancelling = false;

  /// Message d'un refus d'annulation selon le vrai statut de la commande
  /// relue : le serveur répond « La boutique a déjà accepté… » même quand
  /// elle est expirée ou déjà annulée.
  static String _refusal(BuyerOrder? seen, String serverMessage) =>
      switch (seen?.status) {
        OrderStatus.expired =>
          'Cette commande a expiré : vos produits sont déjà libérés.',
        OrderStatus.cancelled ||
        OrderStatus.refunded => 'Cette commande est déjà annulée.',
        _ => serverMessage,
      };

  /// « Annuler la commande » : confirmation, puis demande de paiement en
  /// attente annulée d'abord, puis la commande. Toute commande rendue par le
  /// serveur (annulée ou relue) est reportée dans le suivi et dans la liste,
  /// même si l'écran est quitté pendant l'envoi.
  Future<void> _cancel(BuyerOrder order) async {
    if (_cancelling) return;
    if (!await showCancelSheet(context, order) || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    final client = ref.read(apiClientProvider);
    final controller = ref.read(orderProvider(widget.orderId).notifier);
    // Conteneur lu avant l'envoi : la liste, même chargée entre-temps,
    // reçoit le résultat.
    final container = ProviderScope.containerOf(context, listen: false);
    void publish(BuyerOrder o) {
      if (container.exists(myOrdersProvider)) {
        container.read(myOrdersProvider.notifier).put(o);
      }
      controller.set(o);
    }

    setState(() => _cancelling = true);
    BuyerOrder? again;
    try {
      // Affichée non payée : relue d'abord (payée entre deux relectures, ou
      // demande en attente validée pendant l'annulation de la demande).
      // Payée et toujours annulable : l'acheteur confirme de nouveau, en
      // voyant le montant remboursé.
      final changed = await _beforeCancel(client, order);
      if (changed != null) {
        publish(changed);
        if (canCancel(changed)) {
          again = changed;
        } else {
          showMessage(messenger, _refusal(changed, 'Commande déjà traitée.'));
        }
      } else {
        final cancelled = await client.cancelOrder(order.id);
        publish(cancelled);
        showIviaNotificationOn(
          overlay,
          title: 'Commande annulée.',
          body: 'Vos produits sont libérés.',
          icon: Icons.cancel_outlined,
          color: IviaColors.error,
        );
      }
    } on ApiException catch (e) {
      if (e.isNetwork) {
        showMessage(messenger, 'Pas de connexion. Réessayez.');
      } else if (e.code == 'cannot_cancel' || e.code == 'invalid_transition') {
        // Commande relue : son vrai statut, bouton retiré, message juste.
        BuyerOrder? seen;
        try {
          seen = await client.myOrder(order.id);
          publish(seen);
        } on Exception {
          // Message du serveur seul.
        }
        showMessage(messenger, _refusal(seen, e.message));
      } else {
        showMessage(messenger, e.message);
      }
    } on Exception {
      showMessage(messenger, 'Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
    if (again != null && mounted) await _cancel(again);
  }

  /// Avant d'annuler une commande affichée non payée : la relit et annule
  /// sa demande de paiement en attente. Renvoie la commande relue si elle a
  /// changé (payée, ou plus annulable), `null` si l'annulation peut partir.
  Future<BuyerOrder?> _beforeCancel(
    IviaApiClient client,
    BuyerOrder order,
  ) async {
    if (order.status != OrderStatus.pendingPayment) return null;
    final fresh = await client.myOrder(order.id);
    if (fresh.paidAt != null || fresh.status != OrderStatus.pendingPayment) {
      return fresh;
    }
    final payments = await client.orderPayments(order.id);
    final pending = payments.where((p) => p.status.isPending).firstOrNull;
    if (pending == null) return null;
    try {
      await client.cancelPayment(pending.id);
      return null;
    } on ApiException catch (e) {
      if (e.code != 'payment_not_cancellable') rethrow;
      return client.myOrder(order.id);
    }
  }

  /// Ouverture du paiement en cours (lecture des demandes de la commande).
  var _opening = false;

  /// « Payer » : la demande en attente, s'il y en a une, est reprise (pas de
  /// nouvelle demande) ; sinon l'écran Paiement s'ouvre.
  Future<void> _pay() async {
    if (_opening) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _opening = true);
    try {
      final payments = await ref
          .read(apiClientProvider)
          .orderPayments(widget.orderId);
      final pending = payments.where((p) => p.status.isPending).firstOrNull;
      if (!mounted) return;
      router.go(
        pending == null
            ? Routes.pay(widget.orderId)
            : Routes.payWait(widget.orderId, pending.id),
      );
    } on ApiException catch (e) {
      showMessage(messenger, e.message);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        // L'erreur d'abord : après un 404, la version précédente (autre
        // compte) n'est jamais montrée.
        child: switch (order) {
          AsyncError(:final error) when !order.isLoading => UnavailableView(
            error: error,
            gone: 'Cette commande n’est plus disponible.',
            onRetry: () => ref.invalidate(orderProvider(widget.orderId)),
          ),
          AsyncValue(value: final value?) => _content(value),
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
          if (order.fulfillment == Fulfillment.delivery &&
              (order.status == OrderStatus.driverAssigned ||
                  order.status == OrderStatus.pickedUp))
            DeliveryProgress(
              key: ValueKey('livraison-${order.id}'),
              orderId: order.id,
              app: 'buyer',
              load: (api, id) => api.orderDelivery(id),
            ),
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
          _Header(order: order, onPay: _opening ? null : _pay),
          const SizedBox(height: IviaSpacing.lg),
          if (order.status == OrderStatus.delivered) ...[
            DeliveryRatingCard(orderId: order.id),
            const SizedBox(height: IviaSpacing.lg),
          ],
          _ShopTile(shop: order.shop),
          const SizedBox(height: IviaSpacing.lg),
          OrderCard(child: IviaTimeline(steps: timelineOf(order))),
          const SizedBox(height: IviaSpacing.lg),
          OrderCard(
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
                  IviaAmountRow(
                    label: '${item.quantity} × ${item.name}',
                    amount: formatXof(item.lineTotalXof),
                  ),
                const Divider(height: IviaSpacing.xl),
                if (order.discountXof > 0)
                  IviaAmountRow(
                    label: 'Réduction (${order.promoCode ?? ''})',
                    amount: '− ${formatXof(order.discountXof)}',
                  ),
                IviaAmountRow(
                  label: 'Total',
                  amount: formatXof(order.totalXof),
                  strong: true,
                ),
              ],
            ),
          ),
          if (order.paidAt != null ||
              order.status == OrderStatus.cancelled ||
              order.status == OrderStatus.expired) ...[
            const SizedBox(height: IviaSpacing.lg),
            Builder(
              builder: (context) {
                final me = switch (ref.read(authControllerProvider)) {
                  AuthSignedIn(:final user) => user,
                  _ => null,
                };
                final invoice = Invoice.fromOrder(order, me);
                return OutlinedButton.icon(
                  onPressed: () => showReceipt(context, invoice),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(
                    invoice.isReceipt
                        ? 'Voir le reçu'
                        : 'Voir le récapitulatif',
                  ),
                );
              },
            ),
          ],
          if (canCancel(order)) ...[
            const SizedBox(height: IviaSpacing.xl),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: IviaColors.error,
                side: const BorderSide(color: IviaColors.error),
              ),
              onPressed: _cancelling ? null : () => _cancel(order),
              child: _cancelling
                  ? const ButtonProgress()
                  : const Text('Annuler la commande'),
            ),
          ],
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
  final VoidCallback? onPay;

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
          final at? =>
            '${_capitalized(onDate(at))} à ${timeOfDay(at)}. Merci !',
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
        [
          if (order.cancelReason.isNotEmpty) order.cancelReason,
          // Payée : remboursement intégral, fait par l'équipe ivia.
          if (order.paidAt != null) refundNotice(order),
        ].join('\n'),
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
            Semantics(
              liveRegion: true,
              child: Text(
                title,
                style: textTheme.headlineSmall?.copyWith(color: foreground),
              ),
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
              // Lu par le code lui-même (« Code de remise : 4 8 2 7 »).
              ExcludeSemantics(
                child: Text(
                  'Votre code de remise',
                  style: textTheme.bodyMedium?.copyWith(color: foreground),
                ),
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

String _capitalized(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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
