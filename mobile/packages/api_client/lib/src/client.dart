import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'models.dart';

/// Client de l'API REST `/v1` (contrat : backend/api/openapi.yaml).
///
/// Aucun journal des requêtes : jeton, e-mail et code ne doivent jamais
/// apparaître dans les logs (docs/RULES.md).
class IviaApiClient {
  IviaApiClient({
    required ApiConfig config,
    this.onUnauthorized,
    HttpClientAdapter? adapter,
  }) : _uploadDio = Dio(
         BaseOptions(
           connectTimeout: const Duration(seconds: 10),
           sendTimeout: const Duration(seconds: 60),
           receiveTimeout: const Duration(seconds: 30),
         ),
       ),
       _dio = Dio(
         BaseOptions(
           baseUrl: config.baseUrl.toString(),
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 15),
           sendTimeout: const Duration(seconds: 15),
           contentType: Headers.jsonContentType,
           responseType: ResponseType.json,
         ),
       ) {
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
      _uploadDio.httpClientAdapter = adapter;
    }
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = this.token;
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onResponse: (response, handler) {
          _readServerClock(response.headers.value('date'));
          handler.next(response);
        },
      ),
    );
  }

  final Dio _dio;

  /// Écart entre l'heure du serveur et celle du téléphone, lu dans l'en-tête
  /// `Date` des réponses ; nul tant qu'il reste sous [_clockTolerance].
  Duration _clockOffset = Duration.zero;

  /// L'en-tête `Date` est à la seconde près et arrive après le trajet : en
  /// dessous, l'heure du téléphone fait foi.
  static const _clockTolerance = Duration(seconds: 30);

  /// Heure du serveur, estimée : à utiliser pour les délais fixés par le
  /// serveur (heure limite de paiement), qu'un téléphone mal réglé ne doit
  /// pas avancer ni retarder.
  DateTime now() => DateTime.now().add(_clockOffset);

  void _readServerClock(String? header) {
    final server = parseHttpDate(header);
    if (server == null) return;
    final offset = server.difference(DateTime.now());
    _clockOffset = offset.abs() < _clockTolerance ? Duration.zero : offset;
  }

  /// Envois vers les URL signées du stockage : sans intercepteur, le jeton
  /// de session ne doit jamais partir vers un autre serveur que l'API.
  final Dio _uploadDio;

  /// Jeton de la session ouverte ; `null` : appels anonymes.
  String? token;

  /// Appelé quand le serveur refuse le jeton (session expirée ou révoquée).
  /// Modifiable : l'état de session de l'app s'y abonne après la création
  /// du client.
  VoidCallback? onUnauthorized;

  @visibleForTesting
  Dio get debugDio => _dio;

  /// Envoie un code à 6 chiffres par e-mail. Même réponse que le compte
  /// existe ou non.
  Future<OtpRequested> requestOtp(String email) async {
    final json = await _send(
      'POST',
      '/v1/auth/otp',
      data: {'channel': 'email', 'recipient': normalizeEmail(email)},
    );
    return OtpRequested.fromJson(json);
  }

  /// Vérifie le code et ouvre une session (crée le compte au besoin).
  Future<Session> verifyOtp(String email, String code) async {
    final json = await _send(
      'POST',
      '/v1/auth/verify',
      data: {
        'channel': 'email',
        'recipient': normalizeEmail(email),
        'code': code,
      },
    );
    return Session.fromJson(json);
  }

  Future<User> getMe() async => User.fromJson(await _send('GET', '/v1/me'));

  /// Modifie le profil ; seuls les champs fournis sont envoyés.
  Future<User> updateMe({
    String? firstName,
    String? lastName,
    String? phone,
    bool? acceptPrivacyPolicy,
  }) async {
    final json = await _send(
      'PATCH',
      '/v1/me',
      data: {
        'first_name': ?firstName,
        'last_name': ?lastName,
        'phone': ?phone,
        'accept_privacy_policy': ?acceptPrivacyPolicy,
      },
    );
    return User.fromJson(json);
  }

  Future<List<Choice>> shopCategories() async =>
      _items(await _send('GET', '/v1/shop-categories'));

  /// Quartiers actifs (Lomé).
  Future<List<Choice>> neighborhoods() async =>
      _items(await _send('GET', '/v1/neighborhoods'));

  /// Crée une boutique, en attente de validation par l'admin.
  Future<Shop> createShop(ShopDraft draft) async =>
      Shop.fromJson(await _send('POST', '/v1/shops', data: draft.toJson()));

  /// Boutiques du marchand (rôle seller requis).
  Future<List<Shop>> myShops() async {
    final json = await _send('GET', '/v1/seller/shops');
    return [
      for (final item in json['items'] as List)
        Shop.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Catégories de produits actives, dans l'ordre d'affichage.
  Future<List<ProductCategory>> productCategories() async {
    final json = await _send('GET', '/v1/categories');
    return [
      for (final item in json['items'] as List)
        ProductCategory.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Produits de la boutique du marchand, filtrés par état et par nom
  /// (sans accents ni majuscules, côté serveur).
  Future<Page<Product>> sellerProducts(
    String shopId, {
    ProductStatus? status,
    String query = '',
    int offset = 0,
    int limit = 20,
  }) async {
    final json = await _send(
      'GET',
      '/v1/seller/shops/$shopId/products',
      query: {
        'status': ?status?.code,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'offset': '$offset',
        'limit': '$limit',
      },
    );
    return Page(
      items: [
        for (final item in json['items'] as List)
          Product.fromJson(item as Map<String, dynamic>),
      ],
      nextOffset: json['next_offset'] as int?,
    );
  }

  /// Nombre de produits de la boutique par état.
  Future<ProductCounts> productCounts(String shopId) async =>
      ProductCounts.fromJson(
        await _send('GET', '/v1/seller/shops/$shopId/product-counts'),
      );

  Future<Product> sellerProduct(String id) async =>
      Product.fromJson(await _send('GET', '/v1/seller/products/$id'));

  /// Ajoute un produit ; `isActive: false` crée un brouillon.
  Future<Product> createProduct(String shopId, ProductInput input) async =>
      Product.fromJson(
        await _send(
          'POST',
          '/v1/seller/shops/$shopId/products',
          data: input.toJson(),
        ),
      );

  /// Modifie un produit ; `isActive` publie ou retire.
  Future<Product> updateProduct(String id, ProductInput input) async =>
      Product.fromJson(
        await _send('PATCH', '/v1/seller/products/$id', data: input.toJson()),
      );

  /// Fixe la quantité d'un produit à stock suivi.
  Future<Product> setStock(String id, int quantity) async => Product.fromJson(
    await _send(
      'PUT',
      '/v1/seller/products/$id/stock',
      data: {'quantity': quantity, 'note': ''},
    ),
  );

  /// Recherche de produits publiés (route publique).
  Future<Page<ProductHit>> searchProducts(
    SearchQuery query, {
    int offset = 0,
    int limit = 20,
  }) async {
    final json = await _send(
      'GET',
      '/v1/search/products',
      query: {
        ...query.toParams(products: true),
        'offset': '$offset',
        'limit': '$limit',
      },
    );
    return Page(
      items: [
        for (final item in json['items'] as List)
          ProductHit.fromJson(item as Map<String, dynamic>),
      ],
      nextOffset: json['next_offset'] as int?,
    );
  }

  /// Recherche de boutiques publiées (route publique).
  Future<Page<ShopHit>> searchShops(
    SearchQuery query, {
    int offset = 0,
    int limit = 20,
  }) async {
    final json = await _send(
      'GET',
      '/v1/search/shops',
      query: {
        ...query.toParams(products: false),
        'offset': '$offset',
        'limit': '$limit',
      },
    );
    return Page(
      items: [
        for (final item in json['items'] as List)
          ShopHit.fromJson(item as Map<String, dynamic>),
      ],
      nextOffset: json['next_offset'] as int?,
    );
  }

  /// Fiche publique d'un produit en vente, avec sa boutique.
  Future<(Product, PublicShop)> publicProduct(String id) async {
    final json = await _send('GET', '/v1/products/$id');
    return (
      Product.fromJson(json['product'] as Map<String, dynamic>),
      PublicShop.fromJson(json['shop'] as Map<String, dynamic>),
    );
  }

  /// Fiche publique d'une boutique publiée.
  Future<PublicShop> publicShop(String id) async =>
      PublicShop.fromJson(await _send('GET', '/v1/shops/$id'));

  /// Panier de l'acheteur, recalculé au prix et au stock du moment.
  Future<Cart> cart() async => Cart.fromJson(await _send('GET', '/v1/cart'));

  /// Fixe la quantité totale de [productId] dans le panier (0 : retirer).
  /// Produit d'une autre boutique : 409 `cart_shop_conflict`, sauf avec
  /// [replaceCart], qui vide d'abord le panier.
  Future<Cart> setCartItem(
    String productId,
    int quantity, {
    bool replaceCart = false,
  }) async => Cart.fromJson(
    await _send(
      'PUT',
      '/v1/cart/items',
      data: {
        'product_id': productId,
        'quantity': quantity,
        'replace_cart': replaceCart,
      },
    ),
  );

  /// Vide le panier.
  Future<void> clearCart() => _send('DELETE', '/v1/cart');

  /// Récapitulatif de la commande du panier, sans rien enregistrer.
  Future<OrderQuote> quoteOrder({
    Fulfillment fulfillment = Fulfillment.pickup,
  }) async => OrderQuote.fromJson(
    await _send(
      'POST',
      '/v1/orders/quote',
      data: {'fulfillment': fulfillment.code},
    ),
  );

  /// Commande le panier : stock réservé, panier vidé, paiement attendu.
  /// [clientRequestId] (voir [newRequestId]) rend l'appel idempotent : un
  /// nouvel essai avec le même identifiant rend la même commande.
  Future<BuyerOrder> createOrder({
    required String clientRequestId,
    Fulfillment fulfillment = Fulfillment.pickup,
  }) async => BuyerOrder.fromJson(
    await _send(
      'POST',
      '/v1/orders',
      data: {
        'fulfillment': fulfillment.code,
        'client_request_id': clientRequestId,
      },
    ),
  );

  /// Commandes de l'acheteur, les plus récentes d'abord.
  Future<Page<BuyerOrder>> myOrders({int offset = 0, int limit = 50}) async {
    final json = await _send(
      'GET',
      '/v1/orders',
      query: {'offset': '$offset', 'limit': '$limit'},
    );
    return Page(
      items: [
        for (final item in json['items'] as List)
          BuyerOrder.fromJson(item as Map<String, dynamic>),
      ],
      nextOffset: json['next_offset'] as int?,
    );
  }

  /// Suivi d'une commande de l'acheteur (404 `order_not_found` sinon).
  Future<BuyerOrder> myOrder(String id) async =>
      BuyerOrder.fromJson(await _send('GET', '/v1/orders/$id'));

  /// Demande le paiement de la commande [orderId] : le payeur valide ensuite
  /// sur son téléphone. S'il y a déjà une demande en attente, le serveur la
  /// rend telle quelle (l'annuler d'abord pour changer de numéro).
  Future<Payment> startPayment(
    String orderId, {
    required PaymentOperator operator,
    required String phone,
  }) async => Payment.fromJson(
    await _send(
      'POST',
      '/v1/orders/$orderId/payments',
      data: {'operator': operator.code, 'phone': phone},
    ),
  );

  /// Paiements de la commande, les plus récents d'abord.
  Future<List<Payment>> orderPayments(String orderId) async {
    final json = await _send('GET', '/v1/orders/$orderId/payments');
    return [
      for (final item in json['items'] as List)
        Payment.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// État d'un paiement de l'acheteur (404 `payment_not_found` sinon).
  Future<Payment> payment(String id) async =>
      Payment.fromJson(await _send('GET', '/v1/payments/$id'));

  /// Abandonne une demande en attente (409 `payment_not_cancellable` si elle
  /// a déjà abouti).
  Future<Payment> cancelPayment(String id) async =>
      Payment.fromJson(await _send('POST', '/v1/payments/$id/cancel'));

  /// Fait aboutir ou échouer un paiement du faux prestataire, sur la route de
  /// développement `POST /v1/dev/payments/{id}/simulate` (API locale ou de
  /// test seulement).
  Future<void> devSimulatePayment(String id, {required bool succeeded}) =>
      _send(
        'POST',
        '/v1/dev/payments/$id/simulate',
        data: {'outcome': succeeded ? 'succeeded' : 'failed'},
      );

  /// Dossier livreur de l'utilisateur ; `null` : aucun dossier déposé.
  Future<DriverDossier?> driverMe() async {
    try {
      return DriverDossier.fromJson(await _send('GET', '/v1/driver/me'));
    } on ApiException catch (e) {
      if (e.code == 'driver_not_found') return null;
      rethrow;
    }
  }

  /// Dépose ou corrige la candidature (véhicule, immatriculation).
  Future<DriverDossier> applyAsDriver({
    required VehicleType vehicleType,
    required String vehiclePlate,
  }) async => DriverDossier.fromJson(
    await _send(
      'PUT',
      '/v1/driver/application',
      data: {'vehicle_type': vehicleType.code, 'vehicle_plate': vehiclePlate},
    ),
  );

  /// Ajoute au dossier un document déjà envoyé (`driver_document`).
  Future<DriverDossier> addDriverDocument(
    DriverDocumentKind kind,
    String objectKey,
  ) async => DriverDossier.fromJson(
    await _send(
      'POST',
      '/v1/driver/application/documents',
      data: {'kind': kind.code, 'object_key': objectKey},
    ),
  );

  /// Rattache au marchand une pièce déjà envoyée (`merchant_document`) ;
  /// rend les types de toutes ses pièces.
  Future<List<MerchantDocumentKind>> addMerchantDocument(
    MerchantDocumentKind kind,
    String objectKey,
  ) async {
    final json = await _send(
      'POST',
      '/v1/seller/documents',
      data: {'kind': kind.code, 'object_key': objectKey},
    );
    return merchantDocumentKinds(json['items'] as List);
  }

  /// Prépare l'envoi d'un fichier (URL signée).
  Future<PreparedUpload> prepareUpload({
    required String purpose,
    required String contentType,
    required int sizeBytes,
  }) async => PreparedUpload.fromJson(
    await _send(
      'POST',
      '/v1/uploads',
      data: {
        'purpose': purpose,
        'content_type': contentType,
        'size_bytes': sizeBytes,
      },
    ),
  );

  /// Envoie le fichier sur l'URL signée, avec les en-têtes imposés.
  Future<void> upload(PreparedUpload prepared, List<int> bytes) async {
    try {
      await _uploadDio.put<void>(
        prepared.url,
        data: Stream.value(bytes),
        options: Options(
          headers: {
            ...prepared.headers,
            Headers.contentLengthHeader: bytes.length,
          },
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  /// Dernier code envoyé à [email], lu sur la route de développement
  /// `POST /v1/dev/otp` (API locale ou de test seulement) ; `null` si la
  /// route n'existe pas ou n'a pas de code.
  Future<String?> devOtp(String email) async {
    try {
      final json = await _send(
        'POST',
        '/v1/dev/otp',
        data: {'recipient': normalizeEmail(email)},
      );
      return json['code'] as String?;
    } on ApiException {
      return null;
    }
  }

  /// Révoque la session courante côté serveur.
  Future<void> logout() => _send('POST', '/v1/auth/logout');

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  static List<Choice> _items(Map<String, dynamic> json) => [
    for (final item in json['items'] as List)
      Choice.fromJson(item as Map<String, dynamic>),
  ];

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? data,
    Map<String, String>? query,
  }) async {
    // Jeton envoyé : un 401 tardif d'une ancienne session ne doit pas
    // effacer la session ouverte depuis.
    final sentToken = token;
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method),
      );
      final body = response.data;
      return body is Map<String, dynamic> ? body : const {};
    } on DioException catch (e) {
      final error = _toApiException(e);
      if (sentToken != null && sentToken == token && error.statusCode == 401) {
        onUnauthorized?.call();
      }
      throw error;
    }
  }

  static ApiException _toApiException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const ApiException.network();
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        final body = e.response?.data;
        if (body is Map && body['error'] is Map) {
          final error = body['error'] as Map;
          final code = error['code'];
          final message = error['message'];
          if (code is String && message is String) {
            return ApiException(
              code: code,
              message: message,
              statusCode: status,
              fields: switch (error['fields']) {
                final Map fields => fields.map(
                  (k, v) => MapEntry(k.toString(), v.toString()),
                ),
                _ => const {},
              },
            );
          }
        }
        return ApiException.unknown(statusCode: status);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        // Erreur de socket non classée par dio : traitée comme réseau.
        return e.error is Exception && e.response == null
            ? const ApiException.network()
            : ApiException.unknown(statusCode: e.response?.statusCode);
    }
  }
}

/// Date d'un en-tête HTTP (« Mon, 02 Nov 2026 06:56:01 GMT ») ; `null` si
/// elle est absente ou illisible.
@visibleForTesting
DateTime? parseHttpDate(String? value) {
  final parts = value?.trim().split(RegExp(r'\s+'));
  if (parts == null || parts.length != 6 || parts[5] != 'GMT') return null;
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
  final month = months.indexOf(parts[2]) + 1;
  final time = parts[4].split(':');
  final day = int.tryParse(parts[1]);
  final year = int.tryParse(parts[3]);
  if (month == 0 || time.length != 3 || day == null || year == null) {
    return null;
  }
  final [h, m, sec] = [for (final t in time) int.tryParse(t)];
  if (h == null || m == null || sec == null) return null;
  return DateTime.utc(year, month, day, h, m, sec);
}
