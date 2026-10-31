import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';

/// « Votre boutique est en cours de validation » : suivi des étapes.
class ShopPendingScreen extends ConsumerWidget {
  const ShopPendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(sellerShopProvider).value;
    final shopLine = [
      shop?.name,
      shop?.neighborhoodName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return ReviewPendingView(
      title: 'Votre boutique est en cours de validation',
      body:
          "L'équipe ivia vérifie vos informations. Vous recevrez une "
          'notification dès que la boutique sera publiée.',
      onRefresh: ref.read(sellerShopProvider.notifier).refresh,
      steps: [
        const IviaStep(title: 'Compte créé', state: IviaStepState.done),
        IviaStep(
          title: 'Boutique envoyée',
          subtitle: shopLine.isEmpty ? null : shopLine,
          state: IviaStepState.done,
        ),
        const IviaStep(
          title: 'Validation par ivia',
          subtitle: 'En cours',
          state: IviaStepState.current,
        ),
        const IviaStep(
          title: 'Boutique visible des acheteurs',
          state: IviaStepState.upcoming,
        ),
      ],
      action: FilledButton(
        onPressed: () => context.push(Routes.products),
        child: const Text('Préparer mes produits'),
      ),
    );
  }
}
