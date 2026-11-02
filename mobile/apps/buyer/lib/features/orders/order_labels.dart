import 'package:flutter/material.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Libellé d'un statut (docs/DESIGN.md, « Libellés des statuts »).
String statusLabel(OrderStatus s) => switch (s) {
  OrderStatus.pendingPayment => 'En attente de paiement',
  OrderStatus.expired => 'Paiement expiré',
  OrderStatus.awaitingSeller => 'En attente de la boutique',
  OrderStatus.accepted => 'Acceptée par la boutique',
  OrderStatus.preparing => 'En préparation',
  OrderStatus.readyForPickup => 'Prête à retirer',
  OrderStatus.completed => 'Retirée',
  OrderStatus.awaitingDriver => 'Recherche d’un livreur',
  OrderStatus.driverAssigned => 'Livreur en route vers la boutique',
  OrderStatus.pickedUp => 'En cours de livraison',
  OrderStatus.delivered => 'Livrée',
  OrderStatus.deliveryFailed => 'Livraison échouée',
  OrderStatus.returnedToShop => 'Retournée à la boutique',
  OrderStatus.cancelled => 'Annulée',
  OrderStatus.refunded => 'Remboursée',
  OrderStatus.unknown => 'En cours',
};

/// Ton de la pastille d'un statut.
IviaPillTone statusTone(OrderStatus s) => switch (s) {
  OrderStatus.pendingPayment ||
  OrderStatus.awaitingSeller => IviaPillTone.warning,
  OrderStatus.readyForPickup ||
  OrderStatus.completed ||
  OrderStatus.delivered => IviaPillTone.success,
  OrderStatus.cancelled || OrderStatus.deliveryFailed => IviaPillTone.error,
  OrderStatus.expired ||
  OrderStatus.returnedToShop ||
  OrderStatus.refunded => IviaPillTone.neutral,
  _ => IviaPillTone.info,
};

/// Icône d'un statut : jamais la couleur seule.
IconData statusIcon(OrderStatus s) => switch (s) {
  OrderStatus.pendingPayment => Icons.schedule,
  OrderStatus.expired => Icons.timer_off_outlined,
  OrderStatus.awaitingSeller => Icons.hourglass_empty,
  OrderStatus.accepted => Icons.thumb_up_alt_outlined,
  OrderStatus.preparing => Icons.inventory_2_outlined,
  OrderStatus.readyForPickup => Icons.storefront_outlined,
  OrderStatus.completed || OrderStatus.delivered => Icons.check_circle_outline,
  OrderStatus.awaitingDriver ||
  OrderStatus.driverAssigned ||
  OrderStatus.pickedUp => Icons.local_shipping_outlined,
  OrderStatus.deliveryFailed || OrderStatus.cancelled => Icons.cancel_outlined,
  OrderStatus.returnedToShop => Icons.undo,
  OrderStatus.refunded => Icons.currency_exchange,
  OrderStatus.unknown => Icons.help_outline,
};

/// Pastille d'un statut : libellé, ton et icône.
Widget statusPill(OrderStatus s) => IviaStatusPill(
  label: statusLabel(s),
  tone: statusTone(s),
  icon: statusIcon(s),
);

/// « Retrait » ou « Livraison ».
String fulfillmentLabel(Fulfillment f) => switch (f) {
  Fulfillment.pickup => 'Retrait',
  Fulfillment.delivery => 'Livraison',
};

/// « 3 articles ».
String articles(int count) => '$count article${count > 1 ? 's' : ''}';

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
        subtitle: e.reason.isEmpty ? null : e.reason,
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
