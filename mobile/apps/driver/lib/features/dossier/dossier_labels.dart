import 'package:ivia_api_client/ivia_api_client.dart';

String vehicleLabel(VehicleType type) => switch (type) {
  VehicleType.motorbike => 'Moto',
  VehicleType.car => 'Voiture',
};

/// Types de documents reçus, sans doublon : le serveur ajoute une pièce
/// refaite sans retirer l'ancienne.
List<DriverDocumentKind> receivedKinds(DriverDossier dossier) =>
    dossier.documents.toSet().toList();

/// « Moto · 3 documents ».
String dossierLine(DriverDossier dossier) {
  final count = receivedKinds(dossier).length;
  return '${vehicleLabel(dossier.vehicleType)} · '
      '$count document${count > 1 ? 's' : ''}';
}
