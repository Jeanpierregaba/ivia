import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

/// Pourquoi la position n'a pas pu être obtenue.
enum LocationFailure { serviceDisabled, denied, deniedForever, unavailable }

/// Position actuelle, ou la raison de son absence.
class LocationResult {
  const LocationResult.found(GeoPoint this.point) : failure = null;
  const LocationResult.failed(LocationFailure this.failure) : point = null;

  final GeoPoint? point;
  final LocationFailure? failure;
}

/// Position du téléphone, demandée seulement quand l'utilisateur la veut.
abstract interface class LocationService {
  Future<LocationResult> current();
}

/// Position du téléphone par `geolocator`. [approximate] : précision d'un
/// quartier, suffisante pour « autour de moi » (acheteur) ; sinon précise
/// (épingle d'une boutique).
class DeviceLocationService implements LocationService {
  const DeviceLocationService({this.approximate = false});

  final bool approximate;

  @override
  Future<LocationResult> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationResult.failed(LocationFailure.serviceDisabled);
    }
    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } on Exception {
      return const LocationResult.failed(LocationFailure.unavailable);
    }
    if (permission == LocationPermission.denied) {
      return const LocationResult.failed(LocationFailure.denied);
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationResult.failed(LocationFailure.deniedForever);
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: approximate
              ? LocationAccuracy.medium
              : LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationResult.found(
        GeoPoint(lat: position.latitude, lng: position.longitude),
      );
    } on LocationServiceDisabledException {
      return const LocationResult.failed(LocationFailure.serviceDisabled);
    } on Exception {
      // Délai dépassé, demande déjà en cours, erreur de la plateforme.
      return const LocationResult.failed(LocationFailure.unavailable);
    }
  }
}

/// Service de position de l'app ; précis par défaut, chaque app peut le
/// remplacer (l'acheteur le veut approximatif).
final locationServiceProvider = Provider<LocationService>(
  (ref) => const DeviceLocationService(),
);

/// Distance à vol d'oiseau en mètres (formule de haversine), précise à
/// quelques mètres près à l'échelle de Lomé.
int distanceMeters(GeoPoint a, GeoPoint b) {
  const earthRadius = 6371000.0;
  double rad(double degrees) => degrees * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return (2 * earthRadius * math.asin(math.sqrt(h))).round();
}
