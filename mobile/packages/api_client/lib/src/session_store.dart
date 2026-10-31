import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

/// Session gardée sur le téléphone.
class StoredSession {
  const StoredSession({required this.token, required this.user});

  final String token;

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

  final FlutterSecureStorage _storage;

  /// Stockage illisible (clé du Keystore perdue…) : aucune session.
  Future<StoredSession?> read() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null) return null;
      return StoredSession(
        token: token,
        user: _decodeUser(await _storage.read(key: _userKey)),
      );
    } on PlatformException {
      return null;
    }
  }

  Future<void> save(String token, User user) async {
    await _storage.write(key: _tokenKey, value: token);
    await saveUser(user);
  }

  Future<void> saveUser(User user) =>
      _storage.write(key: _userKey, value: jsonEncode(user.toJson()));

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
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
