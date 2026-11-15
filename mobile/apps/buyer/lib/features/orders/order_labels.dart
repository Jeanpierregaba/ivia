import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Étapes ordinaires d'un retrait, dans l'ordre.
const _pickupPath = [
  OrderStatus.pendingPayment,
  OrderStatus.awaitingSeller,
  OrderStatus.accepted,
  OrderStatus.preparing,
  OrderStatus.readyForPickup,
  OrderStatus.completed,
];

String _stepTitle(OrderStatus s, BuyerOrder order) => switch (s) {
  OrderStatus.pendingPayment => 'Commande passée',
  OrderStatus.awaitingSeller => 'Paiement reçu',
  OrderStatus.accepted => 'Acceptée par ${order.shop.name}',
  _ => statusLabel(s),
};

/// Frise d'une commande : étapes passées avec leur heure ; pour un retrait
/// en cours, étapes à venir en gris ; une fin anormale (expirée, annulée,
/// remboursée) clôt la frise.
List<IviaTimelineStep> timelineOf(BuyerOrder order) {
  final steps = <IviaTimelineStep>[];
  final seen = <OrderStatus>{};
  for (final e in order.events) {
    if (!seen.add(e.to)) continue;
    steps.add(
      IviaTimelineStep(
        title: _stepTitle(e.to, order),
        // Les raisons sont écrites pour le back-office ; seule celle d'une
        // annulation ou d'un échec parle à l'acheteur.
        subtitle:
            e.reason.isNotEmpty &&
                (e.to == OrderStatus.cancelled ||
                    e.to == OrderStatus.deliveryFailed)
            ? e.reason
            : null,
        time: timeOfDay(e.at),
        state: IviaStepState.done,
      ),
    );
  }
  final active = order.status.isActive;
  if (active && steps.isNotEmpty) {
    final last = steps.removeLast();
    steps.add(
      IviaTimelineStep(
        title: last.title,
        subtitle: last.subtitle,
        time: last.time,
        state: IviaStepState.current,
      ),
    );
  }
  if (active && order.fulfillment == Fulfillment.pickup) {
    for (final s in _pickupPath) {
      if (!seen.contains(s)) {
        steps.add(
          IviaTimelineStep(
            title: _stepTitle(s, order),
            state: IviaStepState.upcoming,
          ),
        );
      }
    }
  }
  return steps;
}
