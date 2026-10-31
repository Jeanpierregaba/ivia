import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/seller_shop.dart';

/// Boutique refusée ou suspendue par l'admin : le motif est affiché.
class ShopBlockedScreen extends ConsumerWidget {
  const ShopBlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final shop = ref.watch(sellerShopProvider).value;
    final suspended = shop?.status == ShopStatus.suspended;
    final reason = shop?.statusReason ?? '';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(IviaSpacing.screen),
          children: [
            const SizedBox(height: IviaSpacing.huge),
            const Icon(
              Icons.report_outlined,
              size: 56,
              color: IviaColors.error,
            ),
            const SizedBox(height: IviaSpacing.xxl),
            Semantics(
              header: true,
              child: Text(
                suspended
                    ? 'Votre boutique est suspendue'
                    : "Votre boutique n'a pas été validée",
                style: textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(
              reason.isEmpty
                  ? "Contactez l'équipe ivia pour en savoir plus."
                  : 'Motif : $reason',
              style: textTheme.bodyLarge?.copyWith(
                color: IviaColors.textSecondary,
              ),
            ),
            const SizedBox(height: IviaSpacing.xxxl),
            AsyncButton.outlined(
              label: 'Actualiser',
              onPressed: ref.read(sellerShopProvider.notifier).refresh,
            ),
            const SizedBox(height: IviaSpacing.sm),
            AsyncButton.text(
              label: 'Se déconnecter',
              onPressed: ref.read(authControllerProvider.notifier).signOut,
            ),
          ],
        ),
      ),
    );
  }
}
