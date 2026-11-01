import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';

/// Accueil provisoire du marchand (boutique publiée), onglet Accueil ;
/// remplacé par le résumé de la boutique et des commandes (011).
class HomePlaceholderScreen extends ConsumerWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final shop = ref.watch(sellerShopProvider).value;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(IviaSpacing.screen),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IviaLogoTile(color: IviaAppBrand.seller.accent),
          ),
          const SizedBox(height: IviaSpacing.xxl),
          Semantics(
            header: true,
            child: Text(
              shop?.name ?? 'Votre boutique',
              style: textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: IviaSpacing.sm),
          Text(
            'Votre boutique est publiée : les acheteurs du quartier la '
            'voient. Les commandes arrivent bientôt ici.',
            style: textTheme.bodyLarge?.copyWith(
              color: IviaColors.textSecondary,
            ),
          ),
          const SizedBox(height: IviaSpacing.xxxl),
          FilledButton(
            onPressed: () => context.go(Routes.catalog),
            child: const Text('Mes produits'),
          ),
        ],
      ),
    );
  }
}
