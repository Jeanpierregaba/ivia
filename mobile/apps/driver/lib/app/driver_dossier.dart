import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

/// Utilisateur connecté (identifiant) ; `null` : personne.
String? _userId(AuthState auth) => switch (auth) {
  AuthSignedIn(:final user) || AuthNeedsProfile(:final user) => user.id,
  _ => null,
};

/// Dossier livreur de l'utilisateur connecté ; `null` : aucun dossier.
/// Relu à chaque connexion, pas quand le profil change (envoi du dossier).
final driverDossierProvider =
    AsyncNotifierProvider<DriverDossierNotifier, DriverDossier?>(
      DriverDossierNotifier.new,
      // Pas de nouvel essai automatique : l'écran hors ligne propose
      // « Réessayer ».
      retry: (_, _) => null,
    );

class DriverDossierNotifier extends AsyncNotifier<DriverDossier?> {
  @override
  Future<DriverDossier?> build() async {
    if (ref.watch(authControllerProvider.select(_userId)) == null) return null;
    return ref.read(apiClientProvider).driverMe();
  }

  /// Dossier tout juste envoyé.
  void submitted(DriverDossier dossier) => state = AsyncData(dossier);

  /// Relit le statut sans repasser par le splash ; `false` : échec.
  Future<bool> refresh() async {
    try {
      final dossier = await ref.read(apiClientProvider).driverMe();
      if (ref.mounted) state = AsyncData(dossier);
      return true;
    } on Exception {
      // Réseau, ou réponse inattendue.
      return false;
    }
  }
}

/// Nom de la zone de travail du livreur (« Tokoin ») ; `null` : aucune ou
/// inconnue du serveur.
final workZoneNameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final id = ref.watch(driverDossierProvider).value?.delivery?.workZoneId;
  if (id == null || id.isEmpty) return null;
  final options = await ref.read(apiClientProvider).driverOptions();
  return options.zones.where((z) => z.id == id).firstOrNull?.name;
});
