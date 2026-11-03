import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';
import '../orders/order_labels.dart';
import '../orders/orders_providers.dart';

/// Accueil du marchand (boutique publiée) : commandes à accepter (avec le
/// temps restant de la plus urgente) et en cours ; un appui ouvre l'onglet
/// Commandes au bon endroit.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final shop = ref.watch(sellerShopProvider).value;
    final orders = ref.watch(sellerOrdersProvider);
    final value = orders.value;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await ref.read(sellerOrdersProvider.notifier).refresh();
          } catch (_) {
            showMessage(
              messenger,
              'Commandes non actualisées. Vérifiez votre connexion.',
            );
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            IviaSpacing.screen,
            IviaSpacing.screen,
            IviaSpacing.screen,
            IviaSpacing.huge * 3,
          ),
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
            const SizedBox(height: IviaSpacing.xxl),
            ...switch (value) {
              final v? => _summary(context, ref, v),
              null when orders.hasError => [
                Text(
                  'Impossible de charger les commandes. Tirez vers le bas '
                  'pour réessayer.',
                  style: textTheme.bodyLarge?.copyWith(
                    color: IviaColors.textSecondary,
                  ),
                ),
              ],
              null => const [
                Padding(
                  padding: EdgeInsets.all(IviaSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            },
            const SizedBox(height: IviaSpacing.xxxl),
            OutlinedButton(
              onPressed: () => context.go(Routes.catalog),
              child: const Text('Mes produits'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _summary(BuildContext context, WidgetRef ref, SellerOrders v) {
    final fresh = v.of(OrderTab.fresh);
    final active = v.count(OrderTab.active);
    if (fresh.isEmpty && active == 0) {
      return [
        Text(
          'Aucune commande à traiter. Les nouvelles commandes arrivent ici.',
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: IviaColors.textSecondary),
        ),
      ];
    }
    final urgent = fresh.firstOrNull?.sellerDeadlineAt;
    return [
      if (fresh.isNotEmpty)
        _SummaryCard(
          title: fresh.length == 1
              ? '1 nouvelle commande à accepter'
              : '${fresh.length} nouvelles commandes à accepter',
          highlight: true,
          detail: urgent == null
              ? null
              : IviaCountdown(
                  deadline: urgent,
                  now: ref.watch(apiClientProvider).now,
                  label: (t) => fresh.length == 1
                      ? 'Elle expire dans $t'
                      : 'La première expire dans $t',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
          onTap: () => context.go(Routes.ordersTab(OrderTab.fresh)),
        ),
      if (fresh.isNotEmpty && active > 0)
        const SizedBox(height: IviaSpacing.md),
      if (active > 0)
        _SummaryCard(
          title: active == 1
              ? '1 commande en cours'
              : '$active commandes en cours',
          onTap: () => context.go(Routes.ordersTab(OrderTab.active)),
        ),
    ];
  }
}

/// Carte d'un résumé : titre, détail éventuel, flèche ; tout appuyable.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.onTap,
    this.detail,
    this.highlight = false,
  });

  final String title;
  final Widget? detail;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      child: Material(
        color: highlight ? IviaColors.warningSoft : IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(IviaSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (detail case final d?) ...[
                        const SizedBox(height: IviaSpacing.xs),
                        d,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: IviaSpacing.sm),
                const ExcludeSemantics(
                  child: Icon(Icons.chevron_right, color: IviaColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
