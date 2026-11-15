import 'package:flutter/material.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Annulation possible par l'acheteur : avant le paiement, ou payée tant
/// que la boutique n'a pas accepté (comme le serveur).
bool canCancel(BuyerOrder order) =>
    order.status == OrderStatus.pendingPayment ||
    order.status == OrderStatus.awaitingSeller;

/// Remboursement annoncé pour une commande payée : total de la commande.
String refundNotice(BuyerOrder order) =>
    'Vous serez remboursé de ${formatXof(order.totalXof)} sur votre compte '
    'Mobile Money.';

/// « Annuler la commande #N ? » ; `true` : l'acheteur confirme.
Future<bool> showCancelSheet(BuildContext context, BuyerOrder order) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Annuler la commande #${order.number} ?',
                style: textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(
              order.paidAt != null
                  ? refundNotice(order)
                  : 'Vos produits seront libérés.',
              style: textTheme.bodyLarge?.copyWith(
                color: IviaColors.textSecondary,
              ),
            ),
            const SizedBox(height: IviaSpacing.xxl),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: IviaColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Annuler la commande'),
            ),
            const SizedBox(height: IviaSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Garder ma commande'),
            ),
          ],
        ),
      );
    },
  );
  return confirmed ?? false;
}
