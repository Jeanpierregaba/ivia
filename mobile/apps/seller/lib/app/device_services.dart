import 'dart:async';

import 'package:flutter/foundation.dart';
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

class DeviceLocationService implements LocationService {
  const DeviceLocationService();

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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
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

final locationServiceProvider = Provider<LocationService>(
  (ref) => const DeviceLocationService(),
);

/// Carte Google Maps activée au build (`--dart-define=GOOGLE_MAPS=true`)
/// quand les clés sont configurées ; sinon, aperçu sans fond de carte.
const mapsEnabled = bool.fromEnvironment('GOOGLE_MAPS');

/// Sans carte, la position ne vient que de « Ma position » : un marchand qui
/// refuse la localisation serait bloqué. La carte est donc exigée en release.
void requireMapsInRelease() {
  if (kReleaseMode && !mapsEnabled) {
    throw StateError(
      'Carte absente : construire avec --dart-define=GOOGLE_MAPS=true et les '
      'clés Google Maps (AGENTS.md).',
    );
  }
}

final mapsEnabledProvider = Provider<bool>((ref) => mapsEnabled);
