import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_driver/features/mission/eta.dart';

// Spec 033 : temps de trajet estimé, distance × 1,3, vitesse selon le
// véhicule.

void main() {
  test('moto : 22 km/h', () {
    // 4 200 m × 1,3 = 5 460 m à 22 km/h : 893 s.
    expect(
      travelTime(4200, VehicleType.motorbike),
      const Duration(seconds: 893),
    );
  });

  test('vélo plus lent que la voiture, voiture plus lente que la moto', () {
    final bike = travelTime(3000, VehicleType.bicycle);
    final car = travelTime(3000, VehicleType.car);
    final moto = travelTime(3000, VehicleType.motorbike);
    expect(bike > car, isTrue);
    expect(car > moto, isTrue);
  });

  test('heure d\'arrivée', () {
    final now = DateTime.utc(2026, 11, 8, 23, 24);
    // 2 000 m × 1,3 à 12 km/h : 780 s, soit 13 min.
    expect(
      arrivalAt(now, 2000, VehicleType.bicycle),
      DateTime.utc(2026, 11, 8, 23, 37),
    );
  });

  test('distance nulle : déjà arrivé', () {
    expect(travelTime(0, VehicleType.car), Duration.zero);
  });

  GeoRoute route(int m, int s, {bool approximate = false}) =>
      GeoRoute.fromJson({
        'distance_m': m,
        'duration_s': s,
        'polyline': '',
        'approximate': approximate,
      });

  test('distance à vol d\'oiseau', () {
    const a = GeoPoint(lat: 6.1319, lng: 1.2228);
    // Un centième de degré de latitude : environ 1 112 m.
    final d = straightMeters(a, const GeoPoint(lat: 6.1419, lng: 1.2228));
    expect(d, inInclusiveRange(1100, 1125));
    expect(straightMeters(a, a), 0);
  });

  test('itinéraire du serveur : sa distance et sa durée', () {
    final leg = estimateLeg(
      straight: 2000,
      vehicle: VehicleType.motorbike,
      route: route(3400, 720),
    );
    expect(leg.meters, 3400);
    expect(leg.duration, const Duration(minutes: 12));
  });

  test('vélo : durée moto ralentie', () {
    final leg = estimateLeg(
      straight: 2000,
      vehicle: VehicleType.bicycle,
      route: route(3400, 720),
    );
    // 720 s × 22 / 12.
    expect(leg.duration, const Duration(seconds: 1320));
  });

  test('sans itinéraire ou estimé : repli à vol d\'oiseau', () {
    for (final r in [null, route(9999, 9999, approximate: true)]) {
      final leg = estimateLeg(
        straight: 2000,
        vehicle: VehicleType.car,
        route: r,
      );
      expect(leg.meters, 2600);
      expect(leg.duration, travelTime(2000, VehicleType.car));
    }
  });

  test('profil d\'itinéraire', () {
    expect(routeProfile(VehicleType.car), 'car');
    expect(routeProfile(VehicleType.bicycle), 'moto');
  });
}
