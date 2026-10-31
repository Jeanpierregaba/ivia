import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';

/// « Votre boutique est en cours de validation » : suivi des étapes. Le
/// statut est relu au retour dans l'app et en tirant vers le bas.
class ShopPendingScreen extends ConsumerStatefulWidget {
  const ShopPendingScreen({super.key});

  @override
  ConsumerState<ShopPendingScreen> createState() => _ShopPendingScreenState();
}

class _ShopPendingScreenState extends ConsumerState<ShopPendingScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ok = await ref.read(sellerShopProvider.notifier).refresh();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Pas de connexion : statut non actualisé.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final shop = ref.watch(sellerShopProvider).value;
    final shopLine = [
      shop?.name,
      shop?.neighborhoodName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(IviaSpacing.screen),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: IviaSpacing.huge),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: IviaColors.surface,
                            shape: BoxShape.circle,
                          ),
                          // Anneau fixe (maquette) : l'attente se compte en
                          // heures, pas en secondes.
                          child: const CircularProgressIndicator(
                            value: 0.75,
                            strokeWidth: 4,
                            backgroundColor: IviaColors.border,
                            semanticsLabel: 'Validation en cours',
                          ),
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.xxl),
                      Semantics(
                        header: true,
                        child: Text(
                          'Votre boutique est en cours de validation',
                          style: textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.sm),
                      Text(
                        "L'équipe ivia vérifie vos informations. Vous "
                        'recevrez une notification dès que la boutique sera '
                        'publiée.',
                        style: textTheme.bodyLarge?.copyWith(
                          color: IviaColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.xxl),
                      IviaStepList(
                        steps: [
                          const IviaStep(
                            title: 'Compte créé',
                            state: IviaStepState.done,
                          ),
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
                      ),
                      const Spacer(),
                      const SizedBox(height: IviaSpacing.xxl),
                      FilledButton(
                        onPressed: () => context.push(Routes.products),
                        child: const Text('Préparer mes produits'),
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
