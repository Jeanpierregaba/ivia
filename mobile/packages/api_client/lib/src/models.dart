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
    privacyConsentAt: switch (json['privacy_consent_at']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
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
