import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pourquoi la position n'a pas pu être obtenue.
enum LocationFailure { serviceDisabled, denied, deniedForever, unavailable }

/// Position actuelle, ou la raison de son absence.
class LocationResult {
  const LocationResult.found(GeoPoint this.point) : failure = null;
  const LocationResult.failed(LocationFailure this.failure) : point = null;

  final GeoPoint? point;
  final LocationFailure? failure;
}

/// Autorisation de la position pour l'app.
enum LocationAccess {
  granted,

  /// Pas encore demandée, ou refusée mais encore demandable.
  askable,

  /// Le système ne demandera plus : seuls les réglages peuvent l'accorder.
  deniedForever,
}

/// Position du téléphone. La fenêtre du système n'est ouverte que par
/// [request], appelé par l'écran d'autorisation (`askForLocation`) : une
/// lecture ([current]) ne demande jamais rien.
abstract interface class LocationService {
  /// État de l'autorisation, sans rien demander.
  Future<LocationAccess> access();

  /// Fenêtre du système ; renvoie l'état obtenu.
  Future<LocationAccess> request();

  /// Position, seulement si elle est autorisée (sinon `denied` ou
  /// `deniedForever`).
  Future<LocationResult> current();

  /// Réglages de l'app (position refusée définitivement) ; `false` si
  /// l'ouverture a échoué.
  Future<bool> openSettings();
}

/// Position du téléphone par `geolocator`. [approximate] : précision d'un
/// quartier, suffisante pour « autour de moi » (acheteur) ; sinon précise
/// (épingle d'une boutique).
class DeviceLocationService implements LocationService {
  const DeviceLocationService({this.approximate = false});

  final bool approximate;

  @override
  Future<bool> openSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } on Exception {
      return false;
    }
  }

  static LocationAccess _of(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse => LocationAccess.granted,
        LocationPermission.deniedForever => LocationAccess.deniedForever,
        _ => LocationAccess.askable,
      };

  /// Android ne signale le refus définitif qu'en réponse à une demande
  /// (la vérification dit seulement « refusée ») : il est mémorisé ici,
  /// puis effacé dès que la position est autorisée.
  static const _deniedForeverKey = 'location_denied_forever';

  static Future<void> _remember({required bool deniedForever}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (deniedForever) {
        await prefs.setBool(_deniedForeverKey, true);
      } else if (prefs.containsKey(_deniedForeverKey)) {
        await prefs.remove(_deniedForeverKey);
      }
    } on Exception {
      // Préférences illisibles : la fenêtre du système sera redemandée.
    }
  }

  static Future<bool> _rememberedDeniedForever() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(
            _deniedForeverKey,
          ) ??
          false;
    } on Exception {
      return false;
    }
  }

  @override
  Future<LocationAccess> access() async {
    LocationAccess access;
    try {
      access = _of(await Geolocator.checkPermission());
    } on Exception {
      return LocationAccess.askable;
    }
    switch (access) {
      case LocationAccess.granted:
        await _remember(deniedForever: false);
      case LocationAccess.askable:
        if (await _rememberedDeniedForever()) {
          access = LocationAccess.deniedForever;
        }
      case LocationAccess.deniedForever:
        break;
    }
    return access;
  }

  @override
  Future<LocationAccess> request() async {
    LocationAccess access;
    try {
      access = _of(await Geolocator.requestPermission());
    } on Exception {
      // Demande déjà en cours, erreur de la plateforme : rien d'accordé.
      return LocationAccess.askable;
    }
    if (access != LocationAccess.askable) {
      await _remember(deniedForever: access == LocationAccess.deniedForever);
    }
    return access;
  }

  @override
  Future<LocationResult> current() async {
    // Localisation coupée d'abord : son message prime sur le refus (iOS dit
    // « refusée » quand elle est coupée).
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationResult.failed(LocationFailure.serviceDisabled);
    }
    switch (await access()) {
      case LocationAccess.askable:
        return const LocationResult.failed(LocationFailure.denied);
      case LocationAccess.deniedForever:
        return const LocationResult.failed(LocationFailure.deniedForever);
      case LocationAccess.granted:
        break;
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
