part of 'client.dart';

// App pharmacie : dossier, ouverture et garde, alertes reçues, réponses, réservations, solde.

/// Pharmacie du titulaire connecté.
class PharmacyProfile {
  PharmacyProfile.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String? ?? '',
      licenseNumber = j['license_number'] as String? ?? '',
      phone = j['phone'] as String? ?? '',
      addressText = j['address_text'] as String? ?? '',
      openingHours = j['opening_hours'] as String? ?? '',
      isOpen = j['is_open'] as bool? ?? false,
      onDuty = j['on_duty'] as bool? ?? false,
      open24h = j['open_24h'] as bool? ?? false,
      dutyUntil = _d(j['duty_until']),
      reviewStatus = j['review_status'] as String? ?? 'pending_review',
      reviewNote = j['review_note'] as String? ?? '',
      suspended = j['suspended_at'] != null,
      neighborhoodId = j['neighborhood_id'] as String?,
      lat = ((j['location'] as Map?)?['lat'] as num?)?.toDouble(),
      lng = ((j['location'] as Map?)?['lng'] as num?)?.toDouble(),
      payoutMasked = (j['payout'] as Map?)?['phone_masked'] as String?,
      payoutHolder = (j['payout'] as Map?)?['holder'] as String?,
      documents = [for (final d in _list(j['documents'])) d['kind'] as String],
      missingDocuments = [
        for (final k in (j['missing_documents'] as List? ?? const []))
          k as String,
      ];

  final String id,
      name,
      licenseNumber,
      phone,
      addressText,
      openingHours,
      reviewStatus,
      reviewNote;
  final bool isOpen, onDuty, open24h, suspended;
  final DateTime? dutyUntil;
  final String? neighborhoodId, payoutMasked, payoutHolder;
  final double? lat, lng;
  final List<String> documents, missingDocuments;

  bool get approved => reviewStatus == 'approved' && !suspended;
  bool get hasPayout => payoutMasked != null;

  /// Dossier encore modifiable par le titulaire.
  bool get editable =>
      reviewStatus == 'draft' ||
      reviewStatus == 'changes_requested' ||
      reviewStatus == 'rejected';
}

/// Pièce du dossier pharmacie.
const pharmacyDocumentLabels = {
  'opening_authorization': 'Autorisation d\'exercice',
  'storefront_photo': 'Photo de la devanture',
  'owner_id': 'Pièce d\'identité du titulaire',
};

class InboxPhoto {
  InboxPhoto.fromJson(Map<String, dynamic> j)
    : kind = j['kind'] as String? ?? '',
      url = j['url'] as String?;
  final String kind;
  final String? url;
}

class InboxAlertItem {
  InboxAlertItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      form = j['form'] as String? ?? '',
      quantity = _i(j['quantity']);
  final String id, name, form;
  final int quantity;
}

/// Alerte reçue par la pharmacie (le client reste anonyme).
class InboxAlert {
  InboxAlert.fromJson(Map<String, dynamic> j)
    : alertId = j['alert_id'] as String,
      items = [for (final i in _list(j['items'])) InboxAlertItem.fromJson(i)],
      photos = [for (final p in _list(j['photos'])) InboxPhoto.fromJson(p)],
      photoCount = _i(j['photo_count']),
      note = j['note'] as String? ?? '',
      genericAccepted = j['generic_accepted'] as bool? ?? false,
      distanceM = _i(j['distance_m']),
      status = j['status'] as String? ?? '',
      alertStatus = j['alert_status'] as String? ?? '',
      searchEndsAt = DateTime.parse(j['search_ends_at'] as String),
      seen = j['seen'] as bool? ?? false,
      receivedAt = DateTime.parse(j['received_at'] as String),
      myTotalXof = _i((j['my_response'] as Map?)?['total_xof']),
      myLines = [
        for (final l in _list((j['my_response'] as Map?)?['lines']))
          MedLine.fromJson(l),
      ],
      responded = j['my_response'] != null,
      unlocked = (j['my_response'] as Map?)?['unlocked'] as bool? ?? false;

  final String alertId, note, status, alertStatus;
  final List<InboxAlertItem> items;
  final List<InboxPhoto> photos;
  final int photoCount, distanceM, myTotalXof;
  final bool genericAccepted, seen, responded, unlocked;
  final DateTime searchEndsAt, receivedAt;
  final List<MedLine> myLines;

  String get title => items.isEmpty
      ? 'Ordonnance en photo'
      : items.length == 1
      ? items.first.name
      : '${items.first.name} + ${items.length - 1}';
}

/// Ligne de réponse envoyée par la pharmacie.
class ResponseLineDraft {
  ResponseLineDraft({
    this.alertItemId,
    required this.name,
    required this.quantity,
    this.unitPriceXof = 0,
    this.available = true,
    this.prescriptionRequired = false,
  });
  final String? alertItemId;
  String name;
  int quantity, unitPriceXof;
  bool available, prescriptionRequired;

  Map<String, dynamic> toJson() => {
    'alert_item_id': ?alertItemId,
    'name': name,
    'quantity': quantity,
    'unit_price_xof': unitPriceXof,
    'available': available,
    'prescription_required': prescriptionRequired,
  };
}

/// Réservation vue par la pharmacie.
class PharmacyOrder {
  PharmacyOrder.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      number = j['number'] as String? ?? '',
      fulfillment = j['fulfillment'] as String? ?? 'pickup',
      status = j['status'] as String,
      lines = [for (final l in _list(j['lines'])) MedLine.fromJson(l)],
      itemsXof = _i(j['items_xof']),
      dueXof = _i(j['pharmacy_due_xof']),
      prescriptionRequired = j['prescription_required'] as bool? ?? false,
      buyerFirstName = j['buyer_first_name'] as String? ?? '',
      expiresAt = _d(j['expires_at']),
      preparedAt = _d(j['prepared_at']),
      cancelReason = j['cancel_reason'] as String? ?? '',
      courier = j['courier'] == null
          ? null
          : MedCourier.fromJson(j['courier'] as Map<String, dynamic>),
      createdAt = DateTime.parse(j['created_at'] as String),
      completedAt = _d(j['completed_at']);

  final String id, number, fulfillment, status, buyerFirstName, cancelReason;
  final List<MedLine> lines;
  final int itemsXof, dueXof;
  final bool prescriptionRequired;
  final DateTime? expiresAt, preparedAt, completedAt;
  final DateTime createdAt;
  final MedCourier? courier;

  bool get delivery => fulfillment == 'delivery';
  bool get active => !['completed', 'expired', 'cancelled'].contains(status);
}

class PharmacyEarnings {
  PharmacyEarnings.fromJson(Map<String, dynamic> j)
    : dueXof = _i(j['due_xof']),
      paidOutXof = _i(j['paid_out_xof']),
      balanceXof = _i(j['balance_xof']),
      deliveredCount = _i(j['delivered_count']),
      pickupCount = _i(j['pickup_count']),
      payouts = [
        for (final p in _list(j['payouts']))
          (
            amountXof: _i(p['amount_xof']),
            reference: p['reference'] as String? ?? '',
            at: DateTime.parse(p['created_at'] as String),
          ),
      ];

  final int dueXof, paidOutXof, balanceXof, deliveredCount, pickupCount;
  final List<({int amountXof, String reference, DateTime at})> payouts;
}

extension PharmacistApi on IviaApiClient {
  /// Pharmacie du compte ; `null` : pas encore inscrite.
  Future<PharmacyProfile?> pharmacyMe() async {
    try {
      return PharmacyProfile.fromJson(await _send('GET', '/v1/pharmacy/me'));
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<PharmacyProfile> pharmacyApply({
    required String name,
    required String licenseNumber,
    required String phone,
    required String addressText,
    required GeoPoint location,
    String? neighborhoodId,
    String openingHours = '',
  }) async => PharmacyProfile.fromJson(
    await _send(
      'POST',
      '/v1/pharmacy/application',
      data: {
        'name': name,
        'license_number': licenseNumber,
        'phone': phone,
        'address_text': addressText,
        'location': {'lat': location.lat, 'lng': location.lng},
        'neighborhood_id': ?neighborhoodId,
        'opening_hours': openingHours,
      },
    ),
  );

  Future<void> pharmacyAddDocument(String kind, String objectKey) => _send(
    'POST',
    '/v1/pharmacy/me/documents',
    data: {'kind': kind, 'object_key': objectKey},
  );

  Future<PharmacyProfile> setPharmacyStatus({
    required bool isOpen,
    required bool onDuty,
    required bool open24h,
  }) async => PharmacyProfile.fromJson(
    await _send(
      'PUT',
      '/v1/pharmacy/me/status',
      data: {'is_open': isOpen, 'on_duty': onDuty, 'open_24h': open24h},
    ),
  );

  Future<void> setPharmacyPayout({
    required String operator,
    required String phone,
    required String holder,
  }) => _send(
    'PUT',
    '/v1/pharmacy/me/payout',
    data: {'operator': operator, 'phone': phone, 'holder': holder},
  );

  Future<void> submitPharmacy() => _send('POST', '/v1/pharmacy/me/submit');

  /// Ajoute des gardes au planning (une seule, ou un import).
  Future<void> addPharmacyDutyShifts(
    List<({DateTime startsAt, DateTime endsAt})> shifts,
  ) => _send(
    'POST',
    '/v1/pharmacy/me/duty-shifts',
    data: {
      'shifts': [
        for (final s in shifts)
          {
            'starts_at': s.startsAt.toUtc().toIso8601String(),
            'ends_at': s.endsAt.toUtc().toIso8601String(),
          },
      ],
    },
  );

  Future<void> deletePharmacyDutyShift(String id) =>
      _send('DELETE', '/v1/pharmacy/me/duty-shifts/$id');

  Future<List<({String id, DateTime startsAt, DateTime endsAt})>>
  pharmacyDutyShifts() async {
    final j = await _send('GET', '/v1/pharmacy/me/duty-shifts');
    return [
      for (final s in _list(j['items']))
        (
          id: s['id'] as String,
          startsAt: DateTime.parse(s['starts_at'] as String),
          endsAt: DateTime.parse(s['ends_at'] as String),
        ),
    ];
  }

  Future<List<InboxAlert>> pharmacyInbox({bool openOnly = true}) async {
    final j = await _send(
      'GET',
      '/v1/pharmacy/inbox',
      query: {'open_only': '$openOnly', 'limit': '50'},
    );
    return [for (final i in _list(j['items'])) InboxAlert.fromJson(i)];
  }

  /// Détail d'une alerte (marque l'alerte comme vue, photos lisibles 10 minutes).
  Future<InboxAlert> pharmacyInboxItem(String alertId) async =>
      InboxAlert.fromJson(await _send('GET', '/v1/pharmacy/inbox/$alertId'));

  Future<void> pharmacyRespond(
    String alertId,
    List<ResponseLineDraft> lines, {
    String note = '',
  }) => _send(
    'POST',
    '/v1/pharmacy/inbox/$alertId/respond',
    data: {
      'lines': [for (final l in lines) l.toJson()],
      'note': note,
    },
  );

  Future<void> pharmacyDecline(String alertId) =>
      _send('POST', '/v1/pharmacy/inbox/$alertId/decline');

  Future<List<PharmacyOrder>> pharmacyOrders({bool activeOnly = false}) async {
    final j = await _send(
      'GET',
      '/v1/pharmacy/reservations',
      query: {'active_only': '$activeOnly', 'limit': '50'},
    );
    return [for (final i in _list(j['items'])) PharmacyOrder.fromJson(i)];
  }

  Future<PharmacyOrder> pharmacyOrder(String id) async =>
      PharmacyOrder.fromJson(
        await _send('GET', '/v1/pharmacy/reservations/$id'),
      );

  Future<void> pharmacyMarkPrepared(String id) =>
      _send('POST', '/v1/pharmacy/reservations/$id/prepared');

  Future<void> pharmacyCompletePickup(String id, String code) => _send(
    'POST',
    '/v1/pharmacy/reservations/$id/complete',
    data: {'code': code},
  );

  Future<void> pharmacyCancelOrder(String id, String reason) => _send(
    'POST',
    '/v1/pharmacy/reservations/$id/cancel',
    data: {'reason': reason},
  );

  Future<PharmacyEarnings> pharmacyEarnings() async =>
      PharmacyEarnings.fromJson(await _send('GET', '/v1/pharmacy/earnings'));
}
