import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/router.dart';
import '../cart/cart_actions.dart';
import 'promo_state.dart';

// Boutons d'une publicité : la commande passe par le panier habituel (pas de
// circuit parallèle), le site officiel s'ouvre dans le navigateur.

/// « Commander maintenant » : un exemplaire au panier, puis le panier.
Future<void> orderFromPromo(
  BuildContext context,
  WidgetRef ref,
  Product product, {
  PromoVisual? visual,
  PromoPlacement? placement,
}) async {
  ref
      .read(promoTrackerProvider)
      .track(
        'click_order',
        visual: visual,
        productId: product.id,
        placement: placement,
      );
  final router = GoRouter.of(context);
  final added = await addToCart(
    context,
    ref,
    productId: product.id,
    name: product.name,
  );
  if (added && router.state.matchedLocation != Routes.cart) {
    router.push(Routes.cart);
  }
}

/// « Découvrir le produit » : sa fiche.
void openPromoProduct(
  BuildContext context,
  WidgetRef ref,
  String productId, {
  PromoVisual? visual,
  PromoPlacement? placement,
}) {
  ref
      .read(promoTrackerProvider)
      .track(
        'click_product',
        visual: visual,
        productId: productId,
        placement: placement,
      );
  context.push(Routes.product(productId));
}

/// « Visiter le site officiel » : navigateur du téléphone.
Future<void> visitPromoSite(
  BuildContext context,
  WidgetRef ref,
  String url, {
  PromoVisual? visual,
  PromoPlacement? placement,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return;
  ref
      .read(promoTrackerProvider)
      .track('click_site', visual: visual, placement: placement);
  final messenger = ScaffoldMessenger.of(context);
  final opened = await ref.read(linkOpenerProvider)(uri);
  if (!opened) {
    showMessage(messenger, 'Impossible d’ouvrir le site. Réessayez plus tard.');
  }
}

/// Site d'un visuel : le sien, sinon le site officiel des réglages.
String promoSiteOf(PromoVisual visual, PromoSettings settings) =>
    visual.externalUrl.isNotEmpty ? visual.externalUrl : settings.officialUrl;
