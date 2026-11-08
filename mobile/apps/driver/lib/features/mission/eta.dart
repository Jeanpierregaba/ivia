import 'package:ivia_api_client/ivia_api_client.dart';

/// Temps de trajet estimé (spec 033) : le serveur ne donne pas de durée.
/// Distance à vol d'oiseau × [roadFactor], vitesse moyenne en ville selon le
/// véhicule.

/// Détours des rues par rapport à la ligne droite.
const roadFactor = 1.3;

/// Vitesse moyenne en ville (km/h).
double citySpeedKmh(VehicleType vehicle) => switch (vehicle) {
  VehicleType.bicycle => 12,
  VehicleType.motorbike => 22,
  VehicleType.car => 18,
};

/// Durée pour parcourir [meters] (à vol d'oiseau) avec [vehicle].
Duration travelTime(int meters, VehicleType vehicle) {
  final metersPerSecond = citySpeedKmh(vehicle) / 3.6;
  return Duration(seconds: (meters * roadFactor / metersPerSecond).round());
}

/// Heure d'arrivée estimée depuis [now].
DateTime arrivalAt(DateTime now, int meters, VehicleType vehicle) =>
    now.add(travelTime(meters, vehicle));
