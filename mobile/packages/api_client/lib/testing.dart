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
      final issue = p['is_active'] == false || shop == null
          ? "Ce produit n'est plus disponible."
          : stock != null && stock < qty
          ? 'Plus que $stock en stock.'
          : '';
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
    order
      ..['status'] = status
      ..['updated_at'] = when;
    if (status == 'cancelled') order['cancel_reason'] = reason;
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
    if (providerDown) {
      return FakeResponse.error(
        503,
        'payment_provider_unavailable',
        "Le paiement n'a pas pu être lancé. Réessayez dans un instant.",
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

  /// Le prestataire confirme [payment] (webhook vérifié) : appliqué même
  /// après une annulation ; la commande passe en attente de la boutique, ou
  /// le paiement est marqué en double si elle était déjà payée.
  void succeed(Map<String, dynamic> payment) {
    if (!{'pending', 'failed', 'expired'}.contains(payment['status'])) return;
    _set(payment, 'succeeded');
    final order = orders.orders.firstWhere(
      (o) => o['id'] == payment['order_id'],
    );
    if (order['status'] == 'pending_payment' || order['status'] == 'expired') {
      orders.advance(
        order,
        'awaiting_seller',
        reason: 'Paiement confirmé par le prestataire.',
      );
    } else {
      payment['is_duplicate'] = true;
    }
  }

  /// Le prestataire refuse [payment] (code faux, solde insuffisant…).
  void fail(
    Map<String, dynamic> payment, [
    String reason = 'Paiement refusé ou annulé.',
  ]) {
    if (payment['status'] == 'pending') _set(payment, 'failed', reason);
  }
}
