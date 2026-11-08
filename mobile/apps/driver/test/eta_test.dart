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
}
