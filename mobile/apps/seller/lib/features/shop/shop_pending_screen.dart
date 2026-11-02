import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';
import 'merchant_documents.dart';

/// « Votre boutique est en cours de validation » : suivi des étapes et
/// pièces du marchand. Sans pièce d'identité, l'équipe ivia ne peut pas
/// publier la boutique : l'étape l'annonce et l'encart permet de l'envoyer.
class ShopPendingScreen extends ConsumerWidget {
  const ShopPendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(sellerShopProvider).value;
    final shopLine = [
      shop?.name,
      shop?.neighborhoodName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final identity = shop?.identityProvided ?? false;
    return ReviewPendingView(
      progressLabel: 'Validation en cours',
      title: 'Votre boutique est en cours de validation',
      body: identity
          ? "L'équipe ivia vérifie vos informations. Vous recevrez une "
                'notification dès que la boutique sera publiée.'
          : "Ajoutez votre pièce d'identité : l'équipe ivia la vérifie "
                'avant de publier votre boutique.',
      onRefresh: ref.read(sellerShopProvider.notifier).refresh,
      steps: [
        const IviaStep(title: 'Compte créé', state: IviaStepState.done),
        IviaStep(
          title: 'Boutique envoyée',
          subtitle: shopLine.isEmpty ? null : shopLine,
          state: IviaStepState.done,
        ),
        IviaStep(
          title: "Pièce d'identité",
          subtitle: identity ? 'Envoyée' : 'À ajouter ci-dessous',
          state: identity ? IviaStepState.done : IviaStepState.current,
        ),
        IviaStep(
          title: 'Validation par ivia',
          subtitle: identity ? 'En cours' : null,
          state: identity ? IviaStepState.current : IviaStepState.upcoming,
        ),
        const IviaStep(
          title: 'Boutique visible des acheteurs',
          state: IviaStepState.upcoming,
        ),
      ],
      extra: shop == null ? null : MerchantDocumentsSection(shop: shop),
      action: FilledButton(
        onPressed: () => context.go(Routes.catalog),
        child: const Text('Préparer mes produits'),
      ),
    );
  }
}
