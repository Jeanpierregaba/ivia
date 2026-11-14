part of 'client.dart';

// Suivi en direct d'une livraison (spec 036) : livreur, étape de la course.

/// Étape de la course, vue par le client et le marchand.
enum DeliveryStep {
  accepted('Livreur trouvé'),
  headingToShop('En route vers la boutique'),
  atShop('Arrivé à la boutique'),
  headingToCustomer('En route vers le client'),
  atCustomer('Arrivé chez le client'),
  delivered('Livrée'),
  returning('Retour à la boutique'),
  ended('Terminée');

  const DeliveryStep(this.label);
  final String label;

  static DeliveryStep parse(String? code) => switch (code) {
    'heading_to_shop' => headingToShop,
    'at_shop' => atShop,
    'heading_to_customer' => headingToCustomer,
    'at_customer' => atCustomer,
    'delivered' => delivered,
    'returning' => returning,
    'ended' => ended,
    _ => accepted,
  };

  /// Le livreur se déplace : sa position est suivie sur la carte.
  bool get moving =>
      this == accepted ||
      this == headingToShop ||
      this == atShop ||
      this == headingToCustomer ||
      this == atCustomer;
}

/// Livreur d'une commande et étape de sa course.
class OrderDelivery {
  OrderDelivery.fromJson(Map<String, dynamic> j)
    : driverFirstName = j['driver_first_name'] as String? ?? '',
      vehicleType = j['vehicle_type'] as String? ?? 'motorbike',
      vehiclePlate = j['vehicle_plate'] as String? ?? '',
      step = DeliveryStep.parse(j['step'] as String?),
      assignedAt = _d(j['assigned_at']),
      startedAt = _d(j['started_at']),
      arrivedShopAt = _d(j['arrived_shop_at']),
      pickedUpAt = _d(j['picked_up_at']),
      arrivedCustomerAt = _d(j['arrived_customer_at']),
      deliveredAt = _d(j['delivered_at']);

  final String driverFirstName, vehicleType, vehiclePlate;
  final DeliveryStep step;
  final DateTime? assignedAt, startedAt, arrivedShopAt, pickedUpAt;
  final DateTime? arrivedCustomerAt, deliveredAt;
}

extension DeliveryLiveApi on IviaApiClient {
  /// Livreur de la commande de l'acheteur ; `null` : pas encore de livreur.
  Future<OrderDelivery?> orderDelivery(String orderId) async {
    final j = await _send('GET', '/v1/orders/$orderId/delivery');
    final d = j['delivery'];
    return d is Map<String, dynamic> ? OrderDelivery.fromJson(d) : null;
  }

  /// Livreur d'une commande de la boutique du marchand.
  Future<OrderDelivery?> sellerOrderDelivery(String orderId) async {
    final j = await _send('GET', '/v1/seller/orders/$orderId/delivery');
    final d = j['delivery'];
    return d is Map<String, dynamic> ? OrderDelivery.fromJson(d) : null;
  }
}
