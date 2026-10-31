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
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: config.baseUrl.toString(),
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 15),
           sendTimeout: const Duration(seconds: 15),
           contentType: Headers.jsonContentType,
           responseType: ResponseType.json,
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = this.token;
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;

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

  /// Révoque la session courante côté serveur.
  Future<void> logout() => _send('POST', '/v1/auth/logout');

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? data,
  }) async {
    final authenticated = token != null;
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        options: Options(method: method),
      );
      final body = response.data;
      return body is Map<String, dynamic> ? body : const {};
    } on DioException catch (e) {
      final error = _toApiException(e);
      if (authenticated && error.statusCode == 401) onUnauthorized?.call();
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
