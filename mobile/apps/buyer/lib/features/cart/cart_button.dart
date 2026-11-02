import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/cart.dart';
import '../../app/router.dart';

/// « 3 articles ».
String articlesLabel(int count) => '$count article${count > 1 ? 's' : ''}';

/// Icône du panier des en-têtes : pastille du nombre d'articles, ouvre le
/// panier.
class CartButton extends ConsumerWidget {
  const CartButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      cartViewProvider.select((c) => c.value?.cart.articleCount ?? 0),
    );
    return IviaIconBadgeButton(
      icon: Icons.shopping_bag_outlined,
      label: 'Panier',
      count: count,
      semanticLabel: count == 0 ? 'Panier' : 'Panier, ${articlesLabel(count)}',
      onPressed: () => context.push(Routes.cart),
    );
  }
}

/// « Voir le panier · 3 — 10 500 F » en bas d'une fiche boutique, quand le
/// panier contient des produits de cette boutique ; rien sinon.
class CartBar extends ConsumerWidget {
  const CartBar({super.key, required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartViewProvider).value?.cart;
    if (cart == null || cart.isEmpty || cart.shop?.id != shopId) {
      return const SizedBox.shrink();
    }
    // Même nombre que la pastille. Le sous-total ne compte pas les lignes
    // qui bloquent : avec l'une d'elles, il ne correspondrait pas au nombre,
    // la barre invite donc à vérifier le panier.
    final count = cart.articleCount;
    final amount = cart.items.any((i) => i.hasIssue)
        ? 'À vérifier'
        : formatXof(cart.subtotalXof);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        IviaSpacing.screen,
        IviaSpacing.sm,
        IviaSpacing.screen,
        IviaSpacing.screen,
      ),
      child: Semantics(
        button: true,
        label: 'Voir le panier, ${articlesLabel(count)}, $amount',
        excludeSemantics: true,
        onTap: () => context.push(Routes.cart),
        child: FilledButton(
          onPressed: () => context.push(Routes.cart),
          child: Row(
            children: [
              const Icon(Icons.shopping_bag_outlined),
              const SizedBox(width: IviaSpacing.sm),
              Expanded(child: Text('Voir le panier · $count')),
              const SizedBox(width: IviaSpacing.sm),
              Flexible(child: Text(amount, textAlign: TextAlign.end)),
            ],
          ),
        ),
      ),
    );
  }
}
