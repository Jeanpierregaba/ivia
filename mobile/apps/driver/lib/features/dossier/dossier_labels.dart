import 'package:ivia_api_client/ivia_api_client.dart';

/// Documents demandés au livreur, dans l'ordre d'affichage.
const requiredDocuments = [
  DriverDocumentKind.idCard,
  DriverDocumentKind.drivingLicense,
  DriverDocumentKind.vehicleRegistration,
];

String documentLabel(DriverDocumentKind kind) => switch (kind) {
  DriverDocumentKind.idCard => "Pièce d'identité",
  DriverDocumentKind.drivingLicense => 'Permis de conduire',
  DriverDocumentKind.vehicleRegistration => 'Carte grise',
  DriverDocumentKind.vehicleInsurance => "Assurance du véhicule",
  DriverDocumentKind.vehiclePhoto => 'Photo du véhicule',
  DriverDocumentKind.criminalRecord => 'Casier judiciaire',
  DriverDocumentKind.photo => 'Photo',
  DriverDocumentKind.other => 'Autre document',
};

String vehicleLabel(VehicleType type) => switch (type) {
  VehicleType.bicycle => 'Vélo',
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
