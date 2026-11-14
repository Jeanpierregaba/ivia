import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../common/unavailable_view.dart';
import '../orders/order_screen.dart' show latePaymentWindow;
import '../orders/orders_providers.dart';
import 'payment_providers.dart';

/// Choix de « Je n'ai rien reçu ».
enum _Retry { resend, changeNumber }

/// « Validez le paiement sur votre téléphone » : temps restant, état relu
/// toutes les 3 s au premier plan, jusqu'à la réponse du prestataire.
class PaymentWaitScreen extends ConsumerStatefulWidget {
  const PaymentWaitScreen({
    super.key,
    required this.orderId,
    required this.paymentId,
  });

  final String orderId;
  final String paymentId;

  @override
  ConsumerState<PaymentWaitScreen> createState() => _PaymentWaitScreenState();
}

class _PaymentWaitScreenState extends ConsumerState<PaymentWaitScreen> {
  /// Horloge du temps restant (chaque seconde) ; relit la demande toutes les
  /// [paymentRefreshInterval].
  Timer? _clock;
  var _seconds = 0;
  late final AppLifecycleListener _lifecycle;

  /// Annulation, renvoi ou simulation en cours.
  var _busy = false;

  /// Paiement confirmé : le suivi est déjà ouvert.
  var _done = false;

  /// Numéro complet de cette demande, s'il vient d'être saisi (« Renvoyer
  /// la demande ») ; inconnu quand l'attente est reprise depuis le suivi.
  String? _phone;

  @override
  void initState() {
    super.initState();
    _phone = ref.read(paymentPhonesProvider).remove(widget.paymentId);
    _start();
    // App en arrière-plan (l'acheteur valide dans le menu de son opérateur) :
    // rien n'est relu ; au retour, relue aussitôt si l'attente continue.
    _lifecycle = AppLifecycleListener(
      onHide: _stop,
      onShow: () {
        if (!_waiting) return;
        if (ModalRoute.of(context)?.isCurrent ?? false) _reload();
        _start();
      },
    );
  }

  /// Heure du serveur : l'heure limite est la sienne.
  DateTime _now() => ref.read(apiClientProvider).now();

  /// L'attente continue : issue inconnue, et relecture pas encore finie.
  bool get _waiting {
    final payment = ref.read(paymentProvider(widget.paymentId)).value;
    if (payment != null && payment.status.isFinal) return false;
    final order = ref.read(orderProvider(widget.orderId)).value;
    return order == null || !_pollingOver(order);
  }

  @override
  void dispose() {
    _stop();
    _lifecycle.dispose();
    super.dispose();
  }

  void _start() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stop() {
    _clock?.cancel();
    _clock = null;
  }

  PaymentController get _controller =>
      ref.read(paymentProvider(widget.paymentId).notifier);

  void _tick() {
    if (!mounted) return;
    setState(() {}); // temps restant
    // Issue connue ou relecture finie : plus rien ne change à l'écran.
    if (!_waiting) {
      _stop();
      return;
    }
    if (++_seconds % paymentRefreshInterval.inSeconds != 0) return;
    // Pas sous une feuille ni un autre écran : une annulation qui croise
    // une validation est de toute façon rattrapée (409).
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _reload();
  }

  /// Un paiement validé en retard reprend encore la commande pendant
  /// [latePaymentWindow] après l'heure limite ; au-delà, on ne relit plus.
  bool _pollingOver(BuyerOrder order) =>
      _now().isAfter(order.paymentDeadlineAt.add(latePaymentWindow));

  void _reload() {
    if (!mounted || _busy) return;
    unawaited(_controller.refresh().catchError((Object _) {}));
  }

  /// Paiement confirmé par le serveur : suivi relu, avec le code de remise.
  void _succeeded() {
    if (_done || !mounted) return;
    _done = true;
    unawaited(
      ref
          .read(orderProvider(widget.orderId).notifier)
          .refresh()
          .catchError((Object _) {}),
    );
    showIviaNotification(
      context,
      title: 'Paiement reçu',
      body: 'La boutique va confirmer votre commande.',
      icon: Icons.payments_outlined,
      color: IviaColors.success,
    );
    context.go(Routes.order(widget.orderId));
  }

  /// Annule la demande en cours, puis [then]. Une demande déjà confirmée
  /// (l'annulation a croisé la validation) mène au suivi comme un succès.
  Future<void> _cancelThen(Future<void> Function() then) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).cancelPayment(widget.paymentId);
      await then();
    } on ApiException catch (e) {
      if (e.code == 'payment_not_cancellable') {
        await _controller.refresh().catchError((Object _) {});
        return;
      }
      showMessage(messenger, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(BuyerOrder? order) async {
    final confirmed = await _confirmCancel(order);
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final payable = order != null && _now().isBefore(order.paymentDeadlineAt);
    await _cancelThen(() async {
      showMessage(
        messenger,
        payable
            ? 'Paiement annulé. Vous pouvez payer jusqu’à '
                  '${timeOfDay(order.paymentDeadlineAt)}.'
            : 'Paiement annulé.',
      );
      router.go(Routes.order(widget.orderId));
    });
  }

  Future<void> _nothingReceived(Payment payment) async {
    final choice = await _showRetrySheet(payment);
    if (choice == null || !mounted) return;
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final phone = _phone;
    await _cancelThen(() async {
      if (choice == _Retry.changeNumber || phone == null) {
        router.go(Routes.pay(widget.orderId, operator: payment.operator));
        return;
      }
      try {
        final next = await ref
            .read(apiClientProvider)
            .startPayment(
              widget.orderId,
              operator: payment.operator,
              phone: phone,
            );
        ref.read(paymentPhonesProvider)[next.id] = phone;
        router.go(Routes.payWait(widget.orderId, next.id));
      } on ApiException catch (e) {
        // La demande est annulée : on repart de l'écran Paiement.
        showMessage(messenger, e.message);
        router.go(Routes.pay(widget.orderId, operator: payment.operator));
      }
    });
  }

  Future<void> _simulate({required bool succeeded}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .devSimulatePayment(widget.paymentId, succeeded: succeeded);
    } on ApiException catch (e) {
      showMessage(messenger, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(paymentProvider(widget.paymentId), (_, next) {
      if (next.value?.status.isPaid ?? false) _succeeded();
    });
    final payment = ref.watch(paymentProvider(widget.paymentId));
    final order = ref.watch(orderProvider(widget.orderId)).value;
    // Pas de retour pendant une annulation : son issue doit être connue.
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        body: SafeArea(
          child: switch (payment) {
            AsyncError(:final error) when !payment.isLoading => UnavailableView(
              error: error,
              gone: 'Ce paiement n’est plus disponible.',
              onRetry: () => ref.invalidate(paymentProvider(widget.paymentId)),
            ),
            // Statut inconnu de cette version : traité comme en attente.
            AsyncValue(value: final p?) when !p.status.isFinal => _pending(
              p,
              order,
            ),
            AsyncValue(value: final p?) when !p.status.isPaid => _failed(
              p,
              order,
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  Widget _pending(Payment payment, BuyerOrder? order) {
    final textTheme = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    final operator = operatorLabel(payment.operator);
    final amount = formatXof(payment.amountXof);
    final phone = formatMaskedTogoPhone(payment.phoneMasked);
    final ending = payment.phoneMasked.length >= 2
        ? payment.phoneMasked.substring(payment.phoneMasked.length - 2)
        : '';
    final now = _now();
    final late = order != null && now.isAfter(order.paymentDeadlineAt);
    final over = order != null && _pollingOver(order);
    return ListView(
      padding: const EdgeInsets.all(IviaSpacing.screen),
      children: [
        _back(),
        const SizedBox(height: IviaSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(IviaSpacing.xl),
            decoration: const BoxDecoration(
              color: IviaColors.surface,
              shape: BoxShape.circle,
            ),
            child: over
                ? Icon(Icons.hourglass_empty, color: brand.action, size: 40)
                : CircularProgressIndicator(
                    strokeWidth: 5,
                    color: brand.action,
                    backgroundColor: IviaColors.primarySoft,
                    semanticsLabel: 'En attente de validation',
                  ),
          ),
        ),
        const SizedBox(height: IviaSpacing.xl),
        Semantics(
          header: true,
          child: Text(
            'Validez le paiement sur votre téléphone',
            style: textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: IviaSpacing.md),
        Text(
          'Une demande $operator de $amount a été envoyée au $phone. '
          'Saisissez votre code secret pour confirmer.',
          semanticsLabel:
              'Une demande $operator de $amount a été envoyée au numéro se '
              'terminant par $ending. Saisissez votre code secret pour '
              'confirmer.',
          style: textTheme.bodyLarge?.copyWith(color: IviaColors.textSecondary),
        ),
        if (order != null) ...[
          const SizedBox(height: IviaSpacing.xl),
          _TimeLeft(order: order, now: now, late: late),
        ],
        const SizedBox(height: IviaSpacing.xxl),
        if (over) ...[
          FilledButton(
            onPressed: () => context.go(Routes.order(widget.orderId)),
            child: const Text('Retour à la commande'),
          ),
          const SizedBox(height: IviaSpacing.sm),
        ],
        if (ref.watch(devPaymentsProvider)) ...[
          OutlinedButton(
            onPressed: _busy ? null : () => _simulate(succeeded: true),
            child: const Text('Simuler la validation'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _simulate(succeeded: false),
            child: const Text('Simuler un refus'),
          ),
          const SizedBox(height: IviaSpacing.sm),
        ],
        if (!late) ...[
          OutlinedButton(
            onPressed: _busy ? null : () => _nothingReceived(payment),
            child: const Text('Je n’ai rien reçu'),
          ),
          const SizedBox(height: IviaSpacing.sm),
        ],
        TextButton(
          onPressed: _busy ? null : () => _cancel(order),
          child: const Text('Annuler le paiement'),
        ),
      ],
    );
  }

  Widget _failed(Payment payment, BuyerOrder? order) {
    final textTheme = Theme.of(context).textTheme;
    final payable =
        order != null &&
        order.status == OrderStatus.pendingPayment &&
        _now().isBefore(order.paymentDeadlineAt);
    return ListView(
      padding: const EdgeInsets.all(IviaSpacing.screen),
      children: [
        _back(),
        const SizedBox(height: IviaSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: IviaColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.close_rounded,
              color: IviaColors.error,
              size: 48,
            ),
          ),
        ),
        const SizedBox(height: IviaSpacing.xl),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            'Le paiement n’a pas abouti',
            style: textTheme.headlineMedium,
          ),
        ),
        if (payment.failureReason.isNotEmpty) ...[
          const SizedBox(height: IviaSpacing.md),
          Text(
            payment.failureReason,
            style: textTheme.bodyLarge?.copyWith(
              color: IviaColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: IviaSpacing.xxl),
        if (payable) ...[
          FilledButton(
            onPressed: () => context.go(
              Routes.pay(widget.orderId, operator: payment.operator),
            ),
            child: const Text('Réessayer'),
          ),
          const SizedBox(height: IviaSpacing.sm),
        ],
        OutlinedButton(
          onPressed: () => context.go(Routes.order(widget.orderId)),
          child: const Text('Retour à la commande'),
        ),
      ],
    );
  }

  /// Retour au suivi, sans annuler ; bloqué pendant une annulation.
  Widget _back() => Align(
    alignment: Alignment.centerLeft,
    child: IviaBackButton(
      onPressed: _busy
          ? null
          : () => context.canPop()
                ? context.pop()
                : context.go(Routes.order(widget.orderId)),
    ),
  );

  Future<bool> _confirmCancel(BuyerOrder? order) async {
    final payable = order != null && _now().isBefore(order.paymentDeadlineAt);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _Sheet(
        title: 'Annuler le paiement ?',
        body: payable
            ? 'La demande envoyée sur votre téléphone sera abandonnée. Votre '
                  'commande reste réservée jusqu’à '
                  '${timeOfDay(order.paymentDeadlineAt)} : vous pourrez la '
                  'payer depuis son suivi.'
            : 'La demande envoyée sur votre téléphone sera abandonnée. Le '
                  'délai de paiement est dépassé : la commande ne pourra plus '
                  'être payée.',
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: IviaColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler le paiement'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: IviaColors.background,
              foregroundColor: IviaColors.text,
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer d’attendre'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<_Retry?> _showRetrySheet(Payment payment) {
    final operator = operatorLabel(payment.operator);
    final phone = formatMaskedTogoPhone(payment.phoneMasked);
    return showModalBottomSheet<_Retry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _Sheet(
        title: 'Vous n’avez rien reçu ?',
        body:
            'Vérifiez que le $phone est bien votre numéro $operator et que '
            'votre téléphone a du réseau. La demande en cours sera annulée '
            'avant d’en envoyer une nouvelle.',
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, _Retry.resend),
            child: const Text('Renvoyer la demande'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, _Retry.changeNumber),
            child: const Text('Changer de numéro'),
          ),
        ],
      ),
    );
  }
}

/// Temps restant avant l'heure limite de la commande, barre qui se vide.
class _TimeLeft extends StatelessWidget {
  const _TimeLeft({required this.order, required this.now, required this.late});

  final BuyerOrder order;

  /// Heure du serveur.
  final DateTime now;
  final bool late;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    final total = order.paymentDeadlineAt.difference(order.createdAt);
    final left = order.paymentDeadlineAt.difference(now);
    final fraction = total.inSeconds <= 0 || left.isNegative
        ? 0.0
        : (left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(IviaSpacing.lg),
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
      ),
      child: late
          ? Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Délai de paiement dépassé',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: IviaSpacing.xs),
                  Text(
                    'Si vous avez validé, nous vérifions votre paiement.',
                    style: textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Lu une fois, en toutes lettres ; pas à chaque seconde.
                Semantics(
                  label: 'Temps restant : ${countdownLabel(left)}',
                  excludeSemantics: true,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: IviaSpacing.sm,
                    children: [
                      Text('Temps restant', style: textTheme.bodyLarge),
                      Text(
                        countdown(left),
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: IviaSpacing.md),
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 8,
                      color: brand.action,
                      backgroundColor: IviaColors.background,
                    ),
                  ),
                ),
                const SizedBox(height: IviaSpacing.md),
                Text(
                  'Vos produits sont réservés pendant ${total.inMinutes} '
                  'minutes.',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}

/// Feuille du bas : titre, texte, boutons empilés.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        IviaSpacing.screen,
        0,
        IviaSpacing.screen,
        IviaSpacing.screen,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: textTheme.headlineSmall),
          ),
          const SizedBox(height: IviaSpacing.md),
          Text(
            body,
            style: textTheme.bodyLarge?.copyWith(
              color: IviaColors.textSecondary,
            ),
          ),
          const SizedBox(height: IviaSpacing.xl),
          for (final (i, action) in actions.indexed) ...[
            if (i > 0) const SizedBox(height: IviaSpacing.sm),
            action,
          ],
        ],
      ),
    );
  }
}
