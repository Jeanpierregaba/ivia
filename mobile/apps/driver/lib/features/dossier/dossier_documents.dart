import 'package:ivia_api_client/ivia_api_client.dart';

// La ligne de document elle-même (DocumentRow) est commune aux apps :
// paquet ivia_app_core.

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
  DriverDocumentKind.photo => 'Photo',
  DriverDocumentKind.other => 'Autre document',
};
