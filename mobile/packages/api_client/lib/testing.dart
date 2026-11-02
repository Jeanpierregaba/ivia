/// Faux serveur et réponses types, pour les tests des apps et de ce paquet.
/// À n'importer que depuis `test/`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'src/models.dart';

/// Requête reçue par le [FakeApiServer].
class RecordedRequest {
  const RecordedRequest(
    this.method,
    this.path,
    this.headers,
    this.body, {
    this.host = '',
    this.query = const {},
  });

  final String method;
  final String path;

  /// Hôte appelé (l'API, ou le stockage pour une URL signée).
  final String host;

  /// Paramètres de l'URL.
  final Map<String, String> query;

  /// En-têtes, noms en minuscules.
  final Map<String, String> headers;

  /// JSON décodé, ou octets bruts (envoi de fichier).
  final Object? body;
}

/// Réponse du [FakeApiServer].
class FakeResponse {
  const FakeResponse._(this.status, this.body, {this.network = false});

  factory FakeResponse.json(int status, Object? body) =>
      FakeResponse._(status, body);

  /// Erreur au format commun du backend.
  factory FakeResponse.error(
    int status,
    String code,
    String message, {
    Map<String, String>? fields,
  }) => FakeResponse._(status, {
    'error': {'code': code, 'message': message, 'fields': ?fields},
  });

  /// Coupure réseau : aucune réponse.
  factory FakeResponse.networkError() =>
      const FakeResponse._(0, null, network: true);

  final int status;
  final Object? body;
  final bool network;
}

typedef FakeHandler = FutureOr<FakeResponse> Function(RecordedRequest request);

/// Remplace le réseau de dio : chaque route a son handler, les requêtes sont
/// enregistrées. Une route inconnue répond 404.
class FakeApiServer implements HttpClientAdapter {
  final requests = <RecordedRequest>[];
  final _handlers = <String, FakeHandler>{};
  final _patterns = <(String, RegExp, FakeHandler)>[];

  void on(String method, String path, FakeHandler handler) =>
      _handlers['$method $path'] = handler;

  /// Route à identifiant : [pattern] doit couvrir tout le chemin. Les routes
  /// exactes de [on] passent avant.
  void onPattern(String method, String pattern, FakeHandler handler) =>
      _patterns.add((method, RegExp('^$pattern\$'), handler));

  RecordedRequest get last => requests.last;

  /// Heure du serveur, envoyée dans l'en-tête `Date` des réponses ; aucun
  /// en-tête si `null`.
  DateTime Function()? clock;

  Iterable<RecordedRequest> calls(String method, String path) =>
      requests.where((r) => r.method == method && r.path == path);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? body;
    if (requestStream != null) {
      final bytes = await requestStream.expand((chunk) => chunk).toList();
      if (bytes.isNotEmpty) {
        try {
          body = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          body = bytes;
        }
      }
    }
    final request = RecordedRequest(
      options.method,
      options.uri.path,
      options.headers.map((k, v) => MapEntry(k.toLowerCase(), '$v')),
      body,
      host: options.uri.host,
      query: options.uri.queryParameters,
    );
    requests.add(request);

    final handler =
        _handlers['${request.method} ${request.path}'] ??
        _patterns
            .where((p) => p.$1 == request.method && p.$2.hasMatch(request.path))
            .map((p) => p.$3)
            .firstOrNull;
    final response = handler == null
        ? FakeResponse.error(404, 'not_found', 'Introuvable.')
        : await handler(request);
    if (response.network) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'réseau simulé coupé',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(response.body),
      response.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (clock case final now?) 'date': [_httpDate(now())],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _httpDate(DateTime date) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = date.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[d.weekday - 1]}, ${two(d.day)} ${months[d.month - 1]} '
      '${d.year} ${two(d.hour)}:${two(d.minute)}:${two(d.second)} GMT';
}

/// Réponse type de `POST /v1/auth/otp`.
const otpBody = {
  'channel': 'email',
  'expires_in_seconds': 600,
  'resend_after_seconds': 60,
};

/// Profil type (schéma `User`).
Map<String, dynamic> userBody({
  bool complete = false,
  String email = 'awa@test.tg',
}) => {
  'id': '7d5c1d38-3c1b-4b8f-9a77-1f2e3d4c5b6a',
  'email': email,
  'phone': complete ? '+22890123456' : null,
  'first_name': complete ? 'Awa' : '',
  'last_name': complete ? 'Mensah' : '',
  'roles': ['buyer'],
  'privacy_consent_at': complete ? '2026-10-31T09:00:00Z' : null,
  'profile_complete': complete,
  'created_at': '2026-10-31T08:00:00Z',
};

/// Session type (schéma `Session`).
Map<String, dynamic> sessionBody({bool complete = false}) => {
  'token': 'jeton-secret',
  'expires_at': '2026-12-30T08:00:00Z',
  'is_new_user': !complete,
  'user': userBody(complete: complete),
};

/// Commande vue par le marchand (schéma `SellerOrder`) : retrait de
/// 2 × Pagne wax à 4 500 F et 1 × Savon noir à 1 500 F (stock non suivi),
/// payée à [paidAt], à accepter avant [paidAt] + 15 min.
Map<String, dynamic> sellerOrderBody({
  String id = 'o1',
  int number = 1042,
  String shopId = 's1',
  String status = 'awaiting_seller',
  String fulfillment = 'pickup',
  String buyerFirstName = 'Koffi',
  DateTime? paidAt,
  DateTime? updatedAt,
  String cancelReason = '',
  int handoverAttempts = 0,
  List<Map<String, dynamic>>? items,
}) {
  final paid = (paidAt ?? DateTime.utc(2026, 11, 2, 14)).toUtc();
  final lines =
      items ??
      [
        orderItemBody('p1', 'Pagne wax', 4500, 2),
        orderItemBody('p2', 'Savon noir', 1500, 1, stockMode: 'untracked'),
      ];
  final subtotal = lines.fold<int>(
    0,
    (n, l) => n + (l['line_total_xof'] as int),
  );
  final commission = subtotal * 5 ~/ 100;
  return {
    'id': id,
    'number': number,
    'reference': 'IV-${number.toString().padLeft(6, '0')}',
    'shop_id': shopId,
    'status': status,
    'fulfillment': fulfillment,
    'vehicle_type': null,
    'parcel_size': 'small',
    'buyer_first_name': buyerFirstName,
    'subtotal_xof': subtotal,
    'delivery_fee_xof': fulfillment == 'delivery' ? 1000 : 0,
    'total_xof': subtotal + (fulfillment == 'delivery' ? 1000 : 0),
    'commission_xof': commission,
    'net_xof': subtotal - commission,
    'delivery_address': null,
    'cancel_reason': cancelReason,
    'payment_deadline_at': paid.toIso8601String(),
    'seller_deadline_at': paid
        .add(const Duration(minutes: 15))
        .toIso8601String(),
    'paid_at': paid.toIso8601String(),
    'accepted_at': null,
    'ready_at': null,
    'picked_up_at': null,
    'completed_at': null,
    'cancelled_at': null,
    'refunded_at': null,
    'created_at': paid.subtract(const Duration(minutes: 2)).toIso8601String(),
    'updated_at': (updatedAt ?? paid).toUtc().toIso8601String(),
    'handover_attempts': handoverAttempts,
    'items': lines,
    'events': <Map<String, dynamic>>[],
  };
}

/// Ligne de commande (schéma `OrderItem`).
Map<String, dynamic> orderItemBody(
  String productId,
  String name,
  int unitPriceXof,
  int quantity, {
  String stockMode = 'tracked',
}) => {
  'product_id': productId,
  'product_name': name,
  'unit_price_xof': unitPriceXof,
  'quantity': quantity,
  'line_total_xof': unitPriceXof * quantity,
  'parcel_size': 'small',
  'stock_mode': stockMode,
};

/// Boutique type (schéma `Shop`).
Map<String, dynamic> shopBody({
  String status = 'pending_review',
  List<String> documents = const ['id_card'],
}) => {
  'id': '0b8e7f52-6a1c-4c3e-8f0d-2a9b7c6d5e4f',
  'owner_id': '7d5c1d38-3c1b-4b8f-9a77-1f2e3d4c5b6a',
  'name': 'Chez Afi',
  'description': '',
  'phone': '+22890123456',
  'address_text': 'Rue 248',
  'neighborhood_id': '5f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b',
  'neighborhood_name': 'Tokoin',
  'category_id': '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d',
  'category_name': 'Alimentation',
  'location': {'lat': 6.1375, 'lng': 1.2123},
  'logo_url': null,
  'status': status,
  'status_reason': status == 'rejected' ? 'Photo du logo illisible.' : '',
  'accepting_orders': true,
  'reviewed_at': null,
  'created_at': '2026-10-31T10:00:00Z',
  'updated_at': '2026-10-31T10:00:00Z',
  'merchant_documents': [
    for (final (i, kind) in documents.indexed) merchantDocumentBody(i, kind),
  ],
};

/// Pièce du marchand vue par son propriétaire (sans lien de lecture).
Map<String, dynamic> merchantDocumentBody(int index, String kind) => {
  'id': 'd${index.toString().padLeft(7, '0')}-0000-4000-8000-000000000000',
  'kind': kind,
  'created_at': '2026-10-31T10:00:00Z',
};

/// Listes de choix types : catégories de boutique et quartiers.
const shopCategoriesBody = {
  'items': [
    {'id': '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d', 'name': 'Alimentation'},
    {'id': '2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7e', 'name': 'Mode et beauté'},
  ],
};

const neighborhoodsBody = {
  'items': [
    {
      'id': '5f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b',
      'city': 'Lomé',
      'name': 'Tokoin',
      'is_active': true,
      'center': null,
    },
    {
      'id': '6a2f3e4d-5c6b-7a89-9b0c-1d2e3f4a5b6c',
      'city': 'Lomé',
      'name': 'Bè',
      'is_active': true,
      'center': null,
    },
  ],
};

/// Dossier livreur type (schéma `Driver`).
Map<String, dynamic> driverBody({
  String review = 'pending_review',
  String status = 'pending_review',
  String vehicleType = 'motorbike',
  List<String> documents = const [
    'id_card',
    'driving_license',
    'vehicle_registration',
  ],
}) => {
  'user_id': '7d5c1d38-3c1b-4b8f-9a77-1f2e3d4c5b6a',
  'status': status,
  'review_status': review,
  'review_note': review == 'rejected' ? 'Carte grise illisible.' : '',
  'reviewed_at': null,
  'suspended_at': null,
  'suspension_reason': status == 'suspended' ? 'Plaintes répétées.' : '',
  'availability': 'offline',
  'vehicle_type': vehicleType,
  'vehicle_plate': 'TG 4521 AB',
  'vehicle_description': '',
  'last_location_at': null,
  'documents': [
    for (final (i, kind) in documents.indexed)
      {'id': 'doc-$i', 'kind': kind, 'created_at': '2026-10-31T10:00:00Z'},
  ],
  'created_at': '2026-10-31T10:00:00Z',
};

/// Identifiant de la boutique de [shopBody].
const shopId = '0b8e7f52-6a1c-4c3e-8f0d-2a9b7c6d5e4f';

/// Catégories de produits types (`GET /v1/categories`).
const productCategoriesBody = {
  'items': [
    {
      'id': 'c1000000-0000-4000-8000-000000000001',
      'name': 'Alimentation',
      'parent_id': null,
      'position': 0,
      'is_active': true,
      'updated_at': '2026-10-31T08:00:00Z',
    },
    {
      'id': 'c1000000-0000-4000-8000-000000000002',
      'name': 'Céréales',
      'parent_id': 'c1000000-0000-4000-8000-000000000001',
      'position': 1,
      'is_active': true,
      'updated_at': '2026-10-31T08:00:00Z',
    },
    {
      'id': 'c1000000-0000-4000-8000-000000000003',
      'name': 'Boissons',
      'parent_id': null,
      'position': 2,
      'is_active': true,
      'updated_at': '2026-10-31T08:00:00Z',
    },
  ],
};

/// Produit type (schéma `Product`).
Map<String, dynamic> productBody({
  String id = 'p0000000-0000-4000-8000-000000000001',
  String name = 'Riz parfumé 5 kg',
  String status = 'active',
  int price = 4500,
  String stockMode = 'tracked',
  int? stock = 12,
  int images = 1,
  String createdAt = '2026-10-31T10:00:00Z',
}) => {
  'id': id,
  'shop_id': shopId,
  'category_id': 'c1000000-0000-4000-8000-000000000001',
  'name': name,
  'description': 'Riz long grain parfumé.',
  'price_xof': price,
  'parcel_size': 'medium',
  'stock_mode': stockMode,
  'stock_quantity': stockMode == 'tracked' ? stock : null,
  'available':
      status == 'active' && (stockMode == 'untracked' || (stock ?? 0) > 0),
  'is_active': status == 'active',
  'status': status,
  'published_at': status == 'draft' ? null : '2026-10-12T09:00:00Z',
  'withdrawn_at': status == 'withdrawn' ? '2026-10-24T09:00:00Z' : null,
  'images': [
    for (var i = 0; i < images; i++)
      {
        'url': 'https://cdn.test/products/$id-$i.jpg',
        'object_key': 'products/$id-$i.jpg',
        'position': i,
      },
  ],
  'created_at': createdAt,
  'updated_at': createdAt,
};

/// Catalogue en mémoire branché sur un [FakeApiServer], fidèle au backend :
/// états et dates de publication, filtres `status` et `q` (sans accents ni
/// majuscules), compteurs, pagination, stock, envoi des photos.
class FakeCatalog {
  FakeCatalog(this.server, {this.shop = shopId}) {
    server
      ..on('GET', '/v1/categories', (_) => _ok(productCategoriesBody))
      ..on('GET', '/v1/seller/shops/$shop/products', _list)
      ..on('GET', '/v1/seller/shops/$shop/product-counts', (_) => _ok(counts))
      ..on('POST', '/v1/seller/shops/$shop/products', _create)
      ..onPattern('GET', '/v1/seller/products/([^/]+)', _get)
      ..onPattern('PATCH', '/v1/seller/products/([^/]+)', _update)
      ..onPattern('PUT', '/v1/seller/products/([^/]+)/stock', _stock)
      ..on('POST', '/v1/uploads', _prepareUpload)
      ..onPattern(
        'PUT',
        '/products/[^/]+',
        (r) => _failure(r) ?? FakeResponse.json(200, ''),
      );
  }

  final FakeApiServer server;
  final String shop;

  /// Produits, dans l'ordre de création.
  final products = <Map<String, dynamic>>[];

  /// Horloge du serveur : aujourd'hui (UTC, heure de Lomé), à partir de
  /// 00 h 01, une minute par écriture. Les dates écrites par le faux serveur
  /// s'affichent donc « aujourd'hui » dans l'app.
  var _clock = () {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day, 0, 1);
  }();

  /// Attendu avant de répondre à une lecture de la liste (réseau lent
  /// simulé) ; `null` : réponse immédiate.
  Future<void> Function(RecordedRequest request)? beforeList;

  /// Catégories désactivées par l'admin : refusées comme par le backend
  /// (création, catégorie changée, produit en vente) ; un retrait passe.
  final inactiveCategories = <String>{};

  FakeResponse? _categoryRefused(Object? categoryId, {required bool check}) =>
      check && inactiveCategories.contains(categoryId)
      ? FakeResponse.error(
          400,
          'validation_failed',
          'Certaines informations sont invalides.',
          fields: {'category_id': 'Catégorie inconnue.'},
        )
      : null;
  var _uploads = 0;

  /// Prochaine erreur à renvoyer, une seule fois, pour la première requête
  /// dont « MÉTHODE chemin » contient la clé (ex. `POST /v1/seller/shops`,
  /// `PUT /v1/seller/products`).
  final failures = <String, FakeResponse>{};

  DateTime _tick() => _clock = _clock.add(const Duration(minutes: 1));

  /// Ajoute un produit existant (état initial d'un test).
  Map<String, dynamic> seed({
    required String name,
    String status = 'active',
    int price = 4500,
    String stockMode = 'tracked',
    int? stock = 12,
    int images = 1,
  }) {
    final body = productBody(
      id: 'p${products.length.toString().padLeft(7, '0')}-0000-4000-8000-000000000000',
      name: name,
      status: status,
      price: price,
      stockMode: stockMode,
      stock: stock,
      images: images,
      createdAt: _tick().toIso8601String(),
    );
    if (status == 'withdrawn') {
      body['withdrawn_at'] = _tick().toIso8601String();
    }
    products.add(body);
    return body;
  }

  Map<String, dynamic> byName(String name) =>
      products.firstWhere((p) => p['name'] == name);

  Map<String, int> get counts => {
    for (final s in const ['active', 'draft', 'withdrawn'])
      s: products.where((p) => p['status'] == s).length,
  };

  FakeResponse? _failure(RecordedRequest r) {
    for (final key in failures.keys) {
      if ('${r.method} ${r.path}'.contains(key)) return failures.remove(key);
    }
    return null;
  }

  static FakeResponse _ok(Object? body) => FakeResponse.json(200, body);

  static String _fold(String s) {
    const from = 'àâäáãçéèêëíìîïñóòôöõúùûüÿ';
    const to = 'aaaaaceeeeiiiinooooouuuuy';
    final lower = s.toLowerCase();
    final out = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      out.write(i < 0 ? ch : to[i]);
    }
    return out.toString();
  }

  Future<FakeResponse> _list(RecordedRequest r) async {
    if (beforeList case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    final status = r.query['status'];
    final q = _fold(r.query['q']?.trim() ?? '');
    final offset = int.parse(r.query['offset'] ?? '0');
    final limit = int.parse(r.query['limit'] ?? '20');
    final items =
        products
            .where((p) => status == null || p['status'] == status)
            .where((p) => q.isEmpty || _fold(p['name'] as String).contains(q))
            .toList()
          ..sort((a, b) {
            if (status == 'withdrawn') {
              return (b['withdrawn_at'] as String).compareTo(
                a['withdrawn_at'] as String,
              );
            }
            return (b['created_at'] as String).compareTo(
              a['created_at'] as String,
            );
          });
    final page = items.skip(offset).take(limit).toList();
    final more = items.length > offset + limit;
    return _ok({'items': page, 'next_offset': more ? offset + limit : null});
  }

  FakeResponse _get(RecordedRequest r) {
    if (_failure(r) case final f?) return f;
    final id = r.path.split('/').last;
    final p = products.where((p) => p['id'] == id).firstOrNull;
    return p == null
        ? FakeResponse.error(404, 'product_not_found', 'Produit introuvable.')
        : _ok(p);
  }

  FakeResponse _create(RecordedRequest r) {
    if (_failure(r) case final f?) return f;
    final input = r.body! as Map<String, dynamic>;
    final active = input['is_active'] as bool? ?? true;
    if (_categoryRefused(input['category_id'], check: true) case final f?) {
      return f;
    }
    final now = _tick().toIso8601String();
    final tracked = input['stock_mode'] == 'tracked';
    final id =
        'n${products.length.toString().padLeft(7, '0')}-0000-4000-8000-000000000000';
    final body = <String, dynamic>{
      'id': id,
      'shop_id': shop,
      'stock_mode': input['stock_mode'],
      'stock_quantity': tracked ? input['stock_quantity'] : null,
      'published_at': active ? now : null,
      'withdrawn_at': null,
      'created_at': now,
      'updated_at': now,
    };
    _apply(body, input, active);
    products.add(body);
    return FakeResponse.json(201, body);
  }

  FakeResponse _update(RecordedRequest r) {
    if (_failure(r) case final f?) return f;
    final id = r.path.split('/').last;
    final p = products.where((p) => p['id'] == id).firstOrNull;
    if (p == null) {
      return FakeResponse.error(
        404,
        'product_not_found',
        'Produit introuvable.',
      );
    }
    final input = r.body! as Map<String, dynamic>;
    final was = p['is_active'] as bool;
    final active = input['is_active'] as bool? ?? was;
    final refused = _categoryRefused(
      input['category_id'],
      check: active || input['category_id'] != p['category_id'],
    );
    if (refused != null) return refused;
    final now = _tick().toIso8601String();
    if (active && !was) p['published_at'] = now;
    if (active) {
      p['withdrawn_at'] = null;
    } else if (was) {
      p['withdrawn_at'] = now;
    }
    p['updated_at'] = now;
    _apply(p, input, active);
    return _ok(p);
  }

  void _apply(Map<String, dynamic> p, Map<String, dynamic> input, bool active) {
    p
      ..['category_id'] = input['category_id']
      ..['name'] = input['name']
      ..['description'] = input['description'] ?? ''
      ..['price_xof'] = input['price_xof']
      ..['parcel_size'] = input['parcel_size']
      ..['is_active'] = active
      ..['status'] = active
          ? 'active'
          : p['published_at'] == null
          ? 'draft'
          : 'withdrawn';
    if (input['image_keys'] case final List keys) {
      p['images'] = [
        for (final (i, key) in keys.indexed)
          {'url': 'https://cdn.test/$key', 'object_key': key, 'position': i},
      ];
    }
    p['images'] ??= [];
    _available(p);
  }

  static void _available(Map<String, dynamic> p) {
    final tracked = p['stock_mode'] == 'tracked';
    p['available'] =
        p['is_active'] == true &&
        (!tracked || ((p['stock_quantity'] as int?) ?? 0) > 0);
  }

  FakeResponse _stock(RecordedRequest r) {
    if (_failure(r) case final f?) return f;
    final id = r.path.split('/')[4];
    final p = products.where((p) => p['id'] == id).firstOrNull;
    if (p == null) {
      return FakeResponse.error(
        404,
        'product_not_found',
        'Produit introuvable.',
      );
    }
    if (p['stock_mode'] != 'tracked') {
      return FakeResponse.error(
        409,
        'stock_not_tracked',
        "Ce produit n'a pas de stock suivi.",
      );
    }
    p['stock_quantity'] = (r.body! as Map)['quantity'];
    _available(p);
    return _ok(p);
  }

  FakeResponse _prepareUpload(RecordedRequest r) {
    if (_failure(r) case final f?) return f;
    final key = 'products/u${++_uploads}.jpg';
    return FakeResponse.json(201, {
      'object_key': key,
      'upload': {
        'method': 'PUT',
        'url': 'https://storage.test/$key',
        'headers': {'Content-Type': 'image/jpeg'},
        'expires_at': '2026-10-31T10:05:00Z',
      },
    });
  }
}

/// Pièces du marchand en mémoire, fidèles au backend : envoi par URL signée
/// (`POST /v1/uploads`, `merchant_document`, compartiment privé), puis
/// rattachement (`POST /v1/seller/documents`, 10 pièces au plus) ; la liste
/// (`GET /v1/seller/documents`) et `required`. Prend la main sur
/// `POST /v1/uploads` : seul l'usage `merchant_document` y est accepté.
class FakeMerchantDocuments {
  FakeMerchantDocuments(this.server, {List<String> documents = const []})
    : kinds = [...documents] {
    server
      ..on('GET', '/v1/seller/documents', (_) => _list(200))
      ..on('POST', '/v1/seller/documents', attach)
      ..on('POST', '/v1/uploads', _prepareUpload)
      ..onPattern('PUT', '/merchants/[^/]+/[^/]+', (r) {
        if (_failure(r) case final f?) return f;
        uploaded.add(r.path.substring(1));
        return FakeResponse.json(200, '');
      });
  }

  final FakeApiServer server;

  /// Types des pièces rattachées, dans l'ordre.
  final List<String> kinds;

  /// Clés envoyées sur une URL signée (fichiers déposés).
  final uploaded = <String>[];

  /// Prochaine erreur à renvoyer, une seule fois, pour la première requête
  /// dont « MÉTHODE chemin » contient la clé (ex. `POST /v1/uploads`,
  /// `PUT /merchants`, `POST /v1/seller/documents`).
  final failures = <String, FakeResponse>{};

  var _prepared = 0;

  FakeResponse? _failure(RecordedRequest r) {
    for (final key in failures.keys) {
      if ('${r.method} ${r.path}'.contains(key)) return failures.remove(key);
    }
    return null;
  }

  FakeResponse _list(int status) => FakeResponse.json(status, {
    'items': [
      for (final (i, kind) in kinds.indexed) merchantDocumentBody(i, kind),
    ],
    'required': ['id_card'],
  });

  FakeResponse _prepareUpload(RecordedRequest r) {
    if (_failure(r) case final f?) return f;
    final body = r.body! as Map;
    if (body['purpose'] != 'merchant_document' ||
        body['content_type'] != 'image/jpeg' ||
        (body['size_bytes'] as int) > 5 * 1024 * 1024) {
      return FakeResponse.error(
        400,
        'validation_failed',
        'Certaines informations sont invalides.',
      );
    }
    // Format du serveur : `merchants/<utilisateur>/<fichier>`.
    final key = 'merchants/u1/d${++_prepared}.jpg';
    return FakeResponse.json(201, {
      'object_key': key,
      'upload': {
        'method': 'PUT',
        'url': 'https://storage.test/$key',
        'headers': {'Content-Type': 'image/jpeg'},
        'expires_at': '2026-10-31T10:05:00Z',
      },
    });
  }

  /// Rattachement (`POST /v1/seller/documents`) : public pour qu'un test
  /// l'enveloppe (réponse retardée, coupure).
  FakeResponse attach(RecordedRequest r) {
    if (_failure(r) case final f?) return f;
    final body = r.body! as Map;
    final kind = body['kind'];
    if (!const ['id_card', 'business_registration', 'other'].contains(kind)) {
      return FakeResponse.error(
        400,
        'validation_failed',
        'Certaines informations sont invalides.',
        fields: {
          'kind':
              'Type de document inconnu : id_card, business_registration ou '
              'other.',
        },
      );
    }
    if (kinds.length >= 10) {
      return FakeResponse.error(
        409,
        'too_many_documents',
        'Nombre maximal de documents atteint.',
      );
    }
    // Comme `uploads.Check` : la clé doit venir d'une URL signée de ce
    // compte, pour cet usage.
    final key = body['object_key'];
    if (key is! String || !key.startsWith('merchants/u1/')) {
      return FakeResponse.error(
        400,
        'validation_failed',
        'Certaines informations sont invalides.',
        fields: {'object_key': 'Fichier invalide.'},
      );
    }
    if (!uploaded.contains(key)) {
      return FakeResponse.error(
        400,
        'validation_failed',
        'Certaines informations sont invalides.',
        fields: {'object_key': "Le fichier n'a pas été reçu. Renvoyez-le."},
      );
    }
    kinds.add(kind as String);
    return _list(201);
  }
}

/// Quartiers de [neighborhoodsBody].
const tokoinId = '5f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b';
const beId = '6a2f3e4d-5c6b-7a89-9b0c-1d2e3f4a5b6c';

/// Recherche publique en mémoire branchée sur un [FakeApiServer], fidèle au
/// backend : texte (sans accents ni majuscules), catégorie (parente
/// comprise), boutique, prix, quartier, rayon et distance, « en stock »,
/// tris, pagination ; fiches publiques produit et boutique.
class FakeSearch {
  FakeSearch(this.server) {
    server
      ..on(
        'GET',
        '/v1/categories',
        (_) => FakeResponse.json(200, productCategoriesBody),
      )
      ..on(
        'GET',
        '/v1/neighborhoods',
        (_) => FakeResponse.json(200, neighborhoodsBody),
      )
      ..on('GET', '/v1/search/products', _searchProducts)
      ..on('GET', '/v1/search/shops', _searchShops)
      ..onPattern('GET', '/v1/products/([^/]+)', _product)
      ..onPattern('GET', '/v1/shops/([^/]+)', _shop);
  }

  final FakeApiServer server;
  final shops = <Map<String, dynamic>>[];
  final products = <Map<String, dynamic>>[];

  /// Prochaine erreur, une seule fois, pour la première requête dont
  /// « MÉTHODE chemin » contient la clé.
  final failures = <String, FakeResponse>{};

  /// Attendu avant de répondre à une recherche (réseau lent simulé).
  Future<void> Function(RecordedRequest request)? beforeSearch;

  var _seq = 0;

  /// Identifiant au format UUID, comme ceux de la base ([kind] : chiffre de
  /// tête qui distingue boutiques et produits à la lecture).
  static String _uuid(int kind, int n) =>
      '${kind.toRadixString(16)}0000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

  FakeResponse? _failure(RecordedRequest r) {
    for (final key in failures.keys) {
      if ('${r.method} ${r.path}'.contains(key)) return failures.remove(key);
    }
    return null;
  }

  /// Ajoute une boutique publiée.
  Map<String, dynamic> shop(
    String name, {
    String neighborhoodId = tokoinId,
    GeoPoint location = const GeoPoint(lat: 6.1375, lng: 1.2123),
    bool acceptingOrders = true,
    String? logoUrl,
  }) {
    final s = {
      'id': _uuid(0x5, _seq++),
      'name': name,
      'description': '',
      'phone': '+22890123456',
      'address_text': 'Rue 248',
      'neighborhood_id': neighborhoodId,
      'neighborhood_name': neighborhoodId == beId ? 'Bè' : 'Tokoin',
      'location': location.toJson(),
      'logo_url': logoUrl,
      'accepting_orders': acceptingOrders,
      'created_at': DateTime.utc(
        2026,
        10,
        1,
      ).add(Duration(minutes: _seq)).toIso8601String(),
    };
    shops.add(s);
    return s;
  }

  /// Ajoute un produit en vente à [shop].
  Map<String, dynamic> product(
    Map<String, dynamic> shop,
    String name, {
    int price = 4500,
    String categoryId = 'c1000000-0000-4000-8000-000000000001',
    String parcelSize = 'medium',
    String stockMode = 'tracked',
    int? stock = 12,
    int images = 1,
    String description = '',
  }) {
    final n = _seq++;
    final id = _uuid(0xa, n);
    final p = {
      ...productBody(
        id: id,
        name: name,
        price: price,
        stockMode: stockMode,
        stock: stock,
        images: images,
        createdAt: DateTime.utc(
          2026,
          10,
          1,
        ).add(Duration(minutes: n)).toIso8601String(),
      ),
      'shop_id': shop['id'],
      'category_id': categoryId,
      'parcel_size': parcelSize,
      'description': description,
    };
    products.add(p);
    return p;
  }

  static String _fold(String s) {
    const from = 'àâäáãçéèêëíìîïñóòôöõúùûüÿ';
    const to = 'aaaaaceeeeiiiinooooouuuuy';
    final out = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      out.write(i < 0 ? ch : to[i]);
    }
    return out.toString();
  }

  /// Distance en mètres (haversine), comme `ST_Distance` à quelques mètres
  /// près sur Lomé.
  static double distance(GeoPoint a, GeoPoint b) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(b.lat - a.lat);
    final dLng = rad(b.lng - a.lng);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.lat)) *
            math.cos(rad(b.lat)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  Map<String, dynamic> _shopOf(Map<String, dynamic> p) =>
      shops.firstWhere((s) => s['id'] == p['shop_id']);

  GeoPoint _loc(Map<String, dynamic> s) =>
      GeoPoint.fromJson(s['location'] as Map<String, dynamic>);

  static String? _parentOf(String categoryId) {
    for (final c in productCategoriesBody['items']!) {
      if (c['id'] == categoryId) return c['parent_id'] as String?;
    }
    return null;
  }

  static bool _inStock(Map<String, dynamic> p) =>
      p['stock_mode'] == 'untracked' ||
      ((p['stock_quantity'] as int?) ?? 0) > 0;

  FakeResponse? _validate(RecordedRequest r, {required bool products}) {
    final q = r.query;
    const shopSorts = ['relevance', 'distance'];
    const productSorts = [...shopSorts, 'price_asc', 'price_desc'];
    if (q['sort'] case final sort?
        when !(products ? productSorts : shopSorts).contains(sort)) {
      return _invalid('sort', 'Valeur non reconnue.');
    }
    if ((q['q'] ?? '').trim().length > 100) {
      return _invalid('q', 'Valeur trop longue.');
    }
    if (q.containsKey('lat') != q.containsKey('lng')) {
      return _invalid('lat', 'Indiquez lat et lng ensemble.');
    }
    if ((q.containsKey('radius_m') || q['sort'] == 'distance') &&
        !q.containsKey('lat')) {
      return _invalid(
        'lat',
        'La position est nécessaire pour chercher autour de vous.',
      );
    }
    final min = int.tryParse(q['min_price'] ?? '');
    final max = int.tryParse(q['max_price'] ?? '');
    if (min != null && max != null && min > max) {
      return _invalid('min_price', 'Le prix minimal dépasse le prix maximal.');
    }
    return null;
  }

  static FakeResponse _invalid(String field, String message) =>
      FakeResponse.error(
        400,
        'validation_failed',
        'Certaines informations sont invalides.',
        fields: {field: message},
      );

  GeoPoint? _point(RecordedRequest r) => r.query.containsKey('lat')
      ? GeoPoint(
          lat: double.parse(r.query['lat']!),
          lng: double.parse(r.query['lng']!),
        )
      : null;

  FakeResponse _page(RecordedRequest r, List<Map<String, dynamic>> items) {
    final offset = int.parse(r.query['offset'] ?? '0');
    final limit = int.parse(r.query['limit'] ?? '20');
    final page = items.skip(offset).take(limit).toList();
    final more = items.length > offset + limit;
    return FakeResponse.json(200, {
      'items': page,
      'next_offset': more ? offset + limit : null,
    });
  }

  Future<FakeResponse> _searchProducts(RecordedRequest r) async {
    if (beforeSearch case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    if (_validate(r, products: true) case final f?) return f;
    final q = r.query;
    final text = _fold(q['q'] ?? '');
    final point = _point(r);
    final radius = double.tryParse(q['radius_m'] ?? '');
    final min = int.tryParse(q['min_price'] ?? '');
    final max = int.tryParse(q['max_price'] ?? '');
    final hits = <(Map<String, dynamic>, double?)>[];
    for (final p in products) {
      if (p['is_active'] == false) continue;
      final s = _shopOf(p);
      final d = point == null ? null : distance(point, _loc(s));
      final category = p['category_id'] as String;
      if (text.isNotEmpty && !_fold(p['name'] as String).contains(text)) {
        continue;
      }
      if (q['category_id'] case final c?
          when category != c && _parentOf(category) != c) {
        continue;
      }
      if (q['shop_id'] case final id? when p['shop_id'] != id) continue;
      if (min != null && (p['price_xof'] as int) < min) continue;
      if (max != null && (p['price_xof'] as int) > max) continue;
      if (q['neighborhood_id'] case final n? when s['neighborhood_id'] != n) {
        continue;
      }
      if (radius != null && d! > radius) continue;
      if (q['in_stock'] == 'true' && !_inStock(p)) continue;
      hits.add((p, d));
    }
    // Comme le backend : critère demandé, puis le plus récent, puis l'id.
    int newest(Map<String, dynamic> a, Map<String, dynamic> b) {
      final c = (b['created_at'] as String).compareTo(
        a['created_at'] as String,
      );
      return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
    }

    hits.sort((a, b) {
      final first = switch (q['sort']) {
        'distance' => a.$2!.compareTo(b.$2!),
        'price_asc' => (a.$1['price_xof'] as int).compareTo(
          b.$1['price_xof'] as int,
        ),
        'price_desc' => (b.$1['price_xof'] as int).compareTo(
          a.$1['price_xof'] as int,
        ),
        _ => 0,
      };
      return first != 0 ? first : newest(a.$1, b.$1);
    });
    return _page(r, [
      for (final (p, d) in hits)
        {
          'id': p['id'],
          'shop_id': p['shop_id'],
          'name': p['name'],
          'price_xof': p['price_xof'],
          'parcel_size': p['parcel_size'],
          'shop_name': _shopOf(p)['name'],
          'neighborhood_id': _shopOf(p)['neighborhood_id'],
          'image_url': (p['images'] as List).isEmpty
              ? null
              : (p['images'] as List).first['url'],
          'in_stock': _inStock(p),
          'distance_m': d?.round(),
        },
    ]);
  }

  Future<FakeResponse> _searchShops(RecordedRequest r) async {
    if (beforeSearch case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    if (_validate(r, products: false) case final f?) return f;
    final q = r.query;
    final text = _fold(q['q'] ?? '');
    final point = _point(r);
    final radius = double.tryParse(q['radius_m'] ?? '');
    final hits = <(Map<String, dynamic>, double?)>[];
    for (final s in shops) {
      final d = point == null ? null : distance(point, _loc(s));
      if (text.isNotEmpty && !_fold(s['name'] as String).contains(text)) {
        continue;
      }
      if (q['neighborhood_id'] case final n? when s['neighborhood_id'] != n) {
        continue;
      }
      if (radius != null && d! > radius) continue;
      hits.add((s, d));
    }
    hits.sort((a, b) {
      final first = q['sort'] == 'distance' ? a.$2!.compareTo(b.$2!) : 0;
      if (first != 0) return first;
      final c = (b.$1['created_at'] as String).compareTo(
        a.$1['created_at'] as String,
      );
      return c != 0
          ? c
          : (a.$1['id'] as String).compareTo(b.$1['id'] as String);
    });
    return _page(r, [
      for (final (s, d) in hits)
        {
          'id': s['id'],
          'name': s['name'],
          'description': s['description'],
          'neighborhood_id': s['neighborhood_id'],
          'logo_url': s['logo_url'],
          'accepting_orders': s['accepting_orders'],
          'distance_m': d?.round(),
        },
    ]);
  }

  FakeResponse _product(RecordedRequest r) {
    if (_failure(r) case final f?) return f;
    final id = r.path.split('/').last;
    final p = products.where((p) => p['id'] == id).firstOrNull;
    if (p == null || p['is_active'] == false) {
      return FakeResponse.error(
        404,
        'product_not_found',
        'Produit introuvable.',
      );
    }
    return FakeResponse.json(200, {'product': p, 'shop': _shopOf(p)});
  }

  FakeResponse _shop(RecordedRequest r) {
    if (_failure(r) case final f?) return f;
    final id = r.path.split('/').last;
    final s = shops.where((s) => s['id'] == id).firstOrNull;
    return s == null
        ? FakeResponse.error(404, 'shop_not_found', 'Boutique introuvable.')
        : FakeResponse.json(200, s);
  }
}

/// Panier de l'acheteur en mémoire, branché sur les produits et boutiques
/// d'une [FakeSearch], fidèle au module `cart` du backend : une seule
/// boutique (`cart_shop_conflict`, sauf `replace_cart`), quantité totale de
/// 0 à 99, stock vérifié, 30 lignes au plus, lignes dans l'ordre d'ajout,
/// `issue` et `orderable` recalculés à chaque lecture.
///
/// Un test retire un produit avec `p['is_active'] = false` et change le
/// stock avec `p['stock_quantity'] = n` ; une boutique fermée aux commandes
/// avec `s['accepting_orders'] = false`.
///
/// Un panier par compte, reconnu à l'en-tête `Authorization`, comme le
/// serveur qui ne lit que le panier du jeton. [shopId], [lines] et [put]
/// portent sur le premier compte qui appelle (celui du test) ; un autre
/// jeton a son propre panier, vide au départ.
class FakeCart {
  FakeCart(this.search) {
    search.server
      ..on('GET', '/v1/cart', _get)
      ..on('PUT', '/v1/cart/items', _set)
      ..on('DELETE', '/v1/cart', _clear);
  }

  static const maxLines = 30;
  static const maxQuantity = 99;

  final FakeSearch search;

  /// Boutique du panier ; `null` : pas de panier.
  String? shopId;

  /// Quantités par produit, dans l'ordre d'ajout.
  final lines = <String, int>{};

  /// En-tête `Authorization` du premier compte, propriétaire de [lines].
  String? _owner;

  /// Paniers des autres comptes : boutique et lignes.
  final _others = <String, (String?, Map<String, int>)>{};

  /// Lignes du compte qui envoie le jeton [authorization].
  Map<String, int> linesOf(String authorization) =>
      authorization == _owner ? lines : _others[authorization]?.$2 ?? {};

  /// Sert [handle] avec le panier du compte de [r] à la place de celui du
  /// premier compte, puis remet chacun à sa place.
  Future<FakeResponse> _as(
    RecordedRequest r,
    FakeResponse Function() handle,
  ) async {
    final auth = r.headers['authorization'] ?? '';
    _owner ??= auth;
    if (auth == _owner) return handle();
    final own = (shopId, {...lines});
    final (otherShop, otherLines) = _others[auth] ?? (null, <String, int>{});
    shopId = otherShop;
    lines
      ..clear()
      ..addAll(otherLines);
    try {
      return handle();
    } finally {
      _others[auth] = (shopId, {...lines});
      shopId = own.$1;
      lines
        ..clear()
        ..addAll(own.$2);
    }
  }

  /// Prochaine erreur, une seule fois, pour la première requête dont
  /// « MÉTHODE chemin » contient la clé.
  final failures = <String, FakeResponse>{};

  /// Attendu avant de répondre à une requête du panier (réseau lent).
  Future<void> Function(RecordedRequest request)? beforeRequest;

  /// Remplit le panier sans passer par l'API.
  void put(Map<String, dynamic> product, int quantity) {
    shopId = product['shop_id'] as String;
    lines[product['id'] as String] = quantity;
  }

  int quantityOf(Map<String, dynamic> product) => lines[product['id']] ?? 0;

  FakeResponse? _failure(RecordedRequest r) {
    for (final key in failures.keys) {
      if ('${r.method} ${r.path}'.contains(key)) return failures.remove(key);
    }
    return null;
  }

  Map<String, dynamic>? _product(String id) =>
      search.products.where((p) => p['id'] == id).firstOrNull;

  Map<String, dynamic>? _shop(String? id) =>
      search.shops.where((s) => s['id'] == id).firstOrNull;

  /// Stock suivi restant ; `null` si le stock n'est pas suivi.
  static int? _stock(Map<String, dynamic> p) =>
      p['stock_mode'] == 'tracked' ? (p['stock_quantity'] as int? ?? 0) : null;

  /// Le panier tel que `GET /v1/cart` le renvoie.
  Map<String, dynamic> body() {
    if (shopId == null) {
      return {
        'shop': null,
        'items': <Object>[],
        'subtotal_xof': 0,
        'orderable': false,
      };
    }
    final shop = _shop(shopId);
    var orderable = lines.isNotEmpty;
    if (shop == null || shop['accepting_orders'] != true) orderable = false;
    var subtotal = 0;
    final items = <Map<String, dynamic>>[];
    for (final MapEntry(key: id, value: qty) in lines.entries) {
      final p = _product(id)!;
      final price = p['price_xof'] as int;
      final stock = _stock(p);
      final images = p['images'] as List;
      final (issue, issueCode) = p['is_active'] == false || shop == null
          ? ("Ce produit n'est plus disponible.", 'unavailable')
          : stock != null && stock < qty
          ? ('Plus que $stock en stock.', 'insufficient_stock')
          : ('', '');
      if (issue.isEmpty) {
        subtotal += price * qty;
      } else {
        orderable = false;
      }
      items.add({
        'product_id': id,
        'name': p['name'],
        'image_url': images.isEmpty ? null : images.first['url'],
        'unit_price_xof': price,
        'quantity': qty,
        'line_total_xof': price * qty,
        'parcel_size': p['parcel_size'],
        'issue': issue,
        'issue_code': issueCode,
        'stock_left': issueCode == 'insufficient_stock' ? stock : null,
      });
    }
    return {
      'shop': shop,
      'items': items,
      'subtotal_xof': subtotal,
      'orderable': orderable,
    };
  }

  Future<FakeResponse> _get(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    return _as(r, () => FakeResponse.json(200, body()));
  }

  Future<FakeResponse> _set(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    return _as(r, () => _apply(r));
  }

  FakeResponse _apply(RecordedRequest r) {
    final input = r.body! as Map<String, dynamic>;
    final id = input['product_id'] as String;
    final qty = input['quantity'] as int;
    final replace = input['replace_cart'] as bool? ?? false;
    if (qty < 0 || qty > maxQuantity) {
      return FakeResponse.error(
        400,
        'validation_failed',
        'Certaines informations sont invalides.',
        fields: {'quantity': 'Quantité entre 0 et 99.'},
      );
    }
    if (qty == 0) {
      lines.remove(id);
      if (lines.isEmpty) shopId = null;
      return FakeResponse.json(200, body());
    }
    final p = _product(id);
    if (p == null || p['is_active'] == false || _shop(p['shop_id']) == null) {
      return FakeResponse.error(
        404,
        'product_not_found',
        'Produit introuvable.',
      );
    }
    final stock = _stock(p);
    if (stock == 0) {
      return FakeResponse.error(
        409,
        'product_unavailable',
        "Ce produit n'est plus disponible.",
      );
    }
    if (stock != null && stock < qty) {
      return FakeResponse.error(
        409,
        'insufficient_stock',
        'Seulement $stock en stock.',
      );
    }
    final shop = p['shop_id'] as String;
    final before = (shopId, {...lines});
    if (shopId != null && shopId != shop) {
      if (!replace) {
        return FakeResponse.error(
          409,
          'cart_shop_conflict',
          "Votre panier contient des produits d'une autre boutique. "
              'Videz-le pour ajouter celui-ci.',
        );
      }
      lines.clear();
    }
    shopId = shop;
    lines[id] = qty;
    if (lines.length > maxLines) {
      // Transaction annulée : le panier reste tel qu'il était.
      shopId = before.$1;
      lines
        ..clear()
        ..addAll(before.$2);
      return FakeResponse.error(
        409,
        'cart_full',
        'Votre panier contient trop de produits différents.',
      );
    }
    return FakeResponse.json(200, body());
  }

  Future<FakeResponse> _clear(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    return _as(r, () {
      shopId = null;
      lines.clear();
      return FakeResponse.json(204, null);
    });
  }
}

/// Commandes de l'acheteur en mémoire, branchées sur le panier d'un
/// [FakeCart], fidèles au module `orders` du backend : récapitulatif
/// (`cart_empty`, `shop_unavailable`, `shop_closed`, `product_unavailable`,
/// `insufficient_stock`), création (profil complet exigé, stock suivi
/// réservé, panier vidé, idempotence par `client_request_id`), liste (plus
/// récentes d'abord, paginée), suivi (404 pour la commande d'un autre
/// compte), code de remise donné seulement entre le paiement et la remise.
///
/// Un test fait avancer une commande avec [advance].
class FakeOrders {
  FakeOrders(this.cart) {
    cart.search.server
      ..on('POST', '/v1/orders/quote', _quote)
      ..on('POST', '/v1/orders', _create)
      ..on('GET', '/v1/orders', _list)
      ..onPattern('GET', '/v1/orders/([^/]+)', _get);
  }

  static const handoverCode = '4827';

  final FakeCart cart;

  /// Commandes, de la plus ancienne à la plus récente.
  final orders = <Map<String, dynamic>>[];

  /// Prochaine erreur, une seule fois, pour la première requête dont
  /// « MÉTHODE chemin » contient la clé.
  final failures = <String, FakeResponse>{};

  /// Attendu avant de répondre (réseau lent).
  Future<void> Function(RecordedRequest request)? beforeRequest;

  var profileComplete = true;
  var paymentTimeoutMinutes = 15;

  /// Limite de débit atteinte : `rate_limited` (après le contrôle
  /// d'idempotence, avant celui du profil, comme le serveur).
  var rateLimited = false;

  /// La prochaine commande est créée, mais sa réponse se perd (coupure
  /// réseau après l'enregistrement).
  var loseNextCreateResponse = false;

  /// Heure du serveur.
  DateTime Function() now = () => DateTime.now().toUtc();

  var _number = 1041;

  /// En-tête `Authorization` de l'acheteur de chaque commande.
  final _buyerOf = <String, String>{};

  FakeSearch get _search => cart.search;

  FakeResponse? _failure(RecordedRequest r) {
    for (final key in failures.keys) {
      if ('${r.method} ${r.path}'.contains(key)) return failures.remove(key);
    }
    return null;
  }

  static FakeResponse _conflict(String code, String message) =>
      FakeResponse.error(409, code, message);

  /// Récapitulatif du panier, ou le refus du serveur.
  (Map<String, dynamic>?, FakeResponse?) _quoteOf(Map<String, dynamic> input) {
    final fulfillment = input['fulfillment'];
    if (cart.lines.isEmpty) {
      return (null, _conflict('cart_empty', 'Votre panier est vide.'));
    }
    if (fulfillment != 'pickup' && fulfillment != 'delivery') {
      return (
        null,
        FakeResponse.error(
          400,
          'validation_failed',
          'Certaines informations sont invalides.',
          fields: {'fulfillment': 'Mode attendu : pickup ou delivery.'},
        ),
      );
    }
    final shop = _search.shops.where((s) => s['id'] == cart.shopId).firstOrNull;
    if (shop == null) {
      return (
        null,
        _conflict('shop_unavailable', "Cette boutique n'est plus disponible."),
      );
    }
    if (shop['accepting_orders'] != true) {
      return (
        null,
        _conflict(
          'shop_closed',
          'Cette boutique ne prend pas de commande pour le moment.',
        ),
      );
    }
    if (fulfillment == 'delivery') {
      return (
        null,
        FakeResponse.error(
          400,
          'validation_failed',
          'Certaines informations sont invalides.',
          fields: {'address_id': 'Choisissez une adresse de livraison.'},
        ),
      );
    }
    final items = <Map<String, dynamic>>[];
    var subtotal = 0;
    for (final MapEntry(key: id, value: qty) in cart.lines.entries) {
      final p = _search.products.firstWhere((p) => p['id'] == id);
      if (p['is_active'] == false) {
        return (
          null,
          _conflict(
            'product_unavailable',
            "Un produit de votre panier n'est plus disponible.",
          ),
        );
      }
      final stock = FakeCart._stock(p);
      if (stock != null && stock < qty) {
        return (
          null,
          _conflict(
            'insufficient_stock',
            'Stock insuffisant pour « ${p['name']} ».',
          ),
        );
      }
      final price = p['price_xof'] as int;
      subtotal += price * qty;
      items.add({
        'product_id': id,
        'product_name': p['name'],
        'unit_price_xof': price,
        'quantity': qty,
        'line_total_xof': price * qty,
        'parcel_size': p['parcel_size'],
        'stock_mode': p['stock_mode'],
      });
    }
    return (
      {
        'shop_id': shop['id'],
        'fulfillment': fulfillment,
        'items': items,
        'subtotal_xof': subtotal,
        'parcel_size': 'medium',
        'vehicle_options': <Object>[],
        'vehicle_type': null,
        'delivery_distance_m': null,
        'delivery_fee_xof': 0,
        'total_xof': subtotal,
        'payment_timeout_minutes': paymentTimeoutMinutes,
      },
      null,
    );
  }

  Future<FakeResponse> _quote(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    final (quote, error) = _quoteOf(r.body! as Map<String, dynamic>);
    return error ?? FakeResponse.json(200, quote);
  }

  /// Statuts où le serveur donne le code de remise.
  static const _showsCode = {
    'awaiting_seller',
    'accepted',
    'preparing',
    'ready_for_pickup',
    'awaiting_driver',
    'driver_assigned',
    'picked_up',
  };

  /// Commande en attente de paiement, comme le serveur l'enregistre.
  Map<String, dynamic> _newOrder({
    required String shopId,
    required List<Map<String, dynamic>> items,
    required String fulfillment,
    required DateTime created,
    required String? requestId,
  }) {
    final number = ++_number;
    final total = items.fold(0, (n, i) => n + (i['line_total_xof'] as int));
    final at = created.toIso8601String();
    return {
      'id':
          'b0000000-0000-4000-8000-${number.toRadixString(16).padLeft(12, '0')}',
      'number': number,
      'reference': 'IV-${number.toString().padLeft(6, '0')}',
      'status': 'pending_payment',
      'fulfillment': fulfillment,
      'vehicle_type': null,
      'parcel_size': 'medium',
      'subtotal_xof': total,
      'delivery_fee_xof': 0,
      'total_xof': total,
      'delivery_address': null,
      'cancel_reason': '',
      'payment_deadline_at': created
          .add(Duration(minutes: paymentTimeoutMinutes))
          .toIso8601String(),
      'seller_deadline_at': null,
      'paid_at': null,
      'accepted_at': null,
      'ready_at': null,
      'picked_up_at': null,
      'completed_at': null,
      'cancelled_at': null,
      'refunded_at': null,
      'created_at': at,
      'updated_at': at,
      'items': items,
      'events': <Map<String, dynamic>>[
        {
          'from_status': null,
          'to_status': 'pending_payment',
          'actor_type': 'buyer',
          'reason': '',
          'created_at': at,
        },
      ],
      'shop_id': shopId,
      'client_request_id': requestId,
    };
  }

  /// La commande telle que l'acheteur la voit.
  Map<String, dynamic> view(Map<String, dynamic> order) => {
    ...order,
    'handover_code': _showsCode.contains(order['status']) ? handoverCode : null,
    'shop': _search.shops.firstWhere((s) => s['id'] == order['shop_id']),
  };

  Future<FakeResponse> _create(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    final input = r.body! as Map<String, dynamic>;
    final auth = r.headers['authorization'] ?? '';
    final requestId = input['client_request_id'] as String?;
    if (requestId != null) {
      final same = orders
          .where(
            (o) =>
                o['client_request_id'] == requestId &&
                _buyerOf[o['id']] == auth,
          )
          .firstOrNull;
      if (same != null) return FakeResponse.json(201, view(same));
    }
    if (rateLimited) {
      return FakeResponse.error(
        429,
        'rate_limited',
        'Trop de commandes en peu de temps. Réessayez plus tard.',
      );
    }
    if (!profileComplete) {
      return _conflict(
        'profile_incomplete',
        'Complétez votre profil (prénom, téléphone, consentement) avant de '
            'commander.',
      );
    }
    final (quote, error) = _quoteOf(input);
    if (error != null) return error;
    // Stock suivi réservé.
    for (final item in quote!['items'] as List) {
      final p = _search.products.firstWhere(
        (p) => p['id'] == item['product_id'],
      );
      if (p['stock_mode'] == 'tracked') {
        p['stock_quantity'] =
            (p['stock_quantity'] as int) - (item['quantity'] as int);
      }
    }
    final order = _newOrder(
      shopId: quote['shop_id'] as String,
      items: [
        for (final item in quote['items'] as List)
          Map<String, dynamic>.of(item as Map<String, dynamic>),
      ],
      fulfillment: input['fulfillment'] as String,
      created: now(),
      requestId: requestId,
    );
    final id = order['id'] as String;
    orders.add(order);
    _buyerOf[id] = auth;
    cart
      ..shopId = null
      ..lines.clear();
    if (loseNextCreateResponse) {
      loseNextCreateResponse = false;
      return FakeResponse.networkError();
    }
    return FakeResponse.json(201, view(order));
  }

  /// Ajoute une commande déjà passée, au statut [status], sans passer par
  /// l'API (elle appartient au premier compte qui lit les commandes).
  Map<String, dynamic> seed(
    Map<String, dynamic> shop,
    List<(Map<String, dynamic>, int)> lines, {
    String status = 'pending_payment',
    DateTime? at,
  }) {
    // Passée depuis 5 minutes par défaut : ses étapes sont dans le passé,
    // avant toute étape ajoutée ensuite par [advance].
    final created = at ?? now().subtract(const Duration(minutes: 5));
    final order = _newOrder(
      shopId: shop['id'] as String,
      items: [
        for (final (p, qty) in lines)
          {
            'product_id': p['id'],
            'product_name': p['name'],
            'unit_price_xof': p['price_xof'],
            'quantity': qty,
            'line_total_xof': (p['price_xof'] as int) * qty,
            'parcel_size': p['parcel_size'],
            'stock_mode': p['stock_mode'],
          },
      ],
      fulfillment: 'pickup',
      created: created,
      requestId: null,
    );
    orders.add(order);
    // Étapes ordinaires d'un retrait jusqu'à [status].
    const path = [
      'awaiting_seller',
      'accepted',
      'preparing',
      'ready_for_pickup',
      'completed',
    ];
    var step = 0;
    DateTime next() => created.add(Duration(seconds: 30 * ++step));
    if (path.contains(status)) {
      for (final s in path) {
        advance(order, s, at: next());
        if (s == status) break;
      }
    } else if (status != 'pending_payment') {
      advance(order, status, at: next());
    }
    return order;
  }

  /// Fait passer [order] à [status] (historique compris), comme la machine
  /// à états du serveur.
  void advance(
    Map<String, dynamic> order,
    String status, {
    String reason = '',
    DateTime? at,
  }) {
    final when = (at ?? now()).toIso8601String();
    (order['events'] as List).add({
      'from_status': order['status'],
      'to_status': status,
      'actor_type': 'system',
      'reason': reason,
      'created_at': when,
    });
    // Comme le serveur : une commande expirée rend son stock suivi.
    if (status == 'expired' && order['status'] == 'pending_payment') {
      _moveStock(order, 1);
    }
    order
      ..['status'] = status
      ..['updated_at'] = when;
    if (status == 'cancelled') order['cancel_reason'] = reason;
  }

  /// Rend (+1) ou reprend (-1) le stock suivi des articles de [order] ;
  /// `false` sans rien changer si un article n'a plus assez de stock.
  bool _moveStock(Map<String, dynamic> order, int sign) {
    final changes = <(Map<String, dynamic>, int)>[];
    for (final item in order['items'] as List) {
      final p = _search.products
          .where((p) => p['id'] == item['product_id'])
          .firstOrNull;
      if (p == null || p['stock_mode'] != 'tracked') continue;
      final next =
          (p['stock_quantity'] as int) + sign * (item['quantity'] as int);
      if (next < 0) return false;
      changes.add((p, next));
    }
    for (final (p, next) in changes) {
      p['stock_quantity'] = next;
    }
    return true;
  }

  bool _visible(Map<String, dynamic> order, RecordedRequest r) {
    final auth = r.headers['authorization'] ?? '';
    return _buyerOf.putIfAbsent(order['id'] as String, () => auth) == auth;
  }

  Future<FakeResponse> _list(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    final offset = int.parse(r.query['offset'] ?? '0');
    final limit = int.parse(r.query['limit'] ?? '20');
    if (limit < 1 || limit > 100) {
      return FakeResponse.error(
        400,
        'validation_failed',
        'Certaines informations sont invalides.',
        fields: {'limit': 'Entre 1 et 100.'},
      );
    }
    // Comme le serveur : les plus récentes d'abord (`created_at`).
    final mine =
        [
          for (final o in orders.reversed)
            if (_visible(o, r)) view(o),
        ]..sort(
          (a, b) =>
              (b['created_at'] as String).compareTo(a['created_at'] as String),
        );
    return FakeResponse.json(200, {
      'items': mine.skip(offset).take(limit).toList(),
      'next_offset': mine.length > offset + limit ? offset + limit : null,
    });
  }

  Future<FakeResponse> _get(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    final id = r.path.split('/').last;
    if (!RegExp(r'^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$').hasMatch(id)) {
      // Comme `httpapi.PathUUID` : identifiant mal formé.
      return FakeResponse.error(404, 'not_found', 'Ressource introuvable.');
    }
    final order = orders.where((o) => o['id'] == id).firstOrNull;
    if (order == null || !_visible(order, r)) {
      return FakeResponse.error(
        404,
        'order_not_found',
        'Commande introuvable.',
      );
    }
    return FakeResponse.json(200, view(order));
  }
}

/// Paiements fidèles au module `payments`, branchés sur [FakeOrders] :
/// demande (commande à payer, numéro togolais, une seule demande en attente
/// par commande, rendue telle quelle), état, liste par commande, annulation
/// (`pending → failed`, idempotente, 409 si réussi), simulation du faux
/// prestataire (réussite : la commande passe en attente de la boutique ;
/// seconde réussite : doublon). Demande d'un autre compte : 404.
///
/// Un test fait aboutir une demande avec [succeed] ou [fail], comme le
/// webhook du prestataire.
class FakePayments {
  FakePayments(this.orders) {
    _server
      ..onPattern('POST', '/v1/orders/([^/]+)/payments', _start)
      ..onPattern('GET', '/v1/orders/([^/]+)/payments', _listForOrder)
      ..onPattern('GET', '/v1/payments/([^/]+)', _get)
      ..onPattern('POST', '/v1/payments/([^/]+)/cancel', _cancel)
      ..onPattern('POST', '/v1/dev/payments/([^/]+)/simulate', _simulate);
  }

  final FakeOrders orders;

  /// Paiements, du plus ancien au plus récent.
  final payments = <Map<String, dynamic>>[];

  /// Prochaine erreur, une seule fois, pour la première requête dont
  /// « MÉTHODE chemin » contient la clé.
  final failures = <String, FakeResponse>{};

  /// Attendu avant de répondre (réseau lent).
  Future<void> Function(RecordedRequest request)? beforeRequest;

  /// Trop de demandes : `rate_limited` (nouvelle demande seulement).
  var rateLimited = false;

  /// Prestataire injoignable : `payment_provider_unavailable`.
  var providerDown = false;

  /// La prochaine demande est créée, mais sa réponse se perd (coupure
  /// réseau après l'enregistrement).
  var loseNextStartResponse = false;

  var _number = 0;

  /// En-tête `Authorization` du payeur de chaque paiement.
  final _buyerOf = <String, String>{};

  FakeApiServer get _server => orders.cart.search.server;

  FakeResponse? _failure(RecordedRequest r) {
    for (final key in failures.keys) {
      if ('${r.method} ${r.path}'.contains(key)) return failures.remove(key);
    }
    return null;
  }

  static String _segment(RecordedRequest r, int index) =>
      r.path.split('/')[index];

  static FakeResponse get _notFound =>
      FakeResponse.error(404, 'payment_not_found', 'Paiement introuvable.');

  static FakeResponse get _orderNotFound =>
      FakeResponse.error(404, 'order_not_found', 'Commande introuvable.');

  Map<String, dynamic>? _orderFor(RecordedRequest r) {
    final id = _segment(r, 3);
    final order = orders.orders.where((o) => o['id'] == id).firstOrNull;
    return order != null && orders._visible(order, r) ? order : null;
  }

  Map<String, dynamic>? _paymentFor(RecordedRequest r, int index) {
    final id = _segment(r, index);
    final auth = r.headers['authorization'] ?? '';
    return payments
        .where((p) => p['id'] == id && _buyerOf[p['id']] == auth)
        .firstOrNull;
  }

  /// Numéro togolais au format `+228XXXXXXXX`, comme
  /// `validate.NormalizeTogoPhone` ; `null` s'il est invalide.
  static String? _normalize(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00228')) {
      digits = digits.substring(5);
    } else if (digits.startsWith('228') && digits.length == 11) {
      digits = digits.substring(3);
    }
    if (digits.length != 8 || !(digits[0] == '7' || digits[0] == '9')) {
      return null;
    }
    return '+228$digits';
  }

  /// Comme `validate.MaskPhone`.
  static String _mask(String phone) =>
      '${phone.substring(0, 6)}••••${phone.substring(phone.length - 2)}';

  Map<String, dynamic>? _pendingOf(String orderId) => payments
      .where((p) => p['order_id'] == orderId && p['status'] == 'pending')
      .firstOrNull;

  Future<FakeResponse> _start(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    final input = r.body as Map<String, dynamic>? ?? const {};
    final operator = input['operator'];
    final phone = _normalize(input['phone'] as String? ?? '');
    if ((operator != 'flooz' && operator != 'tmoney') || phone == null) {
      return FakeResponse.error(
        400,
        'validation_failed',
        'Certaines informations sont invalides.',
        fields: {
          if (operator != 'flooz' && operator != 'tmoney')
            'operator': 'Opérateur attendu : flooz ou tmoney.',
          if (phone == null) 'phone': 'Numéro Mobile Money togolais invalide.',
        },
      );
    }
    final order = _orderFor(r);
    if (order == null) return _orderNotFound;
    if (order['status'] != 'pending_payment') {
      return FakeOrders._conflict(
        'order_not_payable',
        "Cette commande n'attend pas de paiement.",
      );
    }
    final deadline = DateTime.parse(order['payment_deadline_at'] as String);
    if (orders.now().isAfter(deadline)) {
      return FakeOrders._conflict(
        'order_expired',
        'Le délai de paiement est dépassé.',
      );
    }
    if (_pendingOf(order['id'] as String) case final pending?) {
      return FakeResponse.json(201, pending);
    }
    if (rateLimited) {
      return FakeResponse.error(
        429,
        'rate_limited',
        'Trop de demandes de paiement. Réessayez plus tard.',
      );
    }
    final number = ++_number;
    final at = orders.now().toIso8601String();
    final payment = <String, dynamic>{
      'id':
          'c0000000-0000-4000-8000-${number.toRadixString(16).padLeft(12, '0')}',
      'order_id': order['id'],
      'status': 'pending',
      'amount_xof': order['total_xof'],
      'currency': 'XOF',
      'operator': operator,
      'phone_masked': _mask(phone),
      'failure_reason': '',
      'is_duplicate': false,
      'created_at': at,
      'updated_at': at,
    };
    payments.add(payment);
    _buyerOf[payment['id'] as String] = r.headers['authorization'] ?? '';
    if (providerDown) {
      // Comme le serveur : la demande est enregistrée puis close.
      _set(payment, 'failed', 'Prestataire injoignable.');
      return FakeResponse.error(
        503,
        'payment_provider_unavailable',
        "Le paiement n'a pas pu être lancé. Réessayez dans un instant.",
      );
    }
    if (loseNextStartResponse) {
      loseNextStartResponse = false;
      return FakeResponse.networkError();
    }
    return FakeResponse.json(201, {
      ...payment,
      'instructions':
          'Paiement simulé : validez-le avec '
          'POST /v1/dev/payments/{id}/simulate.',
    });
  }

  Future<FakeResponse> _listForOrder(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    final order = _orderFor(r);
    if (order == null) return _orderNotFound;
    return FakeResponse.json(200, {
      'items': [
        for (final p in payments.reversed)
          if (p['order_id'] == order['id']) p,
      ],
    });
  }

  Future<FakeResponse> _get(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    final payment = _paymentFor(r, 3);
    return payment == null ? _notFound : FakeResponse.json(200, payment);
  }

  Future<FakeResponse> _cancel(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    final payment = _paymentFor(r, 3);
    if (payment == null) return _notFound;
    switch (payment['status']) {
      case 'pending':
        _set(payment, 'failed', "Annulé par l'acheteur.");
      case 'failed' || 'expired':
        break;
      default:
        return FakeOrders._conflict(
          'payment_not_cancellable',
          'Ce paiement est déjà confirmé : il ne peut plus être annulé.',
        );
    }
    return FakeResponse.json(200, payment);
  }

  Future<FakeResponse> _simulate(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    final payment = _paymentFor(r, 4);
    if (payment == null) return _notFound;
    final outcome = (r.body as Map<String, dynamic>?)?['outcome'];
    if (outcome == 'succeeded') {
      succeed(payment);
    } else if (outcome == 'failed') {
      fail(payment);
    } else {
      return FakeResponse.error(
        400,
        'validation_failed',
        'Certaines informations sont invalides.',
        fields: {'outcome': 'Valeur attendue : succeeded ou failed.'},
      );
    }
    return FakeResponse.json(200, {'status': 'webhook_sent'});
  }

  void _set(Map<String, dynamic> payment, String status, [String reason = '']) {
    payment
      ..['status'] = status
      ..['failure_reason'] = reason
      ..['updated_at'] = orders.now().toIso8601String();
  }

  /// Le prestataire confirme [payment] (webhook vérifié), comme
  /// `orders.OnPaymentSucceeded` : appliqué même après une annulation ; la
  /// commande passe en attente de la boutique (après expiration : si le
  /// stock suivi est encore là, sinon elle est annulée) ; commande annulée
  /// avant le paiement : inchangée (à rembourser) ; déjà payée : doublon.
  void succeed(Map<String, dynamic> payment) {
    if (!{'pending', 'failed', 'expired'}.contains(payment['status'])) return;
    _set(payment, 'succeeded');
    final order = orders.orders.firstWhere(
      (o) => o['id'] == payment['order_id'],
    );
    switch (order['status']) {
      case 'pending_payment':
        orders.advance(
          order,
          'awaiting_seller',
          reason: 'Paiement confirmé par le prestataire.',
        );
      case 'expired' when orders._moveStock(order, -1):
        orders.advance(
          order,
          'awaiting_seller',
          reason: 'Paiement reçu après expiration, stock disponible.',
        );
      case 'expired':
        orders.advance(
          order,
          'cancelled',
          reason: 'Paiement reçu après expiration, stock épuisé.',
        );
      case 'cancelled':
        break;
      default:
        payment['is_duplicate'] = true;
    }
  }

  /// Donne [payment] à un autre compte (en-tête `Authorization`) : il
  /// devient introuvable pour le compte actuel.
  void giveTo(Map<String, dynamic> payment, String authorization) =>
      _buyerOf[payment['id'] as String] = authorization;

  /// Le prestataire refuse [payment] (code faux, solde insuffisant…).
  void fail(
    Map<String, dynamic> payment, [
    String reason = 'Paiement refusé ou annulé.',
  ]) {
    if (payment['status'] == 'pending') _set(payment, 'failed', reason);
  }
}

/// Commandes vues par le marchand, fidèles au module `orders` : commandes
/// payées seulement, transitions permises (sinon 409 `invalid_transition`),
/// délai de 15 min pour accepter (passé, la commande est annulée à la
/// requête suivante : le serveur, lui, l'annule par une tâche de fond lancée
/// à l'heure limite, et accepte encore la commande tant qu'elle n'a pas
/// tourné), code de remise compté
/// avant comparaison et bloqué au 5e essai, boutique suspendue (403).
class FakeSellerOrders {
  FakeSellerOrders(this.server, {this.shopId = 's1'}) {
    server
      ..on('GET', '/v1/seller/orders', _list)
      ..onPattern('GET', '/v1/seller/orders/([^/]+)', _get)
      ..onPattern(
        'POST',
        '/v1/seller/orders/([^/]+)/(accept|reject|preparing|ready|handover)',
        _action,
      );
  }

  final FakeApiServer server;

  /// Boutique du marchand : une autre est introuvable.
  final String shopId;

  /// Code de remise de toutes les commandes.
  static const handoverCode = '4827';

  /// Délai laissé au marchand pour accepter.
  static const sellerTimeout = Duration(minutes: 15);

  /// Commandes payées, de la plus ancienne à la plus récente.
  final orders = <Map<String, dynamic>>[];

  /// Prochaine erreur, une seule fois, pour la première requête dont
  /// « MÉTHODE chemin » contient la clé.
  final failures = <String, FakeResponse>{};

  /// Attendu avant de répondre (réseau lent).
  Future<void> Function(RecordedRequest request)? beforeRequest;

  /// Boutique suspendue par l'admin : 403 `shop_suspended`.
  var shopSuspended = false;

  /// Heure du serveur.
  DateTime Function() now = () => DateTime.now().toUtc();

  var _number = 1041;

  static String _uuid(int n) =>
      'c0000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

  /// Ajoute une commande payée à l'instant ([paidAgo] plus tôt), à
  /// accepter dans les 15 min qui suivent le paiement.
  Map<String, dynamic> add({
    String status = 'awaiting_seller',
    String fulfillment = 'pickup',
    String buyerFirstName = 'Koffi',
    Duration paidAgo = Duration.zero,
    int handoverAttempts = 0,
    String cancelReason = '',
    List<Map<String, dynamic>>? items,
  }) {
    final number = ++_number;
    final paid = now().subtract(paidAgo);
    final order = sellerOrderBody(
      id: _uuid(number),
      number: number,
      shopId: shopId,
      status: status,
      fulfillment: fulfillment,
      buyerFirstName: buyerFirstName,
      paidAt: paid,
      cancelReason: cancelReason,
      handoverAttempts: handoverAttempts,
      items: items,
    );
    // Créées dans l'ordre d'ajout, même ajoutées à la même seconde.
    order['created_at'] = paid
        .subtract(const Duration(minutes: 2))
        .add(Duration(milliseconds: number))
        .toIso8601String();
    orders.add(order);
    return order;
  }

  /// Commande [id] (pour les vérifications des tests).
  Map<String, dynamic> byId(String id) =>
      orders.firstWhere((o) => o['id'] == id);

  /// Annulation par l'acheteur (avant l'acceptation) ou par l'admin.
  void cancel(String id, String reason) =>
      _set(byId(id), 'cancelled', reason: reason);

  FakeResponse? _failure(RecordedRequest r) {
    for (final key in failures.keys) {
      if ('${r.method} ${r.path}'.contains(key)) return failures.remove(key);
    }
    return null;
  }

  /// Contrôles communs : réseau lent, panne programmée, boutique suspendue,
  /// délais dépassés.
  Future<FakeResponse?> _before(RecordedRequest r) async {
    if (beforeRequest case final wait?) await wait(r);
    if (_failure(r) case final f?) return f;
    if (shopSuspended) {
      return FakeResponse.error(
        403,
        'shop_suspended',
        "Cette boutique est suspendue. Contactez l'équipe ivia.",
      );
    }
    _expireLate();
    return null;
  }

  void _expireLate() {
    final at = now();
    for (final o in orders) {
      if (o['status'] != 'awaiting_seller') continue;
      if (at.isAfter(DateTime.parse(o['seller_deadline_at'] as String))) {
        _set(o, 'cancelled', reason: "Le marchand n'a pas répondu à temps.");
      }
    }
  }

  void _set(Map<String, dynamic> o, String status, {String? reason}) {
    final at = now().toIso8601String();
    o
      ..['status'] = status
      ..['updated_at'] = at;
    switch (status) {
      case 'accepted':
        o['accepted_at'] = at;
      case 'ready_for_pickup' || 'awaiting_driver':
        o['ready_at'] = at;
      case 'completed':
        o['completed_at'] = at;
      case 'cancelled':
        o
          ..['cancelled_at'] = at
          ..['cancel_reason'] = reason ?? '';
    }
  }

  static const _labels = {
    'awaiting_seller': 'en attente du marchand',
    'accepted': 'acceptée',
    'preparing': 'en préparation',
    'ready_for_pickup': 'prête à retirer',
    'awaiting_driver': "en attente d'un livreur",
    'driver_assigned': 'livreur en route vers la boutique',
    'picked_up': 'en cours de livraison',
    'delivered': 'livrée',
    'delivery_failed': 'échec de livraison',
    'returned_to_shop': 'revenue en boutique',
    'completed': 'retirée',
    'cancelled': 'annulée',
    'refunded': 'remboursée',
  };

  static FakeResponse _invalid(Map<String, dynamic> o) => FakeResponse.error(
    409,
    'invalid_transition',
    'Action impossible : la commande est « ${_labels[o['status']]} ».',
  );

  static final _notFound = FakeResponse.error(
    404,
    'order_not_found',
    'Commande introuvable.',
  );

  Map<String, dynamic>? _find(String id) =>
      orders.where((o) => o['id'] == id).firstOrNull;

  Future<FakeResponse> _list(RecordedRequest r) async {
    if (await _before(r) case final f?) return f;
    if (r.query['shop_id'] case final id? when id != shopId) {
      return FakeResponse.error(404, 'shop_not_found', 'Boutique introuvable.');
    }
    final offset = int.parse(r.query['offset'] ?? '0');
    final limit = int.parse(r.query['limit'] ?? '20');
    if (limit < 1 || limit > 100) {
      return FakeResponse.error(
        400,
        'validation_failed',
        'Certaines informations sont invalides.',
        fields: {'limit': 'Entre 1 et 100.'},
      );
    }
    final status = r.query['status'];
    // Comme le serveur : les plus récentes d'abord (`created_at`).
    final matching =
        [
          for (final o in orders)
            if (status == null || o['status'] == status) o,
        ]..sort(
          (a, b) =>
              (b['created_at'] as String).compareTo(a['created_at'] as String),
        );
    final page = matching.skip(offset).take(limit).toList();
    final more = offset + limit < matching.length;
    return FakeResponse.json(200, {
      'items': [for (final o in page) Map<String, dynamic>.of(o)],
      'next_offset': more ? offset + limit : null,
    });
  }

  Future<FakeResponse> _get(RecordedRequest r) async {
    if (await _before(r) case final f?) return f;
    final order = _find(r.path.split('/').last);
    if (order == null) return _notFound;
    return FakeResponse.json(200, Map<String, dynamic>.of(order));
  }

  Future<FakeResponse> _action(RecordedRequest r) async {
    if (await _before(r) case final f?) return f;
    final parts = r.path.split('/');
    final order = _find(parts[parts.length - 2]);
    if (order == null) return _notFound;
    final status = order['status'] as String;
    switch (parts.last) {
      case 'accept':
        if (status != 'awaiting_seller') return _invalid(order);
        _set(order, 'accepted');
      case 'reject':
        if (status != 'awaiting_seller') return _invalid(order);
        final body = r.body as Map<String, dynamic>? ?? const {};
        final reason = (body['reason'] as String? ?? '').trim();
        _set(
          order,
          'cancelled',
          reason: reason.isEmpty ? 'Refusée par le marchand.' : reason,
        );
      case 'preparing':
        if (status != 'accepted') return _invalid(order);
        _set(order, 'preparing');
      case 'ready':
        if (status != 'preparing') return _invalid(order);
        _set(
          order,
          order['fulfillment'] == 'delivery'
              ? 'awaiting_driver'
              : 'ready_for_pickup',
        );
      case 'handover':
        if (status != 'ready_for_pickup') return _invalid(order);
        final locked = FakeResponse.error(
          409,
          'handover_locked',
          "Trop d'essais : le code est bloqué. Contactez l'équipe ivia.",
        );
        // Essai compté avant la comparaison, comme le serveur.
        final attempts = order['handover_attempts'] as int;
        if (attempts >= maxHandoverAttempts) return locked;
        order['handover_attempts'] = attempts + 1;
        final body = r.body as Map<String, dynamic>? ?? const {};
        if (body['code'] != handoverCode) {
          if (attempts + 1 >= maxHandoverAttempts) return locked;
          return FakeResponse.error(
            422,
            'handover_code_invalid',
            'Code incorrect. Il reste '
                '${maxHandoverAttempts - attempts - 1} essai(s).',
          );
        }
        _set(order, 'completed');
    }
    return FakeResponse.json(200, Map<String, dynamic>.of(order));
  }
}
