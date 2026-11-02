import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/cart.dart';
import '../../app/router.dart';

/// Message d'un refus du panier, pour l'acheteur.
String cartErrorMessage(Object error) => switch (error) {
  ApiException(code: 'product_not_found') =>
    'Ce produit n’est plus disponible.',
  ApiException(code: 'validation_failed', :final fields)
      when fields.containsKey('quantity') =>
    fields['quantity']!,
  ApiException(:final message) => message,
  _ => const ApiException.unknown().message,
};

void showCartMessage(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message), action: action));

/// « Vider le panier ? » ; [adding] : pour ajouter un produit d'une autre
/// boutique. `true` : confirmé.
Future<bool> showClearCartSheet(
  BuildContext context, {
  required String? shopName,
  required bool adding,
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final textTheme = Theme.of(context).textTheme;
      final from = shopName == null ? 'd’une autre boutique' : 'de $shopName';
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          IviaSpacing.screen,
          0,
          IviaSpacing.screen,
          IviaSpacing.screen,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Vider le panier ?', style: textTheme.headlineSmall),
            ),
            const SizedBox(height: IviaSpacing.md),
            Text(
              adding
                  ? 'Votre panier contient des produits $from. Un panier ne '
                        'contient les produits que d’une seule boutique : le '
                        'vider pour ajouter celui-ci ?'
                  : 'Tous les produits $from seront retirés du panier.',
              style: textTheme.bodyLarge?.copyWith(
                color: IviaColors.textSecondary,
              ),
            ),
            const SizedBox(height: IviaSpacing.xl),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: IviaColors.error),
              onPressed: () => Navigator.pop(context, true),
              child: Text(adding ? 'Vider et ajouter' : 'Vider le panier'),
            ),
            const SizedBox(height: IviaSpacing.sm),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: IviaColors.background,
                foregroundColor: IviaColors.text,
              ),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
          ],
        ),
      );
    },
  );
  return confirmed ?? false;
}

/// Ajoute [count] exemplaires au panier, depuis une fiche ou une carte :
/// conflit de boutique confirmé par « Vider le panier ? », puis message
/// « … ajouté au panier » avec « Voir le panier ». `true` : ajouté.
Future<bool> addToCart(
  BuildContext context,
  WidgetRef ref, {
  required String productId,
  required String name,
  int count = 1,
}) async {
  final router = GoRouter.of(context);
  final controller = ref.read(cartProvider.notifier);
  try {
    await controller.add(productId, count);
  } on ApiException catch (e) {
    if (!context.mounted) return false;
    if (e.code != 'cart_shop_conflict') {
      showCartMessage(context, cartErrorMessage(e));
      return false;
    }
    final replace = await showClearCartSheet(
      context,
      shopName: ref.read(cartViewProvider).value?.cart.shop?.name,
      adding: true,
    );
    if (!replace || !context.mounted) return false;
    try {
      await controller.add(productId, count, replaceCart: true);
    } on ApiException catch (e) {
      if (context.mounted) showCartMessage(context, cartErrorMessage(e));
      return false;
    }
  }
  if (!context.mounted) return true;
  showCartMessage(
    context,
    count == 1 ? '$name ajouté au panier' : '$count × $name ajoutés au panier',
    action: SnackBarAction(
      label: 'Voir le panier',
      onPressed: () => router.push(Routes.cart),
    ),
  );
  return true;
}
