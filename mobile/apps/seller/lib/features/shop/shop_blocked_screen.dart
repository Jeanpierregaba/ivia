import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/seller_shop.dart';

/// Boutique refusée ou suspendue par l'admin : le motif est affiché.
class ShopBlockedScreen extends ConsumerWidget {
  const ShopBlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(sellerShopProvider).value;
    return ReviewBlockedView(
      title: shop?.status == ShopStatus.suspended
          ? 'Votre boutique est suspendue'
          : "Votre boutique n'a pas été validée",
      reason: shop?.statusReason ?? '',
      actions: [
        AsyncButton.outlined(
          label: 'Actualiser',
          onPressed: ref.read(sellerShopProvider.notifier).refresh,
        ),
        AsyncButton.text(
          label: 'Se déconnecter',
          onPressed: ref.read(authControllerProvider.notifier).signOut,
        ),
      ],
    );
  }
}
