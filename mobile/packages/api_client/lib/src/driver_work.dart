part of 'client.dart';

// Travail du livreur : disponibilité, position, propositions et missions (commandes de boutique
// et courses pharmacie).

/// Lieu d'une mission (boutique, pharmacie, client).
class MissionPlace {
  MissionPlace.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String? ?? '',
      phone = j['phone'] as String? ?? '',
      addressText = j['address_text'] as String? ?? '',
      neighborhood = j['neighborhood'] as String? ?? '',
      instructions = j['instructions'] as String? ?? '',
      location = j['location'] == null
          ? null
          : GeoPoint.fromJson(j['location'] as Map<String, dynamic>);

  final String name, phone, addressText, neighborhood, instructions;
  final GeoPoint? location;
}

/// Proposition de course (boutique ou pharmacie), à accepter avant [expiresAt].
class WorkOffer {
  WorkOffer.shop(Map<String, dynamic> j)
    : id = j['id'] as String,
      pharmacy = false,
      reference = j['order_reference'] as String? ?? '',
      from = j['shop_name'] as String? ?? '',
      fromAddress = j['shop_address'] as String? ?? '',
      toArea = j['delivery_neighborhood'] as String? ?? '',
      toPickupM = _i(j['distance_to_shop_m']),
      tripM = _i(j['shop_to_client_m']),
      earningXof = _i(j['earning_xof']),
      expiresAt = DateTime.parse(j['expires_at'] as String);

  WorkOffer.pharmacy(Map<String, dynamic> j)
    : id = j['id'] as String,
      pharmacy = true,
      reference = '',
      from = j['pharmacy_name'] as String? ?? '',
      fromAddress = j['pharmacy_address'] as String? ?? '',
      toArea = '',
      toPickupM = _i(j['distance_to_pharmacy_m']),
      tripM = _i(j['pharmacy_to_client_m']),
      earningXof = _i(j['earning_xof']),
      expiresAt = DateTime.parse(j['expires_at'] as String);

  final String id, reference, from, fromAddress, toArea;
  final bool pharmacy;
  final int toPickupM, tripM, earningXof;
  final DateTime expiresAt;
}

/// Mission en cours ou passée (boutique ou pharmacie).
class WorkMission {
  WorkMission.shop(Map<String, dynamic> j)
    : id = j['id'] as String,
      pharmacy = false,
      reference = j['order_reference'] as String? ?? '',
      status = j['status'] as String,
      feeXof = _i(j['fee_xof']),
      itemsCount = _i(j['items_count']),
      lines = const [],
      prescriptionCheck = false,
      pickup = MissionPlace.fromJson(
        j['shop'] as Map<String, dynamic>? ?? const {},
      ),
      client = j['customer'] == null
          ? null
          : MissionPlace.fromJson(j['customer'] as Map<String, dynamic>),
      assignedAt = DateTime.parse(j['assigned_at'] as String),
      arrivedPickupAt = _d(j['arrived_shop_at']),
      pickedUpAt = _d(j['picked_up_at']),
      arrivedClientAt = _d(j['arrived_customer_at']),
      deliveredAt = _d(j['delivered_at']),
      failedAt = _d(j['failed_at']),
      failureReason = j['failure_reason'] as String? ?? '',
      preparedAt = null;

  WorkMission.pharmacy(Map<String, dynamic> j)
    : id = j['id'] as String,
      pharmacy = true,
      reference = j['number'] as String? ?? '',
      status = j['status'] as String,
      feeXof = _i(j['fee_xof']),
      lines = [for (final l in _list(j['lines'])) MedLine.fromJson(l)],
      itemsCount = _list(j['lines']).length,
      prescriptionCheck = j['prescription_check_required'] as bool? ?? false,
      pickup = MissionPlace.fromJson(
        j['pharmacy'] as Map<String, dynamic>? ?? const {},
      ),
      client = j['client'] == null
          ? null
          : MissionPlace.fromJson(j['client'] as Map<String, dynamic>),
      assignedAt = DateTime.parse(j['assigned_at'] as String),
      arrivedPickupAt = null,
      pickedUpAt = _d(j['picked_up_at']),
      arrivedClientAt = null,
      deliveredAt = _d(j['delivered_at']),
      failedAt = null,
      failureReason = '',
      preparedAt = _d(j['prepared_at']);

  final String id, reference, status, failureReason;
  final bool pharmacy, prescriptionCheck;
  final int feeXof, itemsCount;
  final List<MedLine> lines;
  final MissionPlace pickup;
  final MissionPlace? client;
  final DateTime assignedAt;
  final DateTime? arrivedPickupAt,
      pickedUpAt,
      arrivedClientAt,
      deliveredAt,
      failedAt,
      preparedAt;

  bool get done =>
      deliveredAt != null ||
      failedAt != null ||
      status == 'cancelled' ||
      status == 'delivered';

  /// Course pharmacie : le client n'a pas encore payé (adresse inconnue).
  bool get awaitingPayment => pharmacy && client == null && pickedUpAt == null;
}

/// Appels du livreur.
extension DriverWorkApi on IviaApiClient {
  Future<void> setAvailability(bool online) =>
      _send('PUT', '/v1/driver/availability', data: {'online': online});

  Future<void> sendLocation(GeoPoint p) =>
      _send('POST', '/v1/driver/location', data: {'lat': p.lat, 'lng': p.lng});

  /// Proposition en attente, boutique d'abord puis pharmacie ; `null` sinon.
  Future<WorkOffer?> currentWorkOffer() async {
    final shop = (await _send('GET', '/v1/driver/offers/current'))['offer'];
    if (shop is Map<String, dynamic>) return WorkOffer.shop(shop);
    final ph = (await _send(
      'GET',
      '/v1/driver/pharmacy-offers/current',
    ))['offer'];
    if (ph is Map<String, dynamic>) return WorkOffer.pharmacy(ph);
    return null;
  }

  Future<void> acceptWorkOffer(WorkOffer o) => _send(
    'POST',
    o.pharmacy
        ? '/v1/driver/pharmacy-offers/${o.id}/accept'
        : '/v1/driver/offers/${o.id}/accept',
  );

  Future<void> declineWorkOffer(WorkOffer o) => _send(
    'POST',
    o.pharmacy
        ? '/v1/driver/pharmacy-offers/${o.id}/decline'
        : '/v1/driver/offers/${o.id}/decline',
  );

  /// Mission en cours ; `null` sinon.
  Future<WorkMission?> currentWorkMission() async {
    final shop = (await _send('GET', '/v1/driver/missions/current'))['mission'];
    if (shop is Map<String, dynamic>) return WorkMission.shop(shop);
    final ph = (await _send(
      'GET',
      '/v1/driver/pharmacy-missions/current',
    ))['mission'];
    if (ph is Map<String, dynamic>) return WorkMission.pharmacy(ph);
    return null;
  }

  /// Étape d'une mission de boutique : arrived-at-shop, picked-up, arrived-at-customer.
  Future<void> missionStep(WorkMission m, String step) => _send(
    'POST',
    m.pharmacy
        ? '/v1/driver/pharmacy-missions/${m.id}/$step'
        : '/v1/driver/missions/${m.id}/$step',
  );

  /// Remise au client avec son code (et la vérification de l'ordonnance pour une course pharmacie).
  Future<void> deliverMission(
    WorkMission m,
    String code, {
    bool prescriptionChecked = false,
  }) => m.pharmacy
      ? _send(
          'POST',
          '/v1/driver/pharmacy-missions/${m.id}/delivered',
          data: {'code': code, 'prescription_checked': prescriptionChecked},
        )
      : _send(
          'POST',
          '/v1/driver/missions/${m.id}/deliver',
          data: {'code': code},
        );

  Future<void> failMission(WorkMission m, String reason, int callAttempts) =>
      _send(
        'POST',
        '/v1/driver/missions/${m.id}/fail',
        data: {'reason': reason, 'call_attempts': callAttempts},
      );

  Future<void> withdrawMission(WorkMission m, String reason) => _send(
    'POST',
    m.pharmacy
        ? '/v1/driver/pharmacy-missions/${m.id}/withdraw'
        : '/v1/driver/missions/${m.id}/withdraw',
    data: {'reason': reason},
  );

  /// Courses passées (boutique et pharmacie), les plus récentes d'abord.
  Future<List<WorkMission>> workHistory() async {
    final shop = await _send(
      'GET',
      '/v1/driver/missions',
      query: {'limit': '50'},
    );
    final ph = await _send(
      'GET',
      '/v1/driver/pharmacy-missions',
      query: {'limit': '50'},
    );
    return [
      for (final m in _list(shop['items'])) WorkMission.shop(m),
      for (final m in _list(ph['items'])) WorkMission.pharmacy(m),
    ]..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
  }
}
