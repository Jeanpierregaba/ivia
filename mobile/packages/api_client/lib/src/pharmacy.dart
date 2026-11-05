part of 'client.dart';

// Alerte médicament (spec 029, maquettes P01 à P14) : appels de l'app acheteur.

int _i(Object? v) => (v as num?)?.toInt() ?? 0;
DateTime? _d(Object? v) => v == null ? null : DateTime.parse(v as String);
List<Map<String, dynamic>> _list(Object? v) => [
  for (final e in (v as List? ?? const [])) e as Map<String, dynamic>,
];

/// Pharmacie de garde à proximité (`GET /v1/pharmacies/on-duty`).
class OnDutyPharmacy {
  OnDutyPharmacy.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      phone = j['phone'] as String? ?? '',
      addressText = j['address_text'] as String? ?? '',
      distanceM = _i(j['distance_m']),
      isOpen = j['is_open'] as bool? ?? false,
      onDuty = j['on_duty'] as bool? ?? false,
      dutyUntil = _d(j['duty_until']),
      location = GeoPoint.fromJson(j['location'] as Map<String, dynamic>);

  final String id, name, phone, addressText;
  final int distanceM;
  final bool isOpen, onDuty;
  final DateTime? dutyUntil;
  final GeoPoint location;
}

/// Médicament de la base (autocomplétion).
class MedicineHit {
  MedicineHit.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      dosage = j['dosage'] as String? ?? '',
      form = j['form'] as String? ?? '';

  final String id, name, dosage, form;

  String get label => [name, dosage].where((s) => s.isNotEmpty).join(' ');
}

/// Produit demandé dans une alerte.
class MedItemDraft {
  MedItemDraft({
    required this.name,
    this.medicineId,
    this.form = '',
    this.quantity = 1,
  });

  final String? medicineId;
  final String name;
  String form;
  int quantity;

  Map<String, dynamic> toJson() => {
    'medicine_id': ?medicineId,
    'name': name,
    'form': form,
    'quantity': quantity,
  };
}

/// Rayons proposés avant l'envoi, avec le nombre de pharmacies joignables.
class AlertPreview {
  AlertPreview.fromJson(Map<String, dynamic> j)
    : defaultRadiusM = _i(j['default_radius_m']),
      radii = [
        for (final r in _list(j['radii']))
          (radiusM: _i(r['radius_m']), pharmacies: _i(r['pharmacies'])),
      ],
      unlockFeeXof = _i(j['unlock_fee_xof']),
      responseWindowMinutes = _i(j['response_window_minutes']),
      pickupHoldMinutes = _i(j['pickup_hold_minutes']),
      photoRetentionHours = _i(j['photo_retention_hours']);

  final int defaultRadiusM;
  final List<({int radiusM, int pharmacies})> radii;
  final int unlockFeeXof,
      responseWindowMinutes,
      pickupHoldMinutes,
      photoRetentionHours;
}

class MedItem {
  MedItem.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String,
      form = j['form'] as String? ?? '',
      quantity = _i(j['quantity']);

  final String name, form;
  final int quantity;
}

class MedLine {
  MedLine.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String,
      quantity = _i(j['quantity']),
      unitPriceXof = _i(j['unit_price_xof']),
      lineTotalXof = _i(j['line_total_xof']),
      available = j['available'] as bool? ?? false,
      prescriptionRequired = j['prescription_required'] as bool? ?? false;

  final String name;
  final int quantity, unitPriceXof, lineTotalXof;
  final bool available, prescriptionRequired;
}

/// Pharmacie révélée après le déblocage.
class MedPharmacy {
  MedPharmacy.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String? ?? '',
      phone = j['phone'] as String? ?? '',
      addressText = j['address_text'] as String? ?? '',
      location = j['location'] == null
          ? null
          : GeoPoint.fromJson(j['location'] as Map<String, dynamic>);

  final String name, phone, addressText;
  final GeoPoint? location;
}

/// Réponse d'une pharmacie (anonyme tant qu'elle n'est pas débloquée).
class MedResponse {
  MedResponse.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      rank = _i(j['rank']),
      label = j['label'] as String? ?? '',
      distanceM = _i(j['distance_m']),
      lines = [for (final l in _list(j['lines'])) MedLine.fromJson(l)],
      availableCount = _i(j['available_count']),
      lineCount = _i(j['line_count']),
      allAvailable = j['all_available'] as bool? ?? false,
      totalXof = _i(j['total_xof']),
      prescriptionRequired = j['prescription_required'] as bool? ?? false,
      note = j['note'] as String? ?? '',
      status = j['status'] as String? ?? '',
      unlocked = j['unlocked'] as bool? ?? false,
      reservationId = j['reservation_id'] as String?,
      respondedAt = _d(j['responded_at']) ?? DateTime.now(),
      pharmacy = j['pharmacy'] == null
          ? null
          : MedPharmacy.fromJson(j['pharmacy'] as Map<String, dynamic>);

  final String id, label, note, status;
  final int rank, distanceM, availableCount, lineCount, totalXof;
  final List<MedLine> lines;
  final bool allAvailable, prescriptionRequired, unlocked;
  final String? reservationId;
  final DateTime respondedAt;
  final MedPharmacy? pharmacy;
}

/// Alerte médicament (`GET /v1/medicine-alerts/{id}`).
class MedAlert {
  MedAlert.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      items = [for (final i in _list(j['items'])) MedItem.fromJson(i)],
      photoCount = _list(j['photos']).length,
      note = j['note'] as String? ?? '',
      genericAccepted = j['generic_accepted'] as bool? ?? false,
      status = j['status'] as String,
      radiusM = _i(j['radius_m']),
      searchEndsAt = DateTime.parse(j['search_ends_at'] as String),
      notified = _i((j['stats'] as Map?)?['notified']),
      seen = _i((j['stats'] as Map?)?['seen']),
      responded = _i((j['stats'] as Map?)?['responded']),
      unlockFeeXof = _i(j['unlock_fee_xof']),
      responses = [
        for (final r in _list(j['responses'])) MedResponse.fromJson(r),
      ],
      createdAt = DateTime.parse(j['created_at'] as String);

  final String id, note, status;
  final List<MedItem> items;
  final int photoCount, radiusM, notified, seen, responded, unlockFeeXof;
  final bool genericAccepted;
  final DateTime searchEndsAt, createdAt;
  final List<MedResponse> responses;

  /// Recherche en cours (fenêtre de réponse ouverte).
  bool get searching => status == 'searching' || status == 'answered';

  String get title => items.isEmpty
      ? 'Ordonnance en photo'
      : items.length == 1
      ? items.first.name
      : '${items.first.name} + ${items.length - 1}';
}

/// Paiement d'un déblocage ou d'une commande pharmacie.
class MedPayment {
  MedPayment.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      status = j['status'] as String,
      amountXof = _i(j['amount_xof']),
      operator = j['operator'] as String? ?? '',
      phoneMasked = j['phone_masked'] as String? ?? '',
      failureReason = j['failure_reason'] as String? ?? '',
      instructions = j['instructions'] as String? ?? '',
      reservationId = j['reservation_id'] as String?;

  final String id, status, operator, phoneMasked, failureReason, instructions;
  final int amountXof;
  final String? reservationId;

  bool get pending => status == 'pending';
  bool get succeeded => status == 'succeeded';
}

class UnlockResult {
  UnlockResult.fromJson(Map<String, dynamic> j)
    : alert = MedAlert.fromJson(j['alert'] as Map<String, dynamic>),
      payment = j['payment'] == null
          ? null
          : MedPayment.fromJson(j['payment'] as Map<String, dynamic>),
      reservationId = j['reservation_id'] as String?;

  final MedAlert alert;
  final MedPayment? payment;
  final String? reservationId;
}

class MedCourier {
  MedCourier.fromJson(Map<String, dynamic> j)
    : firstName = j['first_name'] as String? ?? '',
      phone = j['phone'] as String? ?? '',
      vehicleType = j['vehicle_type'] as String? ?? '',
      vehiclePlate = j['vehicle_plate'] as String? ?? '';

  final String firstName, phone, vehicleType, vehiclePlate;
}

/// Réservation créée au déblocage (`GET /v1/medicine-reservations/{id}`).
class MedReservation {
  MedReservation.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      number = j['number'] as String? ?? '',
      alertId = j['alert_id'] as String,
      fulfillment = j['fulfillment'] as String? ?? 'pickup',
      status = j['status'] as String,
      lines = [for (final l in _list(j['lines'])) MedLine.fromJson(l)],
      itemsXof = _i(j['items_xof']),
      deliveryFeeXof = _i(j['delivery_fee_xof']),
      totalXof = _i(j['total_xof']),
      payInApp = j['pay_in_app'] as bool? ?? false,
      prescriptionRequired = j['prescription_required'] as bool? ?? false,
      handoverCode = j['handover_code'] as String? ?? '',
      expiresAt = _d(j['expires_at']),
      courierOffersSent = _i(j['courier_offers_sent']),
      distanceM = _i(j['distance_m']),
      walkMinutes = _i(j['walk_minutes']),
      deliveryAddress = j['delivery_address'] as String? ?? '',
      deliveryEtaMinutes = (j['delivery_eta_minutes'] as num?)?.toInt(),
      cancelReason = j['cancel_reason'] as String? ?? '',
      pharmacy = MedPharmacy.fromJson(
        j['pharmacy'] as Map<String, dynamic>? ?? const {},
      ),
      courier = j['courier'] == null
          ? null
          : MedCourier.fromJson(j['courier'] as Map<String, dynamic>),
      paidAt = _d((j['timeline'] as Map?)?['paid_at']),
      preparedAt = _d((j['timeline'] as Map?)?['prepared_at']),
      pickedUpAt = _d((j['timeline'] as Map?)?['picked_up_at']),
      deliveredAt = _d((j['timeline'] as Map?)?['delivered_at']);

  final String id, number, alertId, fulfillment, status, handoverCode;
  final String deliveryAddress, cancelReason;
  final List<MedLine> lines;
  final int itemsXof, deliveryFeeXof, totalXof, courierOffersSent;
  final int distanceM, walkMinutes;
  final int? deliveryEtaMinutes;
  final bool payInApp, prescriptionRequired;
  final DateTime? expiresAt, paidAt, preparedAt, pickedUpAt, deliveredAt;
  final MedPharmacy pharmacy;
  final MedCourier? courier;

  bool get delivery => fulfillment == 'delivery';
  bool get finished =>
      status == 'completed' || status == 'expired' || status == 'cancelled';
}

class MedDeliveryQuote {
  MedDeliveryQuote.fromJson(Map<String, dynamic> j)
    : distanceM = _i(j['distance_m']),
      deliveryFeeXof = _i(j['delivery_fee_xof']),
      itemsXof = _i(j['items_xof']),
      totalXof = _i(j['total_xof']),
      etaMinutes = _i(j['eta_minutes']);

  final int distanceM, deliveryFeeXof, itemsXof, totalXof, etaMinutes;
}

/// Adresse de livraison du carnet (`/v1/me/addresses`).
class BuyerAddress {
  BuyerAddress.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      label = j['label'] as String? ?? '',
      addressText = j['address_text'] as String? ?? '',
      location = GeoPoint.fromJson(j['location'] as Map<String, dynamic>);

  final String id, label, addressText;
  final GeoPoint location;
}

/// Appels de l'alerte médicament.
extension PharmacyApi on IviaApiClient {
  Map<String, String> _at(GeoPoint p) => {'lat': '${p.lat}', 'lng': '${p.lng}'};

  Future<List<OnDutyPharmacy>> onDutyPharmacies(
    GeoPoint at, {
    int limit = 5,
  }) async {
    final j = await _send(
      'GET',
      '/v1/pharmacies/on-duty',
      query: {..._at(at), 'limit': '$limit'},
    );
    return [for (final i in _list(j['items'])) OnDutyPharmacy.fromJson(i)];
  }

  Future<List<MedicineHit>> searchMedicines(String q) async {
    final j = await _send('GET', '/v1/medicines', query: {'q': q.trim()});
    return [for (final i in _list(j['items'])) MedicineHit.fromJson(i)];
  }

  Future<AlertPreview> alertPreview(GeoPoint at) async => AlertPreview.fromJson(
    await _send('GET', '/v1/medicine-alerts/preview', query: _at(at)),
  );

  Future<MedAlert> createAlert({
    required List<MedItemDraft> items,
    required List<({String kind, String objectKey})> photos,
    required int radiusM,
    required GeoPoint location,
    bool genericAccepted = false,
    String note = '',
  }) async => MedAlert.fromJson(
    await _send(
      'POST',
      '/v1/medicine-alerts',
      data: {
        'items': [for (final i in items) i.toJson()],
        'photos': [
          for (final p in photos) {'kind': p.kind, 'object_key': p.objectKey},
        ],
        'radius_m': radiusM,
        'location': {'lat': location.lat, 'lng': location.lng},
        'generic_accepted': genericAccepted,
        'note': note,
      },
    ),
  );

  Future<MedAlert> medAlert(String id) async =>
      MedAlert.fromJson(await _send('GET', '/v1/medicine-alerts/$id'));

  Future<List<MedAlert>> myAlerts() async {
    final j = await _send('GET', '/v1/medicine-alerts', query: {'limit': '20'});
    return [for (final i in _list(j['items'])) MedAlert.fromJson(i)];
  }

  Future<MedAlert> cancelAlert(String id) async =>
      MedAlert.fromJson(await _send('POST', '/v1/medicine-alerts/$id/cancel'));

  Future<MedAlert> relaunchAlert(String id, int radiusM) async =>
      MedAlert.fromJson(
        await _send(
          'POST',
          '/v1/medicine-alerts/$id/relaunch',
          data: {'radius_m': radiusM},
        ),
      );

  /// Débloque une pharmacie (forfait payé par Mobile Money).
  Future<UnlockResult> unlockResponse(
    String alertId,
    String responseId, {
    required PaymentOperator operator,
    required String phone,
  }) async => UnlockResult.fromJson(
    await _send(
      'POST',
      '/v1/medicine-alerts/$alertId/responses/$responseId/unlock',
      data: {'operator': operator.code, 'phone': phone},
    ),
  );

  Future<MedPayment> medPayment(String id) async =>
      MedPayment.fromJson(await _send('GET', '/v1/medicine-payments/$id'));

  Future<MedReservation> medReservation(String id) async =>
      MedReservation.fromJson(
        await _send('GET', '/v1/medicine-reservations/$id'),
      );

  Future<MedDeliveryQuote> medDeliveryQuote(
    String id,
    String addressId,
  ) async => MedDeliveryQuote.fromJson(
    await _send(
      'GET',
      '/v1/medicine-reservations/$id/delivery-quote',
      query: {'address_id': addressId},
    ),
  );

  /// Livreur ivia : la recherche du livreur démarre.
  Future<MedReservation> chooseMedDelivery(String id, String addressId) async =>
      MedReservation.fromJson(
        await _send(
          'POST',
          '/v1/medicine-reservations/$id/delivery',
          data: {'address_id': addressId},
        ),
      );

  Future<MedReservation> chooseMedPickup(String id) async =>
      MedReservation.fromJson(
        await _send('POST', '/v1/medicine-reservations/$id/pickup'),
      );

  /// Livreur trouvé : produits et livraison payés dans l'app.
  Future<MedPayment> payMedReservation(
    String id, {
    required PaymentOperator operator,
    required String phone,
  }) async => MedPayment.fromJson(
    await _send(
      'POST',
      '/v1/medicine-reservations/$id/pay',
      data: {'operator': operator.code, 'phone': phone},
    ),
  );

  Future<MedReservation> cancelMedReservation(String id) async =>
      MedReservation.fromJson(
        await _send(
          'POST',
          '/v1/medicine-reservations/$id/cancel',
          data: {'reason': 'Annulée par le client'},
        ),
      );

  /// Développement seulement : valide un paiement du faux prestataire.
  Future<void> devSimulateMedPayment(String id, {bool success = true}) => _send(
    'POST',
    '/v1/dev/medicine-payments/$id/simulate',
    data: {'outcome': success ? 'succeeded' : 'failed'},
  );

  /// Développement seulement : les pharmacies de démonstration répondent.
  Future<void> devAutoRespond(String alertId) =>
      _send('POST', '/v1/dev/medicine-alerts/$alertId/auto-respond');

  Future<List<BuyerAddress>> addresses() async {
    final j = await _send('GET', '/v1/me/addresses');
    return [for (final i in _list(j['items'])) BuyerAddress.fromJson(i)];
  }

  Future<BuyerAddress> createAddress({
    required String label,
    required String addressText,
    required GeoPoint location,
  }) async => BuyerAddress.fromJson(
    await _send(
      'POST',
      '/v1/me/addresses',
      data: {
        'label': label,
        'address_text': addressText,
        'location': {'lat': location.lat, 'lng': location.lng},
      },
    ),
  );
}
