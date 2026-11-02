import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

/// Compte connecté vu par l'app marchand : identifiant et rôle seller.
/// `null` : personne n'est connecté.
(String, bool)? _account(AuthState auth) => switch (auth) {
  AuthSignedIn(:final user) ||
  AuthNeedsProfile(:final user) => (user.id, user.roles.contains('seller')),
  _ => null,
};

/// Boutique du marchand connecté ; `null` : aucune boutique.
///
/// Relue à chaque connexion. Le rôle seller n'existe qu'après la création de
/// la première boutique : sans lui, aucune boutique, sans appel au serveur.
final sellerShopProvider = AsyncNotifierProvider<SellerShop, Shop?>(
  SellerShop.new,
  // Pas de nouvel essai automatique : l'écran hors ligne propose
  // « Réessayer ».
  retry: (_, _) => null,
);

class SellerShop extends AsyncNotifier<Shop?> {
  @override
  Future<Shop?> build() async {
    final account = ref.watch(authControllerProvider.select(_account));
    if (account == null || !account.$2) return null;
    return _fetch();
  }

  Future<Shop?> _fetch() async {
    final shops = await ref.read(apiClientProvider).myShops();
    return shops.isEmpty ? null : shops.first;
  }

  /// Boutique tout juste créée.
  void created(Shop shop) => state = AsyncData(shop);

  /// Pièces du marchand rendues par le serveur après un dépôt.
  void documentsSent(List<MerchantDocumentKind> documents) {
    if (state.value case final shop?) {
      state = AsyncData(shop.withDocuments(documents));
    }
  }

  /// Relit le statut (validation par l'admin) sans repasser par le splash.
  /// Échec (réseau) : l'écran en cours reste affiché ; renvoie `false`.
  Future<bool> refresh() async {
    try {
      final shop = await _fetch();
      if (ref.mounted) state = AsyncData(shop);
      return true;
    } on Exception {
      // Réseau, ou réponse inattendue.
      return false;
    }
  }
}

/// Catégories de boutique et quartiers du formulaire.
final shopChoicesProvider =
    FutureProvider.autoDispose<(List<Choice>, List<Choice>)>((ref) async {
      final client = ref.watch(apiClientProvider);
      // Chargés en parallèle.
      final categories = client.shopCategories();
      final neighborhoods = client.neighborhoods();
      return (await categories, await neighborhoods);
    });
