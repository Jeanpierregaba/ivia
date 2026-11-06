import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'models.dart';
import 'promo.dart';

part 'driver_work.dart';
part 'pharmacist.dart';
part 'pharmacy.dart';
part 'seller_money.dart';

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
          if (token != null && options.extra['anonymous'] != true) {
            options.headers['Authorization'] = 'Bearer $token';
          }
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

  /// Jeton de rafraîchissement (connexion par numéro) : sert à renouveler
  /// [token] quand le serveur répond `access_token_expired`.
  String? refreshToken;

  /// Appelé après chaque renouvellement : l'app garde les nouveaux jetons
  /// dans son stockage sécurisé.
  void Function(Session session)? onTokensRefreshed;

  /// Renouvellement en cours : plusieurs requêtes refusées en même temps
  /// n'en déclenchent qu'un (le serveur révoque la session si un ancien
  /// jeton de rafraîchissement revient).
  Future<bool>? _refreshing;

  /// Appelé quand le serveur refuse le jeton (session expirée ou révoquée).
  /// Modifiable : l'état de session de l'app s'y abonne après la création
  /// du client.
  VoidCallback? onUnauthorized;

  @visibleForTesting
  Dio get debugDio => _dio;

  // --- Connexion par numéro (ADR 0012) --------------------------------------

  /// Envoie un code par WhatsApp (SMS en secours, ou SMS si [channel] le
  /// demande). Même réponse que le numéro ait un compte ou non.
  Future<OtpRequested> requestPhoneCode(
    String phone,
    DeviceInfo device, {
    OtpChannel channel = OtpChannel.whatsapp,
  }) async => OtpRequested.fromJson(
    await _send(
      'POST',
      '/v1/auth/phone/code',
      data: {'phone': phone, 'channel': channel.code, ...device.toJson()},
    ),
  );

  /// Vérifie le code : session ouverte, ou inscription à terminer.
  Future<PhoneVerifyResult> verifyPhone(
    String phone,
    String code,
    DeviceInfo device,
  ) async => PhoneVerifyResult.fromJson(
    await _send(
      'POST',
      '/v1/auth/phone/verify',
      data: {'phone': phone, 'code': code, ...device.toJson()},
    ),
  );

  /// Crée le compte d'un numéro vérifié et ouvre la session.
  Future<Session> phoneSignup({
    required String signupToken,
    required String firstName,
    required String lastName,
    required DeviceInfo device,
  }) async => Session.fromJson(
    await _send(
      'POST',
      '/v1/auth/phone/signup',
      data: {
        'signup_token': signupToken,
        'first_name': firstName,
        'last_name': lastName,
        'accept_privacy_policy': true,
        ...device.toJson(),
      },
    ),
  );

  /// Appareils connectés au compte.
  Future<List<SessionView>> sessions() async {
    final json = await _send('GET', '/v1/me/sessions');
    return [
      for (final item in json['items'] as List)
        SessionView.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Déconnecte un autre appareil.
  Future<void> revokeSession(String id) =>
      _send('DELETE', '/v1/me/sessions/$id');

  /// Déconnecte tous les appareils, celui-ci compris.
  Future<void> logoutAll() => _send('POST', '/v1/auth/logout-all');

  /// Changement de numéro : code envoyé au nouveau numéro.
  Future<OtpRequested> requestPhoneChange(
    String phone, {
    OtpChannel channel = OtpChannel.whatsapp,
  }) async => OtpRequested.fromJson(
    await _send(
      'POST',
      '/v1/me/phone/code',
      data: {'phone': phone, 'channel': channel.code},
    ),
  );

  /// Changement de numéro : confirmation par le code reçu.
  Future<User> confirmPhoneChange(String phone, String code) async =>
      User.fromJson(
        await _send(
          'POST',
          '/v1/me/phone',
          data: {'phone': phone, 'code': code},
        ),
      );

  /// Renouvelle les jetons ; `false` si la session est refusée.
  Future<bool> _refresh() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final future = _doRefresh().whenComplete(() => _refreshing = null);
    _refreshing = future;
    return future;
  }

  Future<bool> _doRefresh() async {
    final refresh = refreshToken;
    if (refresh == null) return false;
    try {
      final response = await _dio.request<Object?>(
        '/v1/auth/refresh',
        data: {'refresh_token': refresh},
        // Sans jeton d'accès : l'intercepteur n'en met que si `token` existe.
        options: Options(method: 'POST', extra: {'anonymous': true}),
      );
      final body = response.data;
      if (body is! Map<String, dynamic>) return false;
      final session = Session.fromJson(body);
      // Session fermée pendant le renouvellement : rien à garder.
      if (refreshToken != refresh) return false;
      token = session.token;
      refreshToken = session.refreshToken;
      onTokensRefreshed?.call(session);
      return true;
    } on DioException catch (e) {
      final error = _toApiException(e);
      if (error.isNetwork) throw error;
      return false;
    }
  }

  Future<User> getMe() async => User.fromJson(await _send('GET', '/v1/me'));

  /// Modifie le profil ; seuls les champs fournis sont envoyés.
  Future<User> updateMe({
    String? firstName,
    String? lastName,
    String? phone,
    bool? acceptPrivacyPolicy,
    String? avatarKey,
  }) async {
    final json = await _send(
      'PATCH',
      '/v1/me',
      data: {
        'first_name': ?firstName,
        'last_name': ?lastName,
        'phone': ?phone,
        'accept_privacy_policy': ?acceptPrivacyPolicy,
        'avatar_key': ?avatarKey,
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

  /// Fil publicitaire de l'app (route publique) : visuels en cours,
  /// produits mis en avant et réglages de diffusion.
  Future<PromoFeed> promoFeed({String app = 'buyer'}) async =>
      PromoFeed.fromJson(
        await _send('GET', '/v1/promo/feed', query: {'app': app}),
      );

  /// Envoie des événements publicitaires anonymes ([sessionId] : tiré au
  /// hasard par l'app, sans lien avec le compte).
  Future<void> sendPromoEvents(
    List<PromoEvent> events, {
    required String sessionId,
    String app = 'buyer',
  }) async {
    if (events.isEmpty) return;
    await _send(
      'POST',
      '/v1/promo/events',
      data: {
        'app': app,
        'session_id': sessionId,
        'events': [for (final e in events) e.toJson()],
      },
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
    String? addressId,
  }) async => OrderQuote.fromJson(
    await _send(
      'POST',
      '/v1/orders/quote',
      data: {'fulfillment': fulfillment.code, 'address_id': ?addressId},
    ),
  );

  /// Commande le panier : stock réservé, panier vidé, paiement attendu.
  /// [clientRequestId] (voir [newRequestId]) rend l'appel idempotent : un
  /// nouvel essai avec le même identifiant rend la même commande.
  Future<BuyerOrder> createOrder({
    required String clientRequestId,
    Fulfillment fulfillment = Fulfillment.pickup,
    String? addressId,
  }) async => BuyerOrder.fromJson(
    await _send(
      'POST',
      '/v1/orders',
      data: {
        'fulfillment': fulfillment.code,
        'address_id': ?addressId,
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

  /// Annule une commande de l'acheteur, possible tant que la boutique ne l'a
  /// pas acceptée (409 `cannot_cancel` sinon) ; payée, elle est remboursée
  /// intégralement par l'équipe ivia.
  Future<BuyerOrder> cancelOrder(String id) async =>
      BuyerOrder.fromJson(await _send('POST', '/v1/orders/$id/cancel'));

  /// Commandes payées des boutiques du marchand (ou de [shopId]), les plus
  /// récentes d'abord ; [status] filtre sur un statut.
  Future<Page<SellerOrder>> sellerOrders({
    String? shopId,
    OrderStatus? status,
    int offset = 0,
    int limit = 100,
  }) async {
    final json = await _send(
      'GET',
      '/v1/seller/orders',
      query: {
        'shop_id': ?shopId,
        'status': ?status?.code,
        'offset': '$offset',
        'limit': '$limit',
      },
    );
    return Page(
      items: [
        for (final item in json['items'] as List)
          SellerOrder.fromJson(item as Map<String, dynamic>),
      ],
      nextOffset: json['next_offset'] as int?,
    );
  }

  /// Une commande d'une boutique du marchand (404 `order_not_found` sinon).
  Future<SellerOrder> sellerOrder(String id) async =>
      SellerOrder.fromJson(await _send('GET', '/v1/seller/orders/$id'));

  /// Accepte une nouvelle commande (et confirme la disponibilité des
  /// produits à stock non suivi).
  Future<SellerOrder> acceptOrder(String id) => _sellerAction(id, 'accept');

  /// Refuse une nouvelle commande : annulée, l'acheteur est remboursé et
  /// voit [reason].
  Future<SellerOrder> rejectOrder(String id, String reason) =>
      _sellerAction(id, 'reject', {'reason': reason});

  /// Passe une commande acceptée en préparation.
  Future<SellerOrder> startPreparingOrder(String id) =>
      _sellerAction(id, 'preparing');

  /// Commande prête : à retirer (retrait) ou en attente d'un livreur
  /// (livraison).
  Future<SellerOrder> markOrderReady(String id) => _sellerAction(id, 'ready');

  /// Remet une commande à retirer contre le [code] de l'acheteur (422
  /// `handover_code_invalid`, puis 409 `handover_locked` après 5 essais).
  /// Le code n'est ni gardé ni journalisé.
  Future<SellerOrder> handOverOrder(String id, String code) =>
      _sellerAction(id, 'handover', {'code': code});

  Future<SellerOrder> _sellerAction(
    String id,
    String action, [
    Map<String, dynamic>? data,
  ]) async => SellerOrder.fromJson(
    await _send('POST', '/v1/seller/orders/$id/$action', data: data),
  );

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

  /// Dernier code envoyé au numéro [phone] (format +228…), lu sur la route
  /// de développement `POST /v1/dev/otp` (API locale ou de test seulement) ;
  /// `null` si la route n'existe pas ou n'a pas de code.
  Future<String?> devOtp(String phone) async {
    try {
      final json = await _send(
        'POST',
        '/v1/dev/otp',
        data: {'recipient': phone.trim()},
      );
      return json['code'] as String?;
    } on ApiException {
      return null;
    }
  }

  /// Révoque la session courante côté serveur.
  /// Supprime le compte (refusé s'il reste une commande ou une course en cours).
  Future<void> deleteAccount() => _send('DELETE', '/v1/me');

  Future<void> logout() => _send('POST', '/v1/auth/logout');

  static List<Choice> _items(Map<String, dynamic> json) => [
    for (final item in json['items'] as List)
      Choice.fromJson(item as Map<String, dynamic>),
  ];

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? data,
    Map<String, String>? query,
    bool retried = false,
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
      if (error.code == 'access_token_expired' &&
          sentToken != null &&
          !retried) {
        // Jeton d'accès court expiré : renouvelé sans rien demander, puis la
        // requête est rejouée une fois. Un autre appel l'a peut-être déjà
        // renouvelé (jeton changé depuis l'envoi).
        if (token != sentToken || await _refresh()) {
          return _send(method, path, data: data, query: query, retried: true);
        }
      }
      if (sentToken != null && token == sentToken && error.statusCode == 401) {
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
