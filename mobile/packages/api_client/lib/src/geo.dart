part of 'client.dart';

// Carte : recherche de lieux, adresse d'une position, itinéraire, lieux personnels, temps réel.
// Tout passe par le serveur : les apps n'appellent aucun fournisseur (ADR 0013).

class GeoSuggestion {
  GeoSuggestion.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String? ?? '',
      address = j['address'] as String? ?? '',
      source = j['source'] as String? ?? '',
      point = j['lat'] == null
          ? null
          : GeoPoint(
              lat: (j['lat'] as num).toDouble(),
              lng: (j['lng'] as num).toDouble(),
            );
  final String id, name, address, source;

  /// Connu d'avance pour les lieux Ivia et personnels ; un lieu Google se résout.
  final GeoPoint? point;
}

class GeoPlace {
  GeoPlace.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String? ?? '',
      address = j['address'] as String? ?? '',
      point = GeoPoint(
        lat: ((j['location'] as Map)['lat'] as num).toDouble(),
        lng: ((j['location'] as Map)['lng'] as num).toDouble(),
      );
  final String id, name, address;
  final GeoPoint point;
}

class GeoRoute {
  GeoRoute.fromJson(Map<String, dynamic> j)
    : distanceM = _i(j['distance_m']),
      durationS = _i(j['duration_s']),
      polyline = j['polyline'] as String? ?? '',
      approximate = j['approximate'] as bool? ?? false;
  final int distanceM, durationS;

  /// polyline6 ; vide si l'itinéraire est estimé à vol d'oiseau.
  final String polyline;
  final bool approximate;
}

class RideEstimate {
  RideEstimate.fromJson(Map<String, dynamic> j)
    : priceXof = _i(j['price_xof']),
      driversNear = _i(j['drivers_near']),
      pickupEtaS = _i(j['pickup_eta_s']);
  final int priceXof, driversNear, pickupEtaS;
}

class UserPlace {
  UserPlace.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      label = j['label'] as String? ?? '',
      type = j['type'] as String? ?? '',
      address = j['address'] as String? ?? '',
      point = GeoPoint(
        lat: ((j['location'] as Map)['lat'] as num).toDouble(),
        lng: ((j['location'] as Map)['lng'] as num).toDouble(),
      );
  final String id, label, type, address;
  final GeoPoint point;
}

extension GeoApi on IviaApiClient {
  Future<List<GeoSuggestion>> geoAutocomplete(
    String q, {
    GeoPoint? near,
    required String session,
  }) async {
    final j = await _send(
      'GET',
      '/v1/geo/places/autocomplete',
      query: {
        'q': q,
        'session': session,
        if (near != null) 'lat': '${near.lat}',
        if (near != null) 'lng': '${near.lng}',
      },
    );
    return [for (final i in _list(j['items'])) GeoSuggestion.fromJson(i)];
  }

  Future<GeoPlace> geoPlace(String id, {required String session}) async =>
      GeoPlace.fromJson(
        await _send(
          'GET',
          '/v1/geo/places/${Uri.encodeComponent(id)}',
          query: {'session': session},
        ),
      );

  Future<String> geoReverse(GeoPoint p) async {
    final j = await _send(
      'GET',
      '/v1/geo/reverse',
      query: {'lat': '${p.lat}', 'lng': '${p.lng}'},
    );
    return j['label'] as String? ?? '';
  }

  Future<GeoRoute> geoRoute(
    GeoPoint origin,
    GeoPoint destination, {
    String profile = 'moto',
  }) async => GeoRoute.fromJson(
    await _send(
      'POST',
      '/v1/geo/route',
      data: {
        'origin': {'lat': origin.lat, 'lng': origin.lng},
        'destination': {'lat': destination.lat, 'lng': destination.lng},
        'profile': profile,
      },
    ),
  );

  /// Prix du trajet ; refusé (422) si le départ n'a pas de tarif.
  Future<RideEstimate> rideEstimate(
    GeoPoint origin,
    GeoPoint destination, {
    required String vehicle,
  }) async => RideEstimate.fromJson(
    await _send(
      'POST',
      '/v1/rides/estimate',
      data: {
        'origin': {'lat': origin.lat, 'lng': origin.lng},
        'destination': {'lat': destination.lat, 'lng': destination.lng},
        'vehicle': vehicle,
      },
    ),
  );

  Future<List<UserPlace>> geoMyPlaces() async {
    final j = await _send('GET', '/v1/geo/my-places');
    return [for (final i in _list(j['items'])) UserPlace.fromJson(i)];
  }

  Future<void> geoAddMyPlace({
    required String label,
    required String type,
    required GeoPoint point,
    String address = '',
  }) => _send(
    'POST',
    '/v1/geo/my-places',
    data: {
      'label': label,
      'type': type,
      'address': address,
      'location': {'lat': point.lat, 'lng': point.lng},
    },
  );

  /// Connexion temps réel ; `null` dans un navigateur, qui ne peut pas envoyer le jeton en en-tête
  /// (il ne doit jamais passer dans l'URL).
  WebSocketChannel? openSocket(String path) {
    final t = token;
    if (t == null) return null;
    final base = Uri.parse(_dio.options.baseUrl);
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: path,
    );
    return connectWebSocket(uri, t);
  }
}
