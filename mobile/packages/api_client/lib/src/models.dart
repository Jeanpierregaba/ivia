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
