import 'package:ivia_api_client/ivia_api_client.dart';

String vehicleLabel(VehicleType type) => switch (type) {
  VehicleType.motorbike => 'Moto',
  VehicleType.car => 'Voiture',
};

/// « Moto · 3 documents ».
String dossierLine(DriverDossier dossier) {
  final count = dossier.documents.length;
  return '${vehicleLabel(dossier.vehicleType)} · '
      '$count document${count > 1 ? 's' : ''}';
}
