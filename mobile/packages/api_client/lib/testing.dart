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
      'id':
          's${(_seq++).toString().padLeft(7, '0')}-0000-4000-8000-000000000000',
      'name': name,
      'description': '',
      'phone': '+22890123456',
      'address_text': 'Rue 248',
      'neighborhood_id': neighborhoodId,
      'neighborhood_name': neighborhoodId == beId ? 'Bè' : 'Tokoin',
      'location': location.toJson(),
      'logo_url': logoUrl,
      'accepting_orders': acceptingOrders,
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
    final id = 'p${n.toString().padLeft(7, '0')}-0000-4000-8000-000000000000';
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

  FakeResponse? _validate(RecordedRequest r) {
    final q = r.query;
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
    if (_validate(r) case final f?) return f;
    final q = r.query;
    final text = _fold(q['q'] ?? '');
    final point = _point(r);
    final radius = double.tryParse(q['radius_m'] ?? '');
    final min = int.tryParse(q['min_price'] ?? '');
    final max = int.tryParse(q['max_price'] ?? '');
    final hits = <(Map<String, dynamic>, double?)>[];
    for (final p in products) {
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
    hits.sort((a, b) {
      switch (q['sort']) {
        case 'distance':
          return a.$2!.compareTo(b.$2!);
        case 'price_asc':
          return (a.$1['price_xof'] as int).compareTo(b.$1['price_xof'] as int);
        case 'price_desc':
          return (b.$1['price_xof'] as int).compareTo(a.$1['price_xof'] as int);
      }
      return (b.$1['created_at'] as String).compareTo(
        a.$1['created_at'] as String,
      );
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
    if (_validate(r) case final f?) return f;
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
    if (q['sort'] == 'distance') hits.sort((a, b) => a.$2!.compareTo(b.$2!));
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
    if (p == null) {
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
