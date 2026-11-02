import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';

/// « Votre boutique est en cours de validation » : suivi des étapes. Sans
/// pièce d'identité, la validation attend : l'écran mène aux pièces.
class ShopPendingScreen extends ConsumerWidget {
  const ShopPendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(sellerShopProvider).value;
    final shopLine = [
      shop?.name,
      shop?.neighborhoodName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    // `null` : boutique lue sans ses pièces, l'étape n'est pas affichée.
    final hasIdCard = shop?.merchantDocuments?.contains(
      MerchantDocumentKind.idCard,
    );
    final missing = hasIdCard == false;
    return ReviewPendingView(
      progressLabel: 'Validation en cours',
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
        if (hasIdCard != null)
          IviaStep(
            title: "Pièce d'identité",
            subtitle: missing
                ? 'À ajouter : sans elle, la boutique ne peut pas être publiée'
                : 'Envoyée',
            state: missing ? IviaStepState.current : IviaStepState.done,
          ),
        IviaStep(
          title: 'Validation par ivia',
          subtitle: missing ? null : 'En cours',
          state: missing ? IviaStepState.upcoming : IviaStepState.current,
        ),
        const IviaStep(
          title: 'Boutique visible des acheteurs',
          state: IviaStepState.upcoming,
        ),
      ],
      action: missing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () => context.go(Routes.shopDocuments),
                  child: const Text("Ajouter ma pièce d'identité"),
                ),
                const SizedBox(height: IviaSpacing.sm),
                OutlinedButton(
                  onPressed: () => context.go(Routes.catalog),
                  child: const Text('Préparer mes produits'),
                ),
              ],
            )
          : FilledButton(
              onPressed: () => context.go(Routes.catalog),
              child: const Text('Préparer mes produits'),
            ),
    );
  }
}
