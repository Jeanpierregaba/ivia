import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

String parcelLabel(ParcelSize size) => switch (size) {
  ParcelSize.small => 'Petit',
  ParcelSize.medium => 'Moyen',
  ParcelSize.large => 'Grand',
};

String statusLabel(ProductStatus status) => switch (status) {
  ProductStatus.active => 'En vente',
  ProductStatus.draft => 'Brouillons',
  ProductStatus.withdrawn => 'Retirés',
};

/// Nom affiché d'une catégorie : « Parent › Enfant » pour une
/// sous-catégorie.
String categoryLabel(ProductCategory c, List<ProductCategory> all) {
  final parent = all.where((p) => p.id == c.parentId).firstOrNull;
  return parent == null ? c.name : '${parent.name} › ${c.name}';
}

/// Stock tel qu'affiché : « Stock 12 », « Stock non suivi ».
String stockLabel(Product p) => p.stockMode == StockMode.tracked
    ? 'Stock ${p.stockQuantity ?? 0}'
    : 'Stock non suivi';

/// Ligne sous le nom d'un produit dans le catalogue.
String productSubtitle(Product p, {String? category, DateTime? now}) {
  switch (p.status) {
    case ProductStatus.withdrawn:
      final at = p.withdrawnAt;
      return at == null ? 'Retiré' : 'Retiré ${onDate(at, now: now)}';
    case ProductStatus.active || ProductStatus.draft:
      if (p.soldOut && p.status == ProductStatus.active) {
        return 'Épuisé · à réapprovisionner';
      }
      if (p.stockMode == StockMode.untracked) return 'Stock non suivi';
      return [?category, stockLabel(p)].join(' · ');
  }
}

/// Nombre de photos : « 1 photo », « 3 photos ».
String photosLabel(int n) => n == 1 ? '1 photo' : '$n photos';
