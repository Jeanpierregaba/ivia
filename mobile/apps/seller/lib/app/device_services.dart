import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

/// Choix d'une photo, prête à l'envoi : JPEG de 1024 px au plus, sans
/// métadonnées (position GPS comprise), docs/SECURITY.md.
abstract interface class PhotoPicker {
  /// `null` : choix annulé.
  Future<Uint8List?> pick();
}

class DevicePhotoPicker implements PhotoPicker {
  const DevicePhotoPicker();

  @override
  Future<Uint8List?> pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    return FlutterImageCompress.compressWithList(
      await file.readAsBytes(),
      minWidth: 1024,
      minHeight: 1024,
      quality: 85,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
  }
}

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
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
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
    } on TimeoutException {
      return const LocationResult.failed(LocationFailure.unavailable);
    } on LocationServiceDisabledException {
      return const LocationResult.failed(LocationFailure.serviceDisabled);
    }
  }
}

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => const DevicePhotoPicker(),
);

final locationServiceProvider = Provider<LocationService>(
  (ref) => const DeviceLocationService(),
);

/// Carte Google Maps activée au build (`--dart-define=GOOGLE_MAPS=true`)
/// quand les clés sont configurées ; sinon, aperçu sans fond de carte.
final mapsEnabledProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment('GOOGLE_MAPS'),
);
