import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

/// Session gardée sur le téléphone.
class StoredSession {
  const StoredSession({
    required this.token,
    required this.user,
    this.refreshToken,
  });

  final String token;

  /// Jeton de rafraîchissement (connexion par numéro) ; `null` sinon.
  final String? refreshToken;

  /// Dernier profil reçu ; `null` s'il est absent ou illisible.
  final User? user;
}

/// Jeton et dernier profil dans le stockage sécurisé du téléphone
/// (Keystore Android, Keychain iOS) : jamais en clair (docs/SECURITY.md).
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'session_token';
  static const _userKey = 'session_user';
  static const _refreshKey = 'session_refresh';

  /// Identifiant d'installation : gardé à la déconnexion (le serveur
  /// reconnaît l'appareil), perdu à la désinstallation.
  static const _deviceKey = 'device_id';

  final FlutterSecureStorage _storage;

  /// Stockage illisible (clé du Keystore perdue…) : aucune session.
  Future<StoredSession?> read() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null) return null;
      return StoredSession(
        token: token,
        refreshToken: await _storage.read(key: _refreshKey),
        user: _decodeUser(await _storage.read(key: _userKey)),
      );
    } on PlatformException {
      return null;
    }
  }

  // Écritures au mieux : si le stockage échoue (Keystore indisponible…), la
  // session reste valable pour cette exécution de l'app, sans être gardée.

  Future<void> save(String token, User user, {String? refreshToken}) async {
    if (!await saveTokens(token, refreshToken)) return;
    await saveUser(user);
  }

  /// Jetons renouvelés ; `false` si le stockage a échoué.
  Future<bool> saveTokens(String token, String? refreshToken) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
      if (refreshToken == null) {
        await _storage.delete(key: _refreshKey);
      } else {
        await _storage.write(key: _refreshKey, value: refreshToken);
      }
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// Identifiant d'installation, tiré au hasard au premier appel (jamais un
  /// identifiant matériel). Stockage indisponible : un identifiant pour
  /// cette exécution seulement.
  Future<String> deviceId() async {
    try {
      final existing = await _storage.read(key: _deviceKey);
      if (existing != null && existing.length >= 16) return existing;
      final id = _randomId();
      await _storage.write(key: _deviceKey, value: id);
      return id;
    } on PlatformException {
      return _memoryDeviceId ??= _randomId();
    }
  }

  static String? _memoryDeviceId;

  static String _randomId() {
    final rnd = Random.secure();
    return base64UrlEncode([for (var i = 0; i < 24; i++) rnd.nextInt(256)])
        .replaceAll('=', '');
  }

  Future<void> saveUser(User user) async {
    try {
      await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    } on PlatformException {
      // Profil non gardé : il sera relu sur le serveur au prochain démarrage.
    }
  }

  Future<void> clear() async {
    try {
      await Future.wait([
        _storage.delete(key: _tokenKey),
        _storage.delete(key: _refreshKey),
        _storage.delete(key: _userKey),
      ]);
    } on PlatformException {
      // Rien de plus à faire : le serveur a déjà révoqué ou refusé la session.
    }
  }

  static User? _decodeUser(String? raw) {
    if (raw == null) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
