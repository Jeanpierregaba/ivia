/// Client de l'API ivia : le seul point d'accès au backend pour les 3 apps.
///
/// Contrat : backend/api/openapi.yaml. Les appels HTTP arrivent avec la
/// fonctionnalité 001 (connexion par OTP).
library;

export 'src/api_config.dart';
