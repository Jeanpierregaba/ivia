part of 'client.dart';

// Ivia Business : espaces par secteur, dossier, compte de versement, code PIN, session.

const businessSectorLabels = {
  'shop': 'Boutique',
  'real_estate': 'Immobilier',
  'artisan': 'Artisan',
  'restaurant': 'Restaurant',
};

const businessDocumentLabels = {
  'id_card': 'Pièce d\'identité',
  'selfie': 'Selfie',
  'rccm': 'RCCM',
  'business_registration': 'Registre de commerce (facultatif)',
  'trade_proof': 'Justificatif de métier (facultatif)',
  'hygiene_certificate': 'Certificat d\'hygiène (facultatif)',
};

/// Pièces proposées dans le dossier d'un secteur.
List<String> businessDocumentsOf(String sector) => switch (sector) {
  'real_estate' => const ['id_card', 'selfie', 'rccm'],
  'artisan' => const ['id_card', 'selfie', 'trade_proof'],
  'restaurant' => const ['id_card', 'selfie', 'hygiene_certificate'],
  _ => const ['id_card', 'selfie', 'business_registration'],
};

class BusinessPayout {
  BusinessPayout.fromJson(Map<String, dynamic> j)
    : operator = j['operator'] as String? ?? '',
      phoneMasked = j['phone_masked'] as String? ?? '',
      holder = j['holder'] as String? ?? '';
  final String operator, phoneMasked, holder;
}

class BusinessSpace {
  BusinessSpace.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      sector = j['sector'] as String,
      name = j['name'] as String? ?? '',
      details = (j['details'] as Map?)?.cast<String, dynamic>() ?? const {},
      logoUrl = j['logo_url'] as String?,
      photoUrls = [
        for (final u in (j['photo_urls'] as List? ?? const [])) u as String,
      ],
      shopId = j['shop_id'] as String?,
      status = j['status'] as String,
      statusReason = j['status_reason'] as String? ?? '',
      access = j['access'] as String? ?? 'correction',
      payout = j['payout'] == null
          ? null
          : BusinessPayout.fromJson(j['payout'] as Map<String, dynamic>),
      documents = [for (final d in _list(j['documents'])) d['kind'] as String],
      missingDocuments = [
        for (final k in (j['missing_documents'] as List? ?? const []))
          k as String,
      ];

  final String id, sector, name, status, statusReason, access;
  final Map<String, dynamic> details;
  final String? logoUrl, shopId;
  final List<String> photoUrls, documents, missingDocuments;
  final BusinessPayout? payout;

  String get sectorLabel => businessSectorLabels[sector] ?? sector;
  bool get usesShop => sector == 'shop' || sector == 'restaurant';
  bool get editable =>
      status == 'draft' || status == 'needs_changes' || status == 'rejected';

  String get statusLabel => switch (status) {
    'draft' => 'Dossier à terminer',
    'pending_review' => 'En attente de validation',
    'needs_changes' => 'À compléter',
    'rejected' => 'Refusé',
    'approved' => 'Actif',
    'suspended' => 'Suspendu',
    _ => status,
  };
}

class BusinessItem {
  BusinessItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String? ?? '',
      description = j['description'] as String? ?? '',
      priceXof = _i(j['price_xof']);
  final String id, title, description;
  final int priceXof;
}

extension BusinessApi on IviaApiClient {
  Future<List<BusinessSpace>> businessSpaces() async {
    final j = await _send('GET', '/v1/business/spaces');
    return [for (final i in _list(j['items'])) BusinessSpace.fromJson(i)];
  }

  Future<BusinessSpace> createBusinessSpace({
    required String sector,
    required String name,
    required Map<String, dynamic> details,
  }) async => BusinessSpace.fromJson(
    await _send(
      'POST',
      '/v1/business/spaces',
      data: {'sector': sector, 'name': name, 'details': details},
    ),
  );

  Future<BusinessSpace> updateBusinessSpace(
    String id, {
    required String sector,
    required String name,
    required Map<String, dynamic> details,
  }) async => BusinessSpace.fromJson(
    await _send(
      'PUT',
      '/v1/business/spaces/$id',
      data: {'sector': sector, 'name': name, 'details': details},
    ),
  );

  Future<BusinessSpace> addBusinessDocument(
    String id,
    String kind,
    String objectKey,
  ) async => BusinessSpace.fromJson(
    await _send(
      'POST',
      '/v1/business/spaces/$id/documents',
      data: {'kind': kind, 'object_key': objectKey},
    ),
  );

  Future<BusinessSpace> setBusinessPayout(
    String id, {
    required String operator,
    required String phone,
    required String holder,
    String pin = '',
  }) async => BusinessSpace.fromJson(
    await _send(
      'PUT',
      '/v1/business/spaces/$id/payout',
      data: {
        'operator': operator,
        'phone': phone,
        'holder': holder,
        'pin': pin,
      },
    ),
  );

  Future<BusinessSpace> submitBusinessSpace(String id) async =>
      BusinessSpace.fromJson(
        await _send('POST', '/v1/business/spaces/$id/submit'),
      );

  /// Lie la session à l'espace choisi.
  Future<BusinessSpace> openBusinessSpace(String id) async =>
      BusinessSpace.fromJson(
        await _send('POST', '/v1/business/spaces/$id/open'),
      );

  /// Espace ouvert par la session ; `null` s'il n'y en a pas.
  Future<BusinessSpace?> openedBusinessSpace() async {
    final j = await _send('GET', '/v1/business/session');
    final space = j['space'];
    return space == null
        ? null
        : BusinessSpace.fromJson(space as Map<String, dynamic>);
  }

  Future<void> closeBusinessSpace() => _send('DELETE', '/v1/business/session');

  Future<List<BusinessItem>> businessItems(String spaceId) async {
    final j = await _send('GET', '/v1/business/spaces/$spaceId/items');
    return [for (final i in _list(j['items'])) BusinessItem.fromJson(i)];
  }

  Future<void> addBusinessItem(
    String spaceId, {
    required String title,
    String description = '',
    int priceXof = 0,
  }) => _send(
    'POST',
    '/v1/business/spaces/$spaceId/items',
    data: {'title': title, 'description': description, 'price_xof': priceXof},
  );

  Future<void> deleteBusinessItem(String id) =>
      _send('DELETE', '/v1/business/items/$id');

  Future<bool> businessPinIsSet() async =>
      (await _send('GET', '/v1/business/pin'))['is_set'] as bool? ?? false;

  Future<void> setBusinessPin(String pin, {String currentPin = ''}) => _send(
    'PUT',
    '/v1/business/pin',
    data: {'pin': pin, 'current_pin': currentPin},
  );
}
