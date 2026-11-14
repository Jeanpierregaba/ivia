import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';
import 'catalog_labels.dart';
import 'product_sheets.dart';

/// « Produit publié » : le texte dit quand les acheteurs le verront.
class ProductPublishedScreen extends ConsumerWidget {
  const ProductPublishedScreen({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final shop = ref.watch(sellerShopProvider).value;
    final published = shop?.status == ShopStatus.published;
    final area = shop?.neighborhoodName ?? '';
    final body = !published
        ? 'Il sera visible dès que votre boutique sera validée.'
        : area.isEmpty
        ? 'Il est visible maintenant par les acheteurs du quartier.'
        : 'Il est visible maintenant par les acheteurs autour de $area.';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(Routes.catalog);
      },
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(IviaSpacing.screen),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(IviaSpacing.md),
                          decoration: const BoxDecoration(
                            color: IviaColors.secondarySoft,
                            shape: BoxShape.circle,
                          ),
                          child: Container(
                            width: 84,
                            height: 84,
                            decoration: const BoxDecoration(
                              color: IviaColors.cobaltBlue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.xxl),
                      Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(
                          'Produit publié',
                          style: textTheme.headlineLarge,
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.sm),
                      Text(
                        body,
                        style: textTheme.bodyLarge?.copyWith(
                          color: IviaColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.xxl),
                      Container(
                        padding: const EdgeInsets.all(IviaSpacing.lg),
                        decoration: BoxDecoration(
                          color: IviaColors.surface,
                          borderRadius: BorderRadius.circular(IviaRadius.large),
                        ),
                        child: Row(
                          children: [
                            ProductThumb(url: product.images.firstOrNull?.url),
                            const SizedBox(width: IviaSpacing.lg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'En vente · ${stockLabel(product)}',
                                    style: textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: IviaSpacing.sm),
                            const IviaStatusPill(label: 'En vente'),
                          ],
                        ),
                      ),
                      const Spacer(flex: 2),
                      const SizedBox(height: IviaSpacing.xxl),
                      FilledButton(
                        onPressed: () => context.go(Routes.productNew),
                        child: const Text('Ajouter un autre produit'),
                      ),
                      const SizedBox(height: IviaSpacing.sm),
                      OutlinedButton(
                        onPressed: () => context.go(Routes.catalog),
                        child: const Text('Retour au catalogue'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
