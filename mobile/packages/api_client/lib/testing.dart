/// Faux serveur et réponses types, pour les tests des apps et de ce paquet.
/// À n'importer que depuis `test/`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Requête reçue par le [FakeApiServer].
class RecordedRequest {
  const RecordedRequest(this.method, this.path, this.headers, this.body);

  final String method;
  final String path;

  /// En-têtes, noms en minuscules.
  final Map<String, String> headers;
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

  void on(String method, String path, FakeHandler handler) =>
      _handlers['$method $path'] = handler;

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
      if (bytes.isNotEmpty) body = jsonDecode(utf8.decode(bytes));
    }
    final request = RecordedRequest(
      options.method,
      options.uri.path,
      options.headers.map((k, v) => MapEntry(k.toLowerCase(), '$v')),
      body,
    );
    requests.add(request);

    final handler = _handlers['${request.method} ${request.path}'];
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
