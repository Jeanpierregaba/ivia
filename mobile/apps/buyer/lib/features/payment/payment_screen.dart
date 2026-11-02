import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/messages.dart';
import '../../app/router.dart';
import '../common/unavailable_view.dart';
import '../orders/orders_providers.dart';
import 'payment_providers.dart';

/// Refus qui disent que la commande ne se paie plus : retour au suivi.
const _notPayable = {'order_not_payable', 'order_expired'};

/// Paiement : montant, opérateur, numéro, « Payer ». La demande envoyée,
/// l'écran d'attente prend la place de celui-ci.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({
    super.key,
    required this.orderId,
    this.operator = PaymentOperator.flooz,
  });

  final String orderId;

  /// Opérateur choisi à l'ouverture (« Réessayer », « Changer de numéro »).
  final PaymentOperator operator;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  late var _operator = widget.operator;

  /// Numéro du profil, modifiable ; jamais gardé sur le téléphone.
  late final _phone = TextEditingController(
    text: switch (ref.read(authControllerProvider)) {
      AuthSignedIn(:final user) => formatTogoPhone(user.phone ?? ''),
      _ => '',
    },
  );
  String? _phoneError;
  var _sending = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final digits = togoPhoneDigits(_phone.text);
    if (!isTogoMobile(digits)) {
      setState(
        () => _phoneError = 'Numéro à 8 chiffres commençant par 7 ou 9.',
      );
      return;
    }
    final phone = '+228$digits';
    final client = ref.read(apiClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() {
      _phoneError = null;
      _sending = true;
    });
    try {
      final payment = await client.startPayment(
        widget.orderId,
        operator: _operator,
        phone: phone,
      );
      // Le numéro complet ne sert qu'à « Renvoyer la demande » : en mémoire.
      router.go(Routes.payWait(widget.orderId, payment.id), extra: phone);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'validation_failed' && e.fields['phone'] != null) {
        setState(() => _phoneError = e.fields['phone']);
        return;
      }
      showMessage(messenger, e.message);
      if (_notPayable.contains(e.code)) {
        _refreshOrder();
        router.go(Routes.order(widget.orderId));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _refreshOrder() => ref
      .read(orderProvider(widget.orderId).notifier)
      .refresh()
      .catchError((Object _) {});

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));
    // Pas de retour pendant l'envoi : l'issue de la demande doit être connue.
    return PopScope(
      canPop: !_sending,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
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
        bottomNavigationBar: switch (order.value) {
          final o? when o.status == OrderStatus.pendingPayment => SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(
              IviaSpacing.screen,
              IviaSpacing.sm,
              IviaSpacing.screen,
              IviaSpacing.screen,
            ),
            child: FilledButton(
              onPressed: _sending ? null : _pay,
              child: _sending
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Envoi de la demande',
                      ),
                    )
                  : Text('Payer ${formatXof(o.totalXof)}'),
            ),
          ),
          _ => null,
        },
      ),
    );
  }

  Widget _content(BuyerOrder order) {
    final textTheme = Theme.of(context).textTheme;
    final label = operatorLabel(_operator);
    return ListView(
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
            onPressed: _sending ? null : () => context.pop(),
          ),
        ),
        const SizedBox(height: IviaSpacing.md),
        Semantics(
          header: true,
          child: Text('Paiement', style: textTheme.headlineSmall),
        ),
        const SizedBox(height: IviaSpacing.lg),
        if (order.status != OrderStatus.pendingPayment) ...[
          Text(
            'Cette commande n’attend plus de paiement.',
            style: textTheme.bodyLarge,
          ),
          const SizedBox(height: IviaSpacing.lg),
          FilledButton(
            onPressed: () => context.go(Routes.order(order.id)),
            child: const Text('Retour à la commande'),
          ),
        ] else ...[
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Montant à payer',
                  style: textTheme.bodyLarge?.copyWith(
                    color: IviaColors.textSecondary,
                  ),
                ),
                Text(
                  formatXof(order.totalXof),
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: IviaSpacing.xl),
          Text('Opérateur', style: textTheme.titleSmall),
          const SizedBox(height: IviaSpacing.sm),
          for (final operator in PaymentOperator.values) ...[
            _OperatorCard(
              operator: operator,
              selected: operator == _operator,
              onTap: _sending
                  ? null
                  : () => setState(() => _operator = operator),
            ),
            const SizedBox(height: IviaSpacing.md),
          ],
          const SizedBox(height: IviaSpacing.sm),
          TogoPhoneField(
            label: 'Numéro $label',
            controller: _phone,
            enabled: !_sending,
            errorText: _phoneError,
          ),
          const SizedBox(height: IviaSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 20,
                color: IviaColors.textSecondary,
              ),
              const SizedBox(width: IviaSpacing.sm),
              Expanded(
                child: Text(
                  'Paiement sécurisé. Vous validez sur votre téléphone avec '
                  'votre code secret.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: IviaColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Carte d'un opérateur, une seule choisie (bouton radio).
class _OperatorCard extends StatelessWidget {
  const _OperatorCard({
    required this.operator,
    required this.selected,
    required this.onTap,
  });

  final PaymentOperator operator;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    final label = operatorLabel(operator);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: IviaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IviaRadius.large),
          side: BorderSide(
            color: selected ? brand.action : IviaColors.surface,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(IviaSpacing.lg),
            child: Row(
              children: [
                // Pas de logo d'opérateur : une initiale sur fond neutre.
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: IviaColors.background,
                    borderRadius: BorderRadius.circular(IviaRadius.button),
                  ),
                  child: Text(
                    label[0],
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: IviaColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: IviaSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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
          ),
        ),
      ),
    );
  }
}
