import 'package:flutter/material.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

// Libellés, tons et icônes des commandes, communs aux apps acheteur et
// marchand (docs/DESIGN.md, « Libellés des statuts »).

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

/// Pastille d'un statut : libellé ([label] pour un libellé propre à l'app,
/// sinon celui de DESIGN), ton et icône.
Widget statusPill(OrderStatus s, {String? label}) => IviaStatusPill(
  label: label ?? statusLabel(s),
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
