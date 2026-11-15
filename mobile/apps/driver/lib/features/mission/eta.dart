import 'dart:math' as math;

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

/// Distance à vol d'oiseau entre deux points (haversine), en mètres.
int straightMeters(GeoPoint a, GeoPoint b) {
  const earth = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return (2 * earth * math.asin(math.sqrt(h))).round();
}

/// Trajet restant : distance par la route et durée.
typedef Leg = ({int meters, Duration duration});

/// Profil d'itinéraire du serveur (`car` ou `moto`).
String routeProfile(VehicleType vehicle) =>
    vehicle == VehicleType.car ? 'car' : 'moto';

/// Trajet restant depuis l'itinéraire du serveur ; repli sur le calcul à vol
/// d'oiseau si l'itinéraire manque ou n'est qu'estimé. Le serveur n'a pas de
/// profil vélo : sa durée moto est ralentie à la vitesse du vélo.
Leg estimateLeg({
  required int straight,
  required VehicleType vehicle,
  GeoRoute? route,
}) {
  if (route == null || route.approximate) {
    return (
      meters: (straight * roadFactor).round(),
      duration: travelTime(straight, vehicle),
    );
  }
  var seconds = route.durationS.toDouble();
  if (vehicle == VehicleType.bicycle) {
    seconds *=
        citySpeedKmh(VehicleType.motorbike) / citySpeedKmh(VehicleType.bicycle);
  }
  return (
    meters: route.distanceM,
    duration: Duration(seconds: seconds.round()),
  );
}
