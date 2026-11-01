/// Profil de l'utilisateur connecté (schéma `User` de openapi.yaml).
class User {
  const User({
    required this.id,
    required this.email,
    required this.phone,
    required this.firstName,
    required this.lastName,
    required this.roles,
    required this.privacyConsentAt,
    required this.profileComplete,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    firstName: json['first_name'] as String,
    lastName: json['last_name'] as String,
    roles: List<String>.from(json['roles'] as List),
    privacyConsentAt: _date(json['privacy_consent_at']),
    profileComplete: json['profile_complete'] as bool,
  );

  final String id;
  final String? email;

  /// Format +228XXXXXXXX.
  final String? phone;
  final String firstName;
  final String lastName;
  final List<String> roles;
  final DateTime? privacyConsentAt;

  /// Prénom, téléphone et consentement renseignés.
  final bool profileComplete;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'phone': phone,
    'first_name': firstName,
    'last_name': lastName,
    'roles': roles,
    'privacy_consent_at': privacyConsentAt?.toUtc().toIso8601String(),
    'profile_complete': profileComplete,
  };
}

/// Session ouverte par `POST /v1/auth/verify`.
class Session {
  const Session({
    required this.token,
    required this.isNewUser,
    required this.user,
  });

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    token: json['token'] as String,
    isNewUser: json['is_new_user'] as bool,
    user: User.fromJson(json['user'] as Map<String, dynamic>),
  );

  /// Jeton opaque : jamais affiché ni journalisé.
  final String token;
  final bool isNewUser;
  final User user;
}

/// Réponse à une demande de code (`POST /v1/auth/otp`).
class OtpRequested {
  const OtpRequested({required this.expiresIn, required this.resendAfter});

  factory OtpRequested.fromJson(Map<String, dynamic> json) => OtpRequested(
    expiresIn: Duration(seconds: json['expires_in_seconds'] as int),
    resendAfter: Duration(seconds: json['resend_after_seconds'] as int),
  );

  final Duration expiresIn;
  final Duration resendAfter;
}

/// Position (schéma `Point`).
class GeoPoint {
  const GeoPoint({required this.lat, required this.lng});

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
  );

  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

/// Élément d'une liste de choix (catégorie de boutique, quartier).
class Choice {
  const Choice({required this.id, required this.name});

  factory Choice.fromJson(Map<String, dynamic> json) =>
      Choice(id: json['id'] as String, name: json['name'] as String);

  final String id;
  final String name;
}

/// Statut d'une boutique.
enum ShopStatus {
  pendingReview('pending_review'),
  published('published'),
  rejected('rejected'),
  suspended('suspended');

  const ShopStatus(this.code);

  final String code;

  static ShopStatus parse(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => pendingReview);
}

/// Boutique vue par son marchand (schéma `Shop`).
class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.status,
    required this.statusReason,
    required this.neighborhoodName,
    required this.categoryName,
    required this.logoUrl,
  });

  factory Shop.fromJson(Map<String, dynamic> json) => Shop(
    id: json['id'] as String,
    name: json['name'] as String,
    status: ShopStatus.parse(json['status'] as String),
    statusReason: json['status_reason'] as String? ?? '',
    neighborhoodName: json['neighborhood_name'] as String? ?? '',
    categoryName: json['category_name'] as String? ?? '',
    logoUrl: json['logo_url'] as String?,
  );

  final String id;
  final String name;
  final ShopStatus status;

  /// Motif d'un refus ou d'une suspension, donné par l'admin.
  final String statusReason;
  final String neighborhoodName;
  final String categoryName;
  final String? logoUrl;
}

/// Boutique à créer (schéma `ShopInput`).
class ShopDraft {
  const ShopDraft({
    required this.name,
    required this.categoryId,
    required this.phone,
    required this.addressText,
    required this.neighborhoodId,
    required this.location,
    this.logoKey,
  });

  final String name;
  final String categoryId;

  /// Format +228XXXXXXXX.
  final String phone;
  final String addressText;
  final String? neighborhoodId;
  final GeoPoint location;
  final String? logoKey;

  Map<String, dynamic> toJson() => {
    'name': name,
    'category_id': categoryId,
    'phone': phone,
    'address_text': addressText,
    'neighborhood_id': neighborhoodId,
    'location': location.toJson(),
    'logo_key': ?logoKey,
  };
}

/// Envoi de fichier préparé par `POST /v1/uploads` (schéma `Upload`).
class PreparedUpload {
  const PreparedUpload({
    required this.objectKey,
    required this.url,
    required this.headers,
  });

  factory PreparedUpload.fromJson(Map<String, dynamic> json) {
    final upload = json['upload'] as Map<String, dynamic>;
    // Le client envoie en PUT : toute autre méthode est un changement de
    // contrat à traiter explicitement.
    if (upload['method'] != 'PUT') {
      throw FormatException(
        'Méthode d\'envoi inattendue : ${upload['method']}',
      );
    }
    return PreparedUpload(
      objectKey: json['object_key'] as String,
      url: upload['url'] as String,
      headers: Map<String, String>.from(upload['headers'] as Map),
    );
  }

  /// À transmettre ensuite (ex. `logo_key`).
  final String objectKey;

  /// URL signée, valable 5 minutes : à envoyer en PUT, sans jeton.
  final String url;
  final Map<String, String> headers;
}

/// Catégorie de véhicule d'un livreur.
enum VehicleType {
  motorbike('motorbike'),
  car('car');

  const VehicleType(this.code);

  final String code;

  static VehicleType parse(String code) =>
      values.firstWhere((v) => v.code == code, orElse: () => motorbike);
}

/// Type d'un document du dossier livreur.
enum DriverDocumentKind {
  idCard('id_card'),
  drivingLicense('driving_license'),
  vehicleRegistration('vehicle_registration'),
  photo('photo'),
  other('other');

  const DriverDocumentKind(this.code);

  final String code;

  static DriverDocumentKind parse(String code) =>
      values.firstWhere((k) => k.code == code, orElse: () => other);
}

/// Décision de l'admin sur un dossier livreur.
enum DriverReview {
  pending('pending_review'),
  approved('approved'),
  rejected('rejected');

  const DriverReview(this.code);

  final String code;

  static DriverReview parse(String code) =>
      values.firstWhere((r) => r.code == code, orElse: () => pending);
}

/// Dossier du livreur connecté (schéma `Driver`). Les documents ne sont
/// connus que par leur type : leur lien est réservé aux admins.
class DriverDossier {
  const DriverDossier({
    required this.review,
    required this.reviewNote,
    required this.suspended,
    required this.suspensionReason,
    required this.vehicleType,
    required this.vehiclePlate,
    required this.documents,
  });

  factory DriverDossier.fromJson(Map<String, dynamic> json) => DriverDossier(
    review: DriverReview.parse(json['review_status'] as String),
    reviewNote: json['review_note'] as String? ?? '',
    suspended: json['status'] == 'suspended',
    suspensionReason: json['suspension_reason'] as String? ?? '',
    vehicleType: VehicleType.parse(json['vehicle_type'] as String),
    vehiclePlate: json['vehicle_plate'] as String,
    documents: [
      for (final doc in json['documents'] as List? ?? const [])
        DriverDocumentKind.parse((doc as Map)['kind'] as String),
    ],
  );

  final DriverReview review;

  /// Motif d'un refus, donné par l'admin.
  final String reviewNote;
  final bool suspended;
  final String suspensionReason;
  final VehicleType vehicleType;
  final String vehiclePlate;
  final List<DriverDocumentKind> documents;
}

/// Page d'une liste paginée (`items`, `next_offset`).
class Page<T> {
  const Page({required this.items, required this.nextOffset});

  final List<T> items;

  /// Décalage de la page suivante ; `null` : dernière page.
  final int? nextOffset;
}

/// Catégorie de produits (deux niveaux au plus).
class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    required this.parentId,
  });

  factory ProductCategory.fromJson(Map<String, dynamic> json) =>
      ProductCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        parentId: json['parent_id'] as String?,
      );

  final String id;
  final String name;
  final String? parentId;
}

/// État de publication d'un produit.
enum ProductStatus {
  /// En vente : visible des acheteurs si la boutique est publiée.
  active('active'),

  /// Enregistré, jamais publié.
  draft('draft'),

  /// Publié puis retiré par le marchand.
  withdrawn('withdrawn');

  const ProductStatus(this.code);

  final String code;

  static ProductStatus parse(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => draft);
}

/// Taille de colis : elle détermine les véhicules de livraison possibles.
enum ParcelSize {
  small('small'),
  medium('medium'),
  large('large');

  const ParcelSize(this.code);

  final String code;

  static ParcelSize parse(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => medium);
}

/// Stock suivi (quantité connue) ou non suivi (disponibilité confirmée à
/// chaque commande).
enum StockMode {
  tracked('tracked'),
  untracked('untracked');

  const StockMode(this.code);

  final String code;

  static StockMode parse(String code) =>
      values.firstWhere((m) => m.code == code, orElse: () => untracked);
}

/// Photo d'un produit ; la première est la principale.
class ProductImage {
  const ProductImage({required this.url, required this.objectKey});

  factory ProductImage.fromJson(Map<String, dynamic> json) => ProductImage(
    url: json['url'] as String,
    objectKey: json['object_key'] as String,
  );

  final String url;

  /// À renvoyer dans `image_keys` pour garder la photo.
  final String objectKey;
}

/// Produit vu par son marchand (schéma `Product`).
class Product {
  const Product({
    required this.id,
    required this.shopId,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.priceXof,
    required this.parcelSize,
    required this.stockMode,
    required this.stockQuantity,
    required this.available,
    required this.status,
    required this.publishedAt,
    required this.withdrawnAt,
    required this.images,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    shopId: json['shop_id'] as String,
    categoryId: json['category_id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    priceXof: json['price_xof'] as int,
    parcelSize: ParcelSize.parse(json['parcel_size'] as String),
    stockMode: StockMode.parse(json['stock_mode'] as String),
    stockQuantity: json['stock_quantity'] as int?,
    available: json['available'] as bool,
    status: ProductStatus.parse(json['status'] as String),
    publishedAt: _date(json['published_at']),
    withdrawnAt: _date(json['withdrawn_at']),
    images: [
      for (final image in json['images'] as List? ?? const [])
        ProductImage.fromJson(image as Map<String, dynamic>),
    ],
  );

  final String id;
  final String shopId;
  final String categoryId;
  final String name;
  final String description;

  /// Prix en FCFA (entier).
  final int priceXof;
  final ParcelSize parcelSize;
  final StockMode stockMode;

  /// Quantité d'un stock suivi ; `null` : stock non suivi.
  final int? stockQuantity;

  /// En vente et en stock.
  final bool available;
  final ProductStatus status;

  /// Dernière mise en vente ; `null` : brouillon.
  final DateTime? publishedAt;

  /// Dernier retrait ; `null` : en vente ou brouillon.
  final DateTime? withdrawnAt;
  final List<ProductImage> images;

  /// Stock suivi épuisé.
  bool get soldOut =>
      stockMode == StockMode.tracked && (stockQuantity ?? 0) <= 0;
}

/// Produit à créer ou à modifier (schéma `ProductInput`).
class ProductInput {
  const ProductInput({
    required this.categoryId,
    required this.name,
    required this.description,
    required this.priceXof,
    required this.parcelSize,
    required this.imageKeys,
    this.stockMode,
    this.stockQuantity,
    this.isActive,
  });

  final String categoryId;
  final String name;
  final String description;
  final int priceXof;
  final ParcelSize parcelSize;

  /// Clés des photos, la principale d'abord (toutes envoyées).
  final List<String> imageKeys;

  /// À la création seulement : le mode ne change plus ensuite.
  final StockMode? stockMode;

  /// À la création d'un produit suivi.
  final int? stockQuantity;

  /// Création : `false` crée un brouillon. Modification : `null` garde l'état.
  final bool? isActive;

  Map<String, dynamic> toJson() => {
    'category_id': categoryId,
    'name': name,
    'description': description,
    'price_xof': priceXof,
    'parcel_size': parcelSize.code,
    'image_keys': imageKeys,
    'stock_mode': ?stockMode?.code,
    'stock_quantity': ?stockQuantity,
    'is_active': ?isActive,
  };
}

/// Nombre de produits d'une boutique par état.
class ProductCounts {
  const ProductCounts({
    required this.active,
    required this.draft,
    required this.withdrawn,
  });

  factory ProductCounts.fromJson(Map<String, dynamic> json) => ProductCounts(
    active: json['active'] as int,
    draft: json['draft'] as int,
    withdrawn: json['withdrawn'] as int,
  );

  final int active;
  final int draft;
  final int withdrawn;

  int get total => active + draft + withdrawn;

  int of(ProductStatus status) => switch (status) {
    ProductStatus.active => active,
    ProductStatus.draft => draft,
    ProductStatus.withdrawn => withdrawn,
  };
}

DateTime? _date(Object? value) => switch (value) {
  final String at => DateTime.parse(at),
  _ => null,
};

/// Tri des résultats de recherche.
enum SearchSort {
  relevance('relevance'),
  distance('distance'),
  priceAsc('price_asc'),
  priceDesc('price_desc');

  const SearchSort(this.code);

  final String code;
}

/// Paramètres d'une recherche de produits ou de boutiques. Égalité de
/// valeur : sert de clé aux listes de résultats.
class SearchQuery {
  const SearchQuery({
    this.text = '',
    this.point,
    this.radiusM,
    this.neighborhoodId,
    this.categoryId,
    this.shopId,
    this.minPrice,
    this.maxPrice,
    this.inStockOnly = false,
    this.sort = SearchSort.relevance,
  });

  final String text;

  /// Position de l'acheteur : distances calculées, tri par distance permis.
  final GeoPoint? point;

  /// Rayon autour de [point], en mètres.
  final int? radiusM;
  final String? neighborhoodId;
  final String? categoryId;
  final String? shopId;
  final int? minPrice;
  final int? maxPrice;
  final bool inStockOnly;
  final SearchSort sort;

  /// Paramètres d'URL ; [products] : filtres propres aux produits inclus.
  ///
  /// La position est arrondie à 3 décimales (environ 110 m) : elle part dans
  /// l'URL, qui peut être journalisée (ADR 0010). Les boutiques ne se trient
  /// que par pertinence ou distance : un tri par prix y devient pertinence.
  Map<String, String> toParams({required bool products}) {
    final q = text.trim();
    final p = point;
    final s =
        !products &&
            (sort == SearchSort.priceAsc || sort == SearchSort.priceDesc)
        ? SearchSort.relevance
        : sort;
    return {
      if (q.isNotEmpty) 'q': q,
      if (p != null) 'lat': p.lat.toStringAsFixed(3),
      if (p != null) 'lng': p.lng.toStringAsFixed(3),
      if (p != null && radiusM != null) 'radius_m': '$radiusM',
      'neighborhood_id': ?neighborhoodId,
      if (products) ...{
        'category_id': ?categoryId,
        'shop_id': ?shopId,
        if (minPrice != null) 'min_price': '$minPrice',
        if (maxPrice != null) 'max_price': '$maxPrice',
        if (inStockOnly) 'in_stock': 'true',
      },
      'sort': s.code,
    };
  }

  SearchQuery copyWith({
    String? text,
    GeoPoint? Function()? point,
    int? Function()? radiusM,
    String? Function()? neighborhoodId,
    String? Function()? categoryId,
    String? Function()? shopId,
    int? Function()? minPrice,
    int? Function()? maxPrice,
    bool? inStockOnly,
    SearchSort? sort,
  }) => SearchQuery(
    text: text ?? this.text,
    point: point == null ? this.point : point(),
    radiusM: radiusM == null ? this.radiusM : radiusM(),
    neighborhoodId: neighborhoodId == null
        ? this.neighborhoodId
        : neighborhoodId(),
    categoryId: categoryId == null ? this.categoryId : categoryId(),
    shopId: shopId == null ? this.shopId : shopId(),
    minPrice: minPrice == null ? this.minPrice : minPrice(),
    maxPrice: maxPrice == null ? this.maxPrice : maxPrice(),
    inStockOnly: inStockOnly ?? this.inStockOnly,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      other is SearchQuery &&
      other.text == text &&
      other.point == point &&
      other.radiusM == radiusM &&
      other.neighborhoodId == neighborhoodId &&
      other.categoryId == categoryId &&
      other.shopId == shopId &&
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice &&
      other.inStockOnly == inStockOnly &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    text,
    point,
    radiusM,
    neighborhoodId,
    categoryId,
    shopId,
    minPrice,
    maxPrice,
    inStockOnly,
    sort,
  );
}

/// Produit trouvé (schéma `ProductHit`).
class ProductHit {
  const ProductHit({
    required this.id,
    required this.shopId,
    required this.name,
    required this.priceXof,
    required this.parcelSize,
    required this.shopName,
    required this.neighborhoodId,
    required this.imageUrl,
    required this.inStock,
    required this.distanceM,
  });

  factory ProductHit.fromJson(Map<String, dynamic> json) => ProductHit(
    id: json['id'] as String,
    shopId: json['shop_id'] as String,
    name: json['name'] as String,
    priceXof: json['price_xof'] as int,
    parcelSize: ParcelSize.parse(json['parcel_size'] as String),
    shopName: json['shop_name'] as String,
    neighborhoodId: json['neighborhood_id'] as String?,
    imageUrl: json['image_url'] as String?,
    inStock: json['in_stock'] as bool,
    distanceM: json['distance_m'] as int?,
  );

  final String id;
  final String shopId;
  final String name;
  final int priceXof;
  final ParcelSize parcelSize;
  final String shopName;
  final String? neighborhoodId;
  final String? imageUrl;
  final bool inStock;

  /// Distance à la position envoyée ; `null` sans position.
  final int? distanceM;
}

/// Boutique trouvée (schéma `ShopHit`).
class ShopHit {
  const ShopHit({
    required this.id,
    required this.name,
    required this.neighborhoodId,
    required this.logoUrl,
    required this.acceptingOrders,
    required this.distanceM,
  });

  factory ShopHit.fromJson(Map<String, dynamic> json) => ShopHit(
    id: json['id'] as String,
    name: json['name'] as String,
    neighborhoodId: json['neighborhood_id'] as String?,
    logoUrl: json['logo_url'] as String?,
    acceptingOrders: json['accepting_orders'] as bool,
    distanceM: json['distance_m'] as int?,
  );

  final String id;
  final String name;
  final String? neighborhoodId;
  final String? logoUrl;
  final bool acceptingOrders;
  final int? distanceM;
}

/// Boutique vue par l'acheteur (schéma `PublicShop`).
class PublicShop {
  const PublicShop({
    required this.id,
    required this.name,
    required this.description,
    required this.addressText,
    required this.neighborhoodName,
    required this.location,
    required this.logoUrl,
    required this.acceptingOrders,
  });

  factory PublicShop.fromJson(Map<String, dynamic> json) => PublicShop(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    addressText: json['address_text'] as String? ?? '',
    neighborhoodName: json['neighborhood_name'] as String? ?? '',
    location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
    logoUrl: json['logo_url'] as String?,
    acceptingOrders: json['accepting_orders'] as bool,
  );

  final String id;
  final String name;
  final String description;
  final String addressText;
  final String neighborhoodName;
  final GeoPoint location;
  final String? logoUrl;

  /// La boutique accepte des commandes (sinon : « Commandes suspendues »).
  final bool acceptingOrders;
}
