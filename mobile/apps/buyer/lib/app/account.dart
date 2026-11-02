import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

/// Compte connecté ; `null` hors session. Les états propres au compte
/// (filtres, panier) le lisent pour repartir de zéro quand il change
/// (déconnexion, autre compte sur le même téléphone).
final accountIdProvider = Provider<String?>(
  (ref) => ref.watch(
    authControllerProvider.select(
      (auth) => switch (auth) {
        AuthSignedIn(:final user) || AuthNeedsProfile(:final user) => user.id,
        _ => null,
      },
    ),
  ),
);
