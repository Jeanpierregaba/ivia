import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Plateforme de `geolocator` simulée.
class _Platform extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  LocationPermission permission = LocationPermission.denied;
  LocationPermission afterRequest = LocationPermission.whileInUse;
  Exception? requestError;
  var serviceEnabled = true;
  var requests = 0;
  var reads = 0;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    if (requestError case final e?) throw e;
    return permission = afterRequest;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    reads++;
    return Position(
      latitude: 6.1375,
      longitude: 1.2123,
      timestamp: DateTime.utc(2026, 11, 6),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

void main() {
  late _Platform platform;
  const service = DeviceLocationService();

  setUp(() {
    platform = _Platform();
    GeolocatorPlatform.instance = platform;
  });

  group('access', () {
    for (final (permission, access) in [
      (LocationPermission.denied, LocationAccess.askable),
      (LocationPermission.unableToDetermine, LocationAccess.askable),
      (LocationPermission.deniedForever, LocationAccess.deniedForever),
      (LocationPermission.whileInUse, LocationAccess.granted),
      (LocationPermission.always, LocationAccess.granted),
    ]) {
      test('$permission ⇒ $access, sans rien demander', () async {
        platform.permission = permission;
        expect(await service.access(), access);
        expect(platform.requests, 0);
      });
    }
  });

  group('request', () {
    test('fenêtre du système : état obtenu', () async {
      expect(await service.request(), LocationAccess.granted);
      platform
        ..permission = LocationPermission.denied
        ..afterRequest = LocationPermission.deniedForever;
      expect(await service.request(), LocationAccess.deniedForever);
      expect(platform.requests, 2);
    });

    test('erreur de la plateforme : rien d\'accordé', () async {
      platform.requestError = const PermissionRequestInProgressException(
        'déjà en cours',
      );
      expect(await service.request(), LocationAccess.askable);
    });
  });

  group('current', () {
    test('non autorisée : refus, sans fenêtre du système', () async {
      expect((await service.current()).failure, LocationFailure.denied);
      platform.permission = LocationPermission.deniedForever;
      expect((await service.current()).failure, LocationFailure.deniedForever);
      expect(platform.requests, 0);
      expect(platform.reads, 0);
    });

    test('autorisée : position lue', () async {
      platform.permission = LocationPermission.whileInUse;
      final result = await service.current();
      expect(result.point?.lat, 6.1375);
      expect(result.point?.lng, 1.2123);
    });

    test('autorisée mais localisation coupée : service désactivé', () async {
      platform
        ..permission = LocationPermission.whileInUse
        ..serviceEnabled = false;
      expect(
        (await service.current()).failure,
        LocationFailure.serviceDisabled,
      );
      expect(platform.reads, 0);
    });
  });
}
