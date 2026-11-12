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
    // Maquette A01 : rond blanc, chariot, pastille rouge du nombre d'articles.
    return Semantics(
      button: true,
      label: count == 0 ? 'Panier' : 'Panier, ${articlesLabel(count)}',
      excludeSemantics: true,
      onTap: () => context.push(Routes.cart),
      child: Tooltip(
        message: 'Panier',
        child: Material(
          color: IviaColors.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.push(Routes.cart),
            child: SizedBox.square(
              dimension: 60,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.shopping_cart_outlined,
                    color: Color(0xFF111C33),
                    size: 28,
                  ),
                  if (count > 0)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: IviaColors.imperialRed,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: AnimatedSwitcher(
                          duration: IviaMotion.of(context, IviaMotion.medium),
                          transitionBuilder: (child, a) => ScaleTransition(
                            scale: CurvedAnimation(
                              parent: a,
                              curve: Curves.easeOutBack,
                            ),
                            child: child,
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            key: ValueKey(count),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
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
