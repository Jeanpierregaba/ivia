/// Faux serveur et réponses types, pour les tests des apps et de ce paquet.
/// À n'importer que depuis `test/`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Requête reçue par le [FakeApiServer].
class RecordedRequest {
  const RecordedRequest(
    this.method,
    this.path,
    this.headers,
    this.body, {
    this.host = '',
  });

  final String method;
  final String path;

  /// Hôte appelé (l'API, ou le stockage pour une URL signée).
  final String host;

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
  'vehicle_type': 'motorbike',
  'vehicle_plate': 'TG 4521 AB',
  'vehicle_description': '',
  'last_location_at': null,
  'documents': [
    for (final (i, kind) in documents.indexed)
      {'id': 'doc-$i', 'kind': kind, 'created_at': '2026-10-31T10:00:00Z'},
  ],
  'created_at': '2026-10-31T10:00:00Z',
};
