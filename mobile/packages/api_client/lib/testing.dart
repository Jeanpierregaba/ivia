/// Faux serveur et réponses types, pour les tests des apps et de ce paquet.
/// À n'importer que depuis `test/`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

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
      },
    );
  }

  @override
  void close({bool force = false}) {}
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

/// Boutique type (schéma `Shop`).
Map<String, dynamic> shopBody({String status = 'pending_review'}) => {
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
  var _clock = DateTime.utc(2026, 10, 31, 10);
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

  FakeResponse _list(RecordedRequest r) {
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
