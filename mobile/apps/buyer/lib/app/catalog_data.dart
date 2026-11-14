import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

/// Quartiers actifs (noms des quartiers des résultats, choix de la zone).
final neighborhoodsProvider = FutureProvider<List<Choice>>(
  (ref) => ref.read(apiClientProvider).neighborhoods(),
  retry: (_, _) => null,
);

/// Catégories de produits actives.
final categoriesProvider = FutureProvider<List<ProductCategory>>(
  (ref) => ref.read(apiClientProvider).productCategories(),
  retry: (_, _) => null,
);

/// Nom d'un quartier ; `null` : inconnu ou liste pas encore chargée.
String? neighborhoodName(WidgetRef ref, String? id) {
  if (id == null) return null;
  final all = ref.watch(neighborhoodsProvider).value ?? const [];
  return all.where((n) => n.id == id).firstOrNull?.name;
}

/// Nom d'une catégorie : « Parent › Enfant » pour une sous-catégorie.
String? categoryName(List<ProductCategory> all, String? id) {
  final c = all.where((c) => c.id == id).firstOrNull;
  if (c == null) return null;
  final parent = all.where((p) => p.id == c.parentId).firstOrNull;
  return parent == null ? c.name : '${parent.name} › ${c.name}';
}

/// Véhicule de livraison selon la taille du colis.
String parcelLabel(ParcelSize size) => switch (size) {
  ParcelSize.small => 'Colis petit · moto',
  ParcelSize.medium => 'Colis moyen · moto',
  ParcelSize.large => 'Colis grand · voiture',
};
