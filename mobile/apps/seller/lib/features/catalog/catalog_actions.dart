import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';
import 'catalog_providers.dart';
import 'product_sheets.dart';

/// Message affiché pour une erreur d'API. Boutique suspendue entre-temps :
/// la boutique est relue et le routeur ouvre l'écran « suspendue ».
String catalogErrorMessage(ProviderContainer container, Object error) {
  if (error is ApiException) {
    if (error.code == 'shop_suspended' || error.code == 'shop_not_found') {
      container.read(sellerShopProvider.notifier).refresh();
    }
    return error.message;
  }
  return 'Une erreur est survenue. Réessayez.';
}

/// Message d'aucune photo : la publication en demande au moins une.
const noPhotoMessage = 'Ajoutez au moins une photo.';

/// Actions du catalogue : elles survivent à l'écran qui les lance (le
/// message « Annuler » reste après la fermeture de « Modifier »).
class CatalogActions {
  CatalogActions.of(BuildContext context)
    : _container = ProviderScope.containerOf(context, listen: false),
      _messenger = ScaffoldMessenger.of(context),
      _router = GoRouter.of(context);

  final ProviderContainer _container;
  final ScaffoldMessengerState _messenger;
  final GoRouter _router;

  IviaApiClient get _client => _container.read(apiClientProvider);

  void _say(String text, {SnackBarAction? action}) {
    _messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  SnackBarAction _editAction(Product p) => SnackBarAction(
    label: 'Modifier',
    onPressed: () => _router.push(Routes.productEdit(p.id)),
  );

  /// Erreur d'une action sur [product] : une catégorie refusée (désactivée
  /// par l'admin) propose « Modifier » pour en choisir une autre.
  void _sayError(Object error, Product product) {
    final field = error is ApiException ? error.fields['category_id'] : null;
    if (field != null) {
      _container.invalidate(productCategoriesProvider);
      _say('$field Choisissez-en une autre.', action: _editAction(product));
      return;
    }
    _say(catalogErrorMessage(_container, error));
  }

  /// Confirme puis retire de la vente ; ouvre l'onglet « Retirés » avec un
  /// message « Annuler ». `true` : retiré.
  Future<bool> withdraw(BuildContext context, Product product) async {
    if (!await showWithdrawSheet(context, product)) return false;
    final Product withdrawn;
    try {
      withdrawn = await _client.updateProduct(
        product.id,
        inputFrom(product, isActive: false),
      );
    } on Exception catch (e) {
      _sayError(e, product);
      return false;
    }
    announceWithdrawn(withdrawn);
    return true;
  }

  /// Après un retrait : onglet « Retirés », message « Annuler ».
  void announceWithdrawn(Product product) {
    refreshCatalog(_container);
    _container
        .read(catalogTabProvider.notifier)
        .select(ProductStatus.withdrawn);
    _router.go(Routes.catalog);
    _say(
      '${product.name} retiré de la vente',
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () => restore(product, undo: true),
      ),
    );
  }

  /// Remet en vente (« Remettre », ou « Annuler » d'un retrait).
  Future<void> restore(Product product, {bool undo = false}) async {
    if (product.images.isEmpty) {
      _say(noPhotoMessage, action: _editAction(product));
      return;
    }
    try {
      await _client.updateProduct(
        product.id,
        inputFrom(product, isActive: true),
      );
    } on Exception catch (e) {
      _sayError(e, product);
      return;
    }
    refreshCatalog(_container);
    if (undo) {
      _container.read(catalogTabProvider.notifier).select(ProductStatus.active);
    }
    _say('${product.name} remis en vente');
  }

  /// Ajuste la quantité d'un produit à stock suivi.
  Future<void> adjustStock(BuildContext context, Product product) async {
    final quantity = await showStockSheet(
      context,
      initial: product.stockQuantity ?? 0,
    );
    if (quantity == null || quantity == product.stockQuantity) return;
    try {
      await _client.setStock(product.id, quantity);
    } on Exception catch (e) {
      _say(catalogErrorMessage(_container, e));
      return;
    }
    refreshCatalog(_container);
    _say('Stock mis à jour : $quantity');
  }
}
