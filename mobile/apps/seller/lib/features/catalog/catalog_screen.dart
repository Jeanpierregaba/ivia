import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';
import 'catalog_actions.dart';
import 'catalog_labels.dart';
import 'catalog_providers.dart';
import 'product_row.dart';

/// Délai de frappe avant d'envoyer la recherche au serveur.
const searchDelay = Duration(milliseconds: 300);

/// Catalogue du marchand : onglets En vente, Brouillons, Retirés, recherche.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  late final _search = TextEditingController(
    text: ref.read(catalogQueryProvider),
  );
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      ref.read(catalogQueryProvider.notifier).set('');
      return;
    }
    _debounce = Timer(
      searchDelay,
      () => ref.read(catalogQueryProvider.notifier).set(text),
    );
  }

  Future<void> _refresh() async {
    refreshCatalog(ProviderScope.containerOf(context, listen: false));
    final filter = (
      ref.read(catalogTabProvider),
      ref.read(catalogQueryProvider),
    );
    try {
      await ref.read(catalogListProvider(filter).future);
    } on Exception {
      // Erreur affichée par la liste.
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final shop = ref.watch(sellerShopProvider).value;
    final pending = shop?.status == ShopStatus.pendingReview;
    final tab = ref.watch(catalogTabProvider);
    final query = ref.watch(catalogQueryProvider);
    final counts = ref.watch(catalogCountsProvider).value;
    final filter = (tab, query);
    final list = ref.watch(catalogListProvider(filter));
    final categories = ref.watch(productCategoriesProvider).value ?? const [];

    final subtitle = [
      ?shop?.name,
      if (counts != null)
        counts.total == 1 ? '1 produit' : '${counts.total} produits',
    ].join(' · ');

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 400) {
              ref.read(catalogListProvider(filter).notifier).loadMore();
            }
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  IviaSpacing.screen,
                  IviaSpacing.lg,
                  IviaSpacing.screen,
                  0,
                ),
                sliver: SliverList.list(
                  children: [
                    if (pending) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IviaBackButton(
                          onPressed: () => context.go(Routes.shopPending),
                        ),
                      ),
                      const SizedBox(height: IviaSpacing.lg),
                    ],
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: IviaSpacing.lg,
                      runSpacing: IviaSpacing.md,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                'Catalogue',
                                style: textTheme.headlineLarge,
                              ),
                            ),
                            if (subtitle.isNotEmpty)
                              Text(subtitle, style: textTheme.bodyMedium),
                          ],
                        ),
                        FilledButton.icon(
                          onPressed: () => context.push(Routes.productNew),
                          icon: const Icon(Icons.add),
                          label: const Text(
                            'Produit',
                            semanticsLabel: 'Ajouter un produit',
                          ),
                        ),
                      ],
                    ),
                    if (pending) ...[
                      const SizedBox(height: IviaSpacing.md),
                      const IviaInfoCard(
                        text:
                            'Vos produits seront visibles dès que votre '
                            'boutique sera validée.',
                      ),
                    ],
                    const SizedBox(height: IviaSpacing.xl),
                    IviaSearchField(
                      controller: _search,
                      hint: 'Rechercher un produit',
                      onChanged: _onSearch,
                    ),
                    const SizedBox(height: IviaSpacing.lg),
                    IviaSegmentedTabs(
                      segments: [
                        for (final status in ProductStatus.values)
                          IviaSegment(
                            label: statusLabel(status),
                            count: counts?.of(status),
                          ),
                      ],
                      selected: ProductStatus.values.indexOf(tab),
                      onSelected: (i) => ref
                          .read(catalogTabProvider.notifier)
                          .select(ProductStatus.values[i]),
                    ),
                    const SizedBox(height: IviaSpacing.lg),
                  ],
                ),
              ),
              ..._body(list, tab, query, categories),
              const SliverToBoxAdapter(
                child: SizedBox(height: IviaSpacing.xxxl),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(
    AsyncValue<CatalogPage> list,
    ProductStatus tab,
    String query,
    List<ProductCategory> categories,
  ) {
    final page = list.value;
    if (list.hasError && page == null) {
      return [
        _Message(
          text: 'Impossible de charger vos produits. Vérifiez votre connexion.',
          action: OutlinedButton(
            onPressed: () {
              ref
                ..invalidate(catalogListProvider((tab, query)))
                ..invalidate(catalogCountsProvider);
            },
            child: const Text('Réessayer'),
          ),
        ),
      ];
    }
    if (page == null) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(IviaSpacing.huge),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (page.items.isEmpty) {
      return [
        _Message(
          text: query.isNotEmpty
              ? 'Aucun produit ne correspond à « $query ».'
              : switch (tab) {
                  ProductStatus.active =>
                    'Aucun produit en vente. Ajoutez votre premier produit.',
                  ProductStatus.draft => 'Aucun brouillon.',
                  ProductStatus.withdrawn => 'Aucun produit retiré.',
                },
          action: query.isEmpty && tab == ProductStatus.active
              ? FilledButton(
                  onPressed: () => context.push(Routes.productNew),
                  child: const Text('Ajouter un produit'),
                )
              : null,
        ),
      ];
    }
    final actions = CatalogActions.of(context);
    String? category(String id) {
      final c = categories.where((c) => c.id == id).firstOrNull;
      return c == null ? null : categoryLabel(c, categories);
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        sliver: SliverList.builder(
          itemCount: page.items.length,
          itemBuilder: (context, i) {
            final p = page.items[i];
            return ProductRow(
              key: ValueKey(p.id),
              product: p,
              categoryName: category(p.categoryId),
              first: i == 0,
              last: i == page.items.length - 1,
              onOpen: () => context.push(
                p.status == ProductStatus.draft
                    ? Routes.productDraft(p.id)
                    : Routes.productEdit(p.id),
              ),
              onStock: () => actions.adjustStock(context, p),
              onWithdraw: () => actions.withdraw(context, p),
              onRestore: () => actions.restore(p),
            );
          },
        ),
      ),
      if (page.loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(IviaSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (page.loadMoreFailed)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(IviaSpacing.lg),
            child: Center(
              child: TextButton(
                onPressed: () => ref
                    .read(catalogListProvider((tab, query)).notifier)
                    .loadMore(),
                child: const Text('Afficher la suite'),
              ),
            ),
          ),
        ),
    ];
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(IviaSpacing.xxl),
      sliver: SliverToBoxAdapter(
        child: Column(
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: IviaColors.textSecondary),
              ),
            ),
            if (action case final action?) ...[
              const SizedBox(height: IviaSpacing.lg),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
