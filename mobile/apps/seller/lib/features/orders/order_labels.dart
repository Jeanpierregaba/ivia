import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

/// Onglets de la liste des commandes, dans l'ordre d'affichage.
enum OrderTab {
  /// À accepter ou refuser (`awaiting_seller`).
  fresh('new', 'Nouvelles'),

  /// Acceptées, en préparation, prêtes, en livraison.
  active('active', 'En cours'),

  /// Retirées, livrées, annulées, remboursées…
  done('done', 'Terminées');

  const OrderTab(this.code, this.label);

  /// Valeur du paramètre `tab` de l'URL.
  final String code;
  final String label;

  static OrderTab parse(String? code) =>
      values.firstWhere((t) => t.code == code, orElse: () => fresh);
}

/// Onglet d'une commande selon son statut.
OrderTab tabOf(OrderStatus s) => switch (s) {
  OrderStatus.awaitingSeller => OrderTab.fresh,
  OrderStatus.accepted ||
  OrderStatus.preparing ||
  OrderStatus.readyForPickup ||
  OrderStatus.awaitingDriver ||
  OrderStatus.driverAssigned ||
  OrderStatus.pickedUp ||
  // Statut ajouté au serveur depuis : gardé visible.
  OrderStatus.unknown => OrderTab.active,
  _ => OrderTab.done,
};

/// Libellé d'un statut côté marchand ; le reste comme DESIGN.
String sellerStatusLabel(OrderStatus s) => switch (s) {
  OrderStatus.awaitingSeller => 'Nouvelle',
  OrderStatus.accepted => 'Acceptée',
  _ => statusLabel(s),
};
