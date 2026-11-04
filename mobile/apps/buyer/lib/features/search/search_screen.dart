import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/buyer_area.dart';
import '../../app/catalog_data.dart';
import '../../app/router.dart';
import '../home/area_sheet.dart';
import '../promo/promo_state.dart';
import 'product_grid.dart';
import 'search_results.dart';
import 'search_sheets.dart';
import 'search_state.dart';

/// Délai de frappe avant d'envoyer la recherche.
const searchDelay = Duration(milliseconds: 300);

/// Onglet Recherche : texte, produits ou boutiques, filtres, tri.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _text = TextEditingController(
    text: ref.read(searchFiltersProvider).text,
  );
  final _focus = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Appui sur le champ de l'accueil avant l'ouverture de l'onglet.
    if (ref.read(searchFocusRequestProvider) > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  SearchFiltersState get _filters => ref.read(searchFiltersProvider.notifier);

  void _onText(String text) {
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      _filters.update((f) => f.copyWith(text: ''));
      return;
    }
    _debounce = Timer(
      searchDelay,
      () => _filters.update((f) => f.copyWith(text: text.trim())),
    );
  }

  Future<void> _pickRadius(SearchFilters filters) async {
    final picked = await showRadiusSheet(context, filters.radiusKm);
    if (picked != null) {
      _filters.update((f) => f.copyWith(radiusKm: () => picked.value));
    }
  }

  Future<void> _pickCategory(SearchFilters filters) async {
    final all = ref.read(categoriesProvider).value;
    if (all == null) {
      ref.invalidate(categoriesProvider);
      return;
    }
    final picked = await showCategorySheet(context, all, filters.categoryId);
    if (picked != null) {
      _filters.update((f) => f.copyWith(categoryId: () => picked.value));
    }
  }

  Future<void> _pickPrice(SearchFilters filters) async {
    final picked = await showPriceSheet(
      context,
      min: filters.minPrice,
      max: filters.maxPrice,
    );
    if (picked case (final min, final max)) {
      _filters.update(
        (f) => f.copyWith(minPrice: () => min, maxPrice: () => max),
      );
    }
  }

  Future<void> _pickSort(SearchFilters filters, BuyerArea area) async {
    final picked = await showSortSheet(
      context,
      current: filters.toQuery(area).sort,
      withDistance: area.point != null,
      products: filters.tab == SearchTab.products,
    );
    if (picked != null) _filters.update((f) => f.copyWith(sort: picked.value));
  }

  void _retry(SearchFilters filters, SearchQuery query) => ref.invalidate(
    filters.tab == SearchTab.products
        ? productResultsProvider(query)
        : shopResultsProvider(query),
  );

  void _loadMore(SearchFilters filters, SearchQuery query) =>
      filters.tab == SearchTab.products
      ? ref.read(productResultsProvider(query).notifier).loadMore()
      : ref.read(shopResultsProvider(query).notifier).loadMore();

  @override
  Widget build(BuildContext context) {
    final area = ref.watch(buyerAreaProvider);
    final filters = ref.watch(searchFiltersProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final query = filters.toQuery(area);
    final products = filters.tab == SearchTab.products;

    ref
      ..listen(searchFocusRequestProvider, (_, _) => _focus.requestFocus())
      // Texte posé depuis l'accueil (nouvelle recherche) : le champ suit.
      // Nouvelle recherche depuis l'accueil : la frappe en attente est
      // abandonnée et le champ prend le texte de la recherche.
      ..listen(searchFiltersProvider.select((f) => f.session), (_, _) {
        _debounce?.cancel();
        _text.text = ref.read(searchFiltersProvider).text;
      });

    final zoneChip = switch (area) {
      AreaPosition() => IviaChip(
        label: filters.radiusKm == null
            ? 'Autour de moi'
            : 'Autour de moi · ${filters.radiusKm} km',
        selected: true,
        dropdown: true,
        onTap: () => _pickRadius(filters),
      ),
      AreaNeighborhood(:final name) => IviaChip(
        label: name,
        selected: true,
        dropdown: true,
        onTap: () => showAreaSheet(context),
      ),
      _ => IviaChip(
        label: 'Choisir un quartier',
        dropdown: true,
        onTap: () => showAreaSheet(context),
      ),
    };
    final chips = <Widget>[
      zoneChip,
      if (products) ...[
        IviaChip(
          label: categoryName(categories, filters.categoryId) ?? 'Catégorie',
          selected: filters.categoryId != null,
          dropdown: true,
          onTap: () => _pickCategory(filters),
        ),
        IviaChip(
          label: priceLabel(filters.minPrice, filters.maxPrice) ?? 'Prix',
          selected: filters.minPrice != null || filters.maxPrice != null,
          dropdown: true,
          onTap: () => _pickPrice(filters),
        ),
        IviaChip(
          label: 'En stock',
          selected: filters.inStockOnly,
          onTap: () =>
              _filters.update((f) => f.copyWith(inStockOnly: !f.inStockOnly)),
        ),
      ],
    ];

    return SafeArea(
      bottom: false,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0 &&
              n.metrics.axis == Axis.vertical &&
              n.metrics.extentAfter < 400) {
            _loadMore(filters, query);
          }
          return false;
        },
        child: CustomScrollView(
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
                  IviaSearchField(
                    controller: _text,
                    focusNode: _focus,
                    hint: 'Produit ou boutique…',
                    maxLength: 100,
                    onChanged: _onText,
                  ),
                  const SizedBox(height: IviaSpacing.lg),
                  IviaSegmentedTabs(
                    segments: const [
                      IviaSegment(label: 'Produits'),
                      IviaSegment(label: 'Boutiques'),
                    ],
                    selected: products ? 0 : 1,
                    onSelected: (i) => _filters.update(
                      (f) => f.copyWith(tab: SearchTab.values[i]),
                    ),
                  ),
                  const SizedBox(height: IviaSpacing.md),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48 * MediaQuery.textScalerOf(context).scale(1),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: IviaSpacing.screen,
                  ),
                  itemCount: chips.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: IviaSpacing.sm),
                  itemBuilder: (_, i) => Center(child: chips[i]),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: IviaSpacing.screen,
                vertical: IviaSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _pickSort(filters, area),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_drop_down),
                    label: Text('Trier : ${sortLabel(query.sort)}'),
                  ),
                ),
              ),
            ),
            if (area is AreaLocating)
              const SliverToBoxAdapter(child: _Loading())
            else if (products)
              ..._results(
                ref.watch(productResultsProvider(query)),
                area: area,
                filters: filters,
                query: query,
                // Navigation sans texte : les produits mis en avant
                // reviennent dans la liste (recherche précise : intacte).
                builder: (items) => ProductGridSliver(
                  items: filters.text.isEmpty
                      ? withFeatured(ref, items)
                      : items,
                ),
                emptyText: filters.text.isEmpty
                    ? 'Aucun produit autour de vous pour l’instant.'
                    : 'Aucun produit ne correspond à « ${filters.text} ».',
              )
            else
              ..._results(
                ref.watch(shopResultsProvider(query)),
                area: area,
                filters: filters,
                query: query,
                builder: (items) => SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IviaSpacing.screen,
                  ),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: IviaSpacing.sm),
                    itemBuilder: (context, i) => _ShopRow(shop: items[i]),
                  ),
                ),
                emptyText: filters.text.isEmpty
                    ? 'Aucune boutique autour de vous pour l’instant.'
                    : 'Aucune boutique ne correspond à « ${filters.text} ».',
              ),
            const SliverToBoxAdapter(child: SizedBox(height: IviaSpacing.xxxl)),
          ],
        ),
      ),
    );
  }

  List<Widget> _results<T>(
    AsyncValue<Results<T>> results, {
    required BuyerArea area,
    required SearchFilters filters,
    required SearchQuery query,
    required Widget Function(List<T> items) builder,
    required String emptyText,
  }) {
    final page = results.value;
    if (results.hasError && page == null) {
      final error = results.error;
      return [
        SliverToBoxAdapter(
          child: _Message(
            text: error is ApiException && !error.isNetwork
                ? error.message
                : 'Impossible de charger les résultats. Vérifiez votre '
                      'connexion.',
            action: OutlinedButton(
              onPressed: () => _retry(filters, query),
              child: const Text('Réessayer'),
            ),
          ),
        ),
      ];
    }
    if (page == null) return const [SliverToBoxAdapter(child: _Loading())];
    if (page.items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _Message(
            text: emptyText,
            action: filters.hasFiltersFor(area)
                ? OutlinedButton(
                    onPressed: _filters.clearFilters,
                    child: const Text('Effacer les filtres'),
                  )
                : null,
          ),
        ),
      ];
    }
    return [
      builder(page.items),
      if (page.loadingMore)
        const SliverToBoxAdapter(child: _Loading())
      else if (page.loadMoreFailed)
        SliverToBoxAdapter(
          child: Center(
            child: TextButton(
              onPressed: () => _loadMore(filters, query),
              child: const Text('Afficher la suite'),
            ),
          ),
        ),
    ];
  }
}

/// Boutique trouvée : logo, nom, « quartier · distance ».
class _ShopRow extends ConsumerWidget {
  const _ShopRow({required this.shop});

  final ShopHit shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final place = neighborhoodName(ref, shop.neighborhoodId);
    final distance = switch (shop.distanceM) {
      final m? => formatDistance(m),
      null => null,
    };
    final spoken = [
      shop.name,
      ?place,
      ?distance,
      if (!shop.acceptingOrders) 'commandes suspendues',
    ].join(', ');
    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      onTap: () => context.push(Routes.shop(shop.id)),
      child: Material(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
        child: InkWell(
          borderRadius: BorderRadius.circular(IviaRadius.large),
          onTap: () => context.push(Routes.shop(shop.id)),
          child: Padding(
            padding: const EdgeInsets.all(IviaSpacing.md),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 56,
                  child: IviaNetworkImage(url: shop.logoUrl),
                ),
                const SizedBox(width: IviaSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          text: place ?? '',
                          children: [
                            if (distance case final d?)
                              TextSpan(
                                text: place == null ? d : ' · $d',
                                style: const TextStyle(
                                  color: IviaColors.cobaltBlue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        style: textTheme.bodySmall,
                      ),
                      if (!shop.acceptingOrders)
                        Text(
                          'Commandes suspendues',
                          style: textTheme.bodySmall?.copyWith(
                            color: IviaColors.error,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: IviaColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(IviaSpacing.xxl),
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
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(IviaSpacing.xxl),
    child: Center(child: CircularProgressIndicator()),
  );
}
