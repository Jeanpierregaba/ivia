import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import 'catalog_labels.dart';

/// Nombre maximal de photos d'un produit (la première est la principale).
const maxPhotos = 5;


/// Photo du formulaire : choisie sur le téléphone, ou déjà sur le serveur.
class EditorPhoto {
  EditorPhoto.local(Uint8List this.bytes) : url = null;

  EditorPhoto.remote(ProductImage image)
    : bytes = null,
      url = image.url,
      key = image.objectKey;

  final Uint8List? bytes;
  final String? url;

  /// Clé de la photo envoyée : un nouvel essai ne la renvoie pas.
  String? key;
}

/// Champs d'un produit, communs à la création (étapes) et à la
/// modification. Les envois successifs portent sur le même produit.
class ProductForm {
  ProductForm();

  ProductForm.fromProduct(Product p)
    : productId = p.id,
      saved = p,
      photos = [for (final image in p.images) EditorPhoto.remote(image)],
      categoryId = p.categoryId,
      parcelSize = p.parcelSize,
      tracked = p.stockMode == StockMode.tracked,
      quantity = p.stockQuantity ?? 0,
      savedStockMode = p.stockMode,
      savedQuantity = p.stockQuantity {
    name.text = p.name;
    price.text = groupDigits(p.priceXof);
    description.text = p.description;
  }

  final name = TextEditingController();
  final price = TextEditingController();
  final description = TextEditingController();
  List<EditorPhoto> photos = [];
  String? categoryId;
  ParcelSize? parcelSize;
  bool tracked = true;
  int quantity = 1;

  /// Produit déjà enregistré (brouillon, ou produit modifié) ; `null` : pas
  /// encore créé.
  String? productId;

  /// Dernière version enregistrée sur le serveur (y compris après un
  /// enregistrement interrompu entre deux requêtes).
  Product? saved;

  /// Mode de stock enregistré : il ne change plus.
  StockMode? savedStockMode;
  int? savedQuantity;

  bool get stockModeLocked => savedStockMode != null;

  void dispose() {
    name.dispose();
    price.dispose();
    description.dispose();
  }

  /// Étape 1 : vérifications locales, le serveur valide à nouveau.
  /// [categoryIds] : catégories actives chargées ; une catégorie absente
  /// (désactivée par l'admin) est à choisir à nouveau, avant l'envoi des
  /// photos.
  Map<String, String> validateDetails({Set<String>? categoryIds}) {
    final errors = <String, String>{};
    final n = name.text.trim();
    if (n.length < 2 || n.length > 150) {
      errors['name'] = 'Le nom compte de 2 à 150 caractères.';
    }
    final p = parseXof(price.text);
    if (p == null || p < 1 || p > 100000000) {
      errors['price_xof'] = 'Prix entre 1 et 100 000 000 FCFA.';
    }
    final category = categoryId;
    if (category == null ||
        (categoryIds != null && !categoryIds.contains(category))) {
      errors['category_id'] = 'Choisissez une catégorie.';
    }
    if (description.text.trim().length > 500) {
      errors['description'] = '500 caractères au plus.';
    }
    return errors;
  }

  /// Étape 2.
  Map<String, String> validateDelivery() => {
    if (parcelSize == null) 'parcel_size': 'Choisissez la taille du colis.',
  };

  /// Envoie les nouvelles photos puis crée ou modifie le produit ; ajuste le
  /// stock d'un produit suivi déjà enregistré.
  Future<Product> save(
    IviaApiClient client, {
    required String shopId,
    required bool active,
  }) async {
    for (final photo in photos) {
      final bytes = photo.bytes;
      if (photo.key != null || bytes == null) continue;
      final prepared = await client.prepareUpload(
        purpose: 'product_image',
        contentType: 'image/jpeg',
        sizeBytes: bytes.length,
      );
      await client.upload(prepared, bytes);
      photo.key = prepared.objectKey;
    }
    final creating = productId == null;
    final input = ProductInput(
      categoryId: categoryId!,
      name: name.text.trim(),
      description: description.text.trim(),
      priceXof: parseXof(price.text)!,
      parcelSize: parcelSize!,
      imageKeys: [for (final photo in photos) photo.key!],
      stockMode: creating
          ? (tracked ? StockMode.tracked : StockMode.untracked)
          : null,
      stockQuantity: creating && tracked ? quantity : null,
      isActive: active,
    );
    if (creating) {
      final product = saved = await client.createProduct(shopId, input);
      productId = product.id;
      savedStockMode = product.stockMode;
      savedQuantity = product.stockQuantity;
      return product;
    }
    var product = saved = await client.updateProduct(productId!, input);
    if (product.stockMode == StockMode.tracked && quantity != savedQuantity) {
      product = saved = await client.setStock(product.id, quantity);
      savedQuantity = quantity;
    }
    return product;
  }

  /// Vérifications de l'aperçu, dans l'ordre affiché.
  List<String> checks() => [
    photosLabel(photos.length),
    description.text.trim().isEmpty
        ? 'Prix et catégorie'
        : 'Prix, catégorie et description',
    tracked ? 'Stock suivi : $quantity' : 'Stock non suivi',
  ];
}

/// Champs affichés par les formulaires produit : une erreur du serveur sur
/// un autre champ s'affiche en message général.
const shownFields = {...detailFields, 'parcel_size', 'stock_quantity'};

/// Champs de l'étape 1 (une erreur sur l'un d'eux y ramène).
const detailFields = {
  'name',
  'price_xof',
  'category_id',
  'description',
  'image_keys',
};
