import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart' hide statusLabel;
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/business_state.dart';
import '../../app/router.dart';
import '../../app/seller_shop.dart';
import '../business/biz_ui.dart';
import 'catalog_actions.dart';
import 'catalog_labels.dart';
import 'catalog_providers.dart';
import 'product_row.dart';

/// Délai de frappe avant d'envoyer la recherche au serveur.
const searchDelay = Duration(milliseconds: 300);

/// Produits du marchand : recherche, états (En vente, Brouillons, Retirés),
/// catégorie, liste ou grille, glissements et sélection multiple.
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

  /// Sélection multiple (appui long) : produits cochés.
  final _selected = <String, Product>{};
  var _bulkBusy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    setState(() {});
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

  void _clearSearch() {
    _search.clear();
    _onSearch('');
  }

  Future<void> _refresh() async {
    refreshCatalog(ProviderScope.containerOf(context, listen: false));
    final filter = watchFilterNow();
    try {
      await ref.read(catalogListProvider(filter).future);
    } on Exception catch (e) {
      // Liste déjà affichée : elle reste, un message dit qu'elle n'est pas
      // à jour.
      if (!mounted || ref.read(catalogListProvider(filter)).value == null) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Catalogue non actualisé. '
              '${catalogErrorMessage(ProviderScope.containerOf(context, listen: false), e)}',
            ),
          ),
        );
    }
  }

  CatalogFilter watchFilterNow() => (
    ref.read(catalogTabProvider),
    ref.read(catalogQueryProvider),
    ref.read(catalogCategoryProvider),
  );

  /// Boutique suspendue ou retirée entre-temps : la boutique est relue et le
  /// routeur ouvre l'écran qui l'explique.
  void _onLoadError(Object? error) {
    if (error is ApiException &&
        (error.code == 'shop_suspended' || error.code == 'shop_not_found')) {
      ref.read(sellerShopProvider.notifier).refresh();
    }
  }

  void _toggle(Product p) {
    setState(() {
      if (_selected.remove(p.id) == null) _selected[p.id] = p;
    });
  }

  Future<void> _chooseCategory(List<ProductCategory> all) async {
    final current = ref.read(catalogCategoryProvider);
    final picked = await showCategorySheet(
      context,
      categories: all,
      selected: current,
      allowAll: true,
    );
    if (picked == null || !mounted) return;
    ref
        .read(catalogCategoryProvider.notifier)
        .select(picked.isEmpty ? null : picked);
  }

  /// Retire ou remet en vente les produits cochés.
  Future<void> _bulk({required bool activate}) async {
    final items = _selected.values.toList();
    if (items.isEmpty || _bulkBusy) return;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    if (!activate) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            items.length == 1
                ? 'Retirer 1 produit de la vente ?'
                : 'Retirer ${items.length} produits de la vente ?',
          ),
          content: const Text(
            'Ils ne seront plus visibles par les acheteurs. Vous pourrez les '
            'remettre en vente à tout moment.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Garder'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Retirer'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _bulkBusy = true);
    final client = ref.read(apiClientProvider);
    var done = 0;
    var skipped = 0;
    for (final p in items) {
      // Mise en vente : une photo au moins (règle du serveur).
      if (activate && p.images.isEmpty) {
        skipped++;
        continue;
      }
      try {
        await client.updateProduct(p.id, inputFrom(p, isActive: activate));
        done++;
      } on Exception {
        skipped++;
      }
    }
    refreshCatalog(container);
    if (!mounted) return;
    setState(() {
      _bulkBusy = false;
      _selected.clear();
    });
    final what = activate ? 'mis en vente' : 'retiré${done > 1 ? 's' : ''}';
    showMessage(
      messenger,
      [
        done == 1 ? '1 produit $what' : '$done produits $what',
        if (skipped > 0)
          activate ? '$skipped sans photo ou en erreur' : '$skipped en erreur',
      ].join(' · '),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(sellerShopProvider).value;
    final pending = shop?.status == ShopStatus.pendingReview;
    final tab = ref.watch(catalogTabProvider);
    final query = ref.watch(catalogQueryProvider);
    final category = ref.watch(catalogCategoryProvider);
    final grid = ref.watch(catalogGridProvider);
    final counts = ref.watch(catalogCountsProvider).value;
    final filter = watchCatalogFilter(ref);
    final list = ref.watch(catalogListProvider(filter));
    ref
      ..listen(
        catalogListProvider(filter),
        (_, next) => _onLoadError(next.error),
      )
      ..listen(catalogCountsProvider, (_, next) => _onLoadError(next.error))
      // Changement d'onglet ou de filtre : la sélection repart de zéro.
      ..listen(catalogTabProvider, (_, _) => setState(_selected.clear));
    final categories = ref.watch(productCategoriesProvider).value ?? const [];
    final restaurant =
        ref.watch(businessGateProvider).value?.opened?.sector == 'restaurant';
    final categoryName = categories
        .where((c) => c.id == category)
        .map((c) => c.name)
        .firstOrNull;

    final subtitle = [
      ?shop?.name,
      if (counts != null)
        counts.total == 1 ? '1 produit' : '${counts.total} produits',
    ].join(' · ');
    final selecting = _selected.isNotEmpty;

    return PopScope(
      // En attente de validation, le catalogue remplace l'écran de
      // validation : le retour d'Android y revient au lieu de fermer l'app.
      // En sélection : le retour la quitte d'abord.
      canPop: !pending && !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) {
          setState(_selected.clear);
        } else if (pending) {
          context.go(Routes.shopPending);
        }
      },
      child: ColoredBox(
        color: Biz.page,
        child: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: Biz.navy,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    // Défilement vertical de la liste seulement ; après un
                    // échec, « Afficher la suite » relance.
                    if (n.depth == 0 &&
                        n.metrics.axis == Axis.vertical &&
                        n.metrics.extentAfter < 400 &&
                        !(list.value?.loadMoreFailed ?? false)) {
                      ref.read(catalogListProvider(filter).notifier).loadMore();
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        sliver: SliverList.list(
                          children: [
                            if (pending) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: IviaBackButton(
                                  onPressed: () =>
                                      context.go(Routes.shopPending),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            BizHeader(
                              title: restaurant ? 'Menu' : 'Produits',
                              subtitle: subtitle,
                              trailing: [
                                _AddButton(
                                  onTap: () => context.push(Routes.productNew),
                                ),
                                if (shop != null) _ShopAvatar(shop: shop),
                              ],
                            ),
                            if (pending) ...[
                              const SizedBox(height: 12),
                              const IviaInfoCard(
                                text:
                                    'Vos produits seront visibles dès que '
                                    'votre boutique sera validée.',
                              ),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: _SearchField(
                                    controller: _search,
                                    onChanged: _onSearch,
                                    onClear: _clearSearch,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                BizIconButton(
                                  icon: Icons.tune_rounded,
                                  tooltip: 'Filtrer par catégorie',
                                  badge: category != null,
                                  onPressed: () => _chooseCategory(categories),
                                ),
                                const SizedBox(width: 8),
                                BizIconButton(
                                  icon: grid
                                      ? Icons.view_agenda_outlined
                                      : Icons.grid_view_rounded,
                                  tooltip: grid
                                      ? 'Afficher en liste'
                                      : 'Afficher en grille',
                                  onPressed: () => ref
                                      .read(catalogGridProvider.notifier)
                                      .toggle(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              for (final status in ProductStatus.values) ...[
                                BizFilterChip(
                                  label: statusLabel(status),
                                  count: counts?.of(status),
                                  active: tab == status,
                                  onTap: () => ref
                                      .read(catalogTabProvider.notifier)
                                      .select(status),
                                ),
                                const SizedBox(width: 8),
                              ],
                              BizFilterChip(
                                label: categoryName ?? 'Catégorie',
                                icon: categoryName == null
                                    ? Icons.expand_more_rounded
                                    : Icons.close_rounded,
                                active: categoryName != null,
                                onTap: () => categoryName == null
                                    ? _chooseCategory(categories)
                                    : ref
                                          .read(
                                            catalogCategoryProvider.notifier,
                                          )
                                          .select(null),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 14)),
                      ..._body(list, filter, query, categories, grid),
                      SliverToBoxAdapter(
                        child: SizedBox(height: selecting ? 120 : 32),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Barre de la sélection multiple, qui glisse depuis le bas.
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: IgnorePointer(
                ignoring: !selecting,
                child: AnimatedSlide(
                  offset: selecting ? Offset.zero : const Offset(0, 1.6),
                  duration: Biz.medium,
                  curve: Curves.easeOutCubic,
                  child: _SelectionBar(
                    count: _selected.length,
                    busy: _bulkBusy,
                    activate: tab != ProductStatus.active,
                    onAll: () => setState(() {
                      for (final p in list.value?.items ?? const <Product>[]) {
                        _selected[p.id] = p;
                      }
                    }),
                    onClose: () => setState(_selected.clear),
                    onApply: () => _bulk(activate: tab != ProductStatus.active),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(
    AsyncValue<CatalogPage> list,
    CatalogFilter filter,
    String query,
    List<ProductCategory> categories,
    bool grid,
  ) {
    final tab = filter.$1;
    final page = list.value;
    if (list.hasError && page == null) {
      final error = list.error;
      return [
        SliverToBoxAdapter(
          child: BizEmpty(
            icon: Icons.cloud_off_rounded,
            color: Biz.red,
            title: error is ApiException && !error.isNetwork ? error.message : 'Impossible de charger vos produits. Vérifiez votre connexion.',
            action: BizButton(
              outlined: true,
              icon: Icons.refresh_rounded,
              label: 'Réessayer',
              onPressed: () {
                ref
                  ..invalidate(catalogListProvider(filter))
                  ..invalidate(catalogCountsProvider);
              },
            ),
          ),
        ),
      ];
    }
    if (page == null) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.list(
            children: [
              for (var i = 0; i < 5; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: _RowSkeleton(),
                ),
            ],
          ),
        ),
      ];
    }
    if (page.items.isEmpty) {
      final filtered = query.isNotEmpty || filter.$3 != null;
      return [
        SliverToBoxAdapter(
          child: BizEmpty(
            icon: filtered
                ? Icons.search_off_rounded
                : switch (tab) {
                    ProductStatus.active => Icons.add_photo_alternate_outlined,
                    ProductStatus.draft => Icons.edit_note_rounded,
                    ProductStatus.withdrawn => Icons.inventory_2_outlined,
                  },
            title: query.isNotEmpty
                ? 'Aucun produit ne correspond à « $query ».'
                : filter.$3 != null
                ? 'Aucun produit dans cette catégorie.'
                : switch (tab) {
                    ProductStatus.active =>
                      'Aucun produit en vente. Ajoutez votre premier produit.',
                    ProductStatus.draft => 'Aucun brouillon.',
                    ProductStatus.withdrawn => 'Aucun produit retiré.',
                  },
            body: !filtered && tab == ProductStatus.active
                ? 'Une belle photo et un prix clair suffisent pour commencer.'
                : null,
            action: !filtered && tab == ProductStatus.active
                ? BizButton(
                    color: Biz.red,
                    icon: Icons.add_rounded,
                    label: 'Ajouter un produit',
                    onPressed: () => context.push(Routes.productNew),
                  )
                : null,
          ),
        ),
      ];
    }
    final actions = CatalogActions.of(context);
    String? category(String id) {
      final c = categories.where((c) => c.id == id).firstOrNull;
      return c == null ? null : categoryLabel(c, categories);
    }

    void open(Product p) => context.push(
      p.status == ProductStatus.draft
          ? Routes.productDraft(p.id)
          : Routes.productEdit(p.id),
    );
    final selecting = _selected.isNotEmpty;
    final items = page.items;
    return [
      if (grid)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              // Place du nom et du prix sous la photo, police comprise.
              childAspectRatio:
                  0.78 / MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final p = items[i];
              return BizReveal(
                key: ValueKey('tile-${p.id}'),
                index: i % 10,
                child: ProductTile(
                  product: p,
                  onOpen: () => open(p),
                  selecting: selecting,
                  selected: _selected.containsKey(p.id),
                  onSelect: () => _toggle(p),
                ),
              );
            },
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final p = items[i];
              return Padding(
                key: ValueKey(p.id),
                padding: const EdgeInsets.only(bottom: 10),
                child: BizReveal(
                  index: i % 10,
                  child: ProductRow(
                    product: p,
                    categoryName: category(p.categoryId),
                    onOpen: () => open(p),
                    onStock: () => actions.adjustStock(context, p),
                    onWithdraw: () => actions.withdraw(context, p),
                    onRestore: () => actions.restore(p),
                    selecting: selecting,
                    selected: _selected.containsKey(p.id),
                    onSelect: () => _toggle(p),
                  ),
                ),
              );
            },
          ),
        ),
      if (page.loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (page.loadMoreFailed)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: TextButton(
                onPressed: () =>
                    ref.read(catalogListProvider(filter).notifier).loadMore(),
                child: const Text('Afficher la suite'),
              ),
            ),
          ),
        ),
    ];
  }
}

/// Champ de recherche arrondi, croix pour effacer.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: 'Rechercher un produit',
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      prefixIcon: const Icon(Icons.search_rounded, color: Biz.muted),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Effacer la recherche',
              onPressed: onClear,
              icon: const Icon(Icons.cancel_rounded, color: Biz.muted),
            ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Biz.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Biz.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Biz.navy, width: 1.6),
      ),
    ),
  );
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Ajouter un produit',
    child: Semantics(
      container: true,
      button: true,
      label: 'Ajouter un produit',
      excludeSemantics: true,
      onTap: onTap,
      child: BizPressable(
        onTap: onTap,
        scale: 0.88,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Biz.navy,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Biz.navy.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white),
        ),
      ),
    ),
  );
}

class _ShopAvatar extends StatelessWidget {
  const _ShopAvatar({required this.shop});
  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final initials = shop.name.trim().isEmpty
        ? '?'
        : shop.name
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((w) => w[0].toUpperCase())
              .join();
    return ExcludeSemantics(
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Biz.navy2, Biz.navy]),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: shop.logoUrl == null
            ? Text(
                initials,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              )
            : Image.network(
                shop.logoUrl!,
                fit: BoxFit.cover,
                width: 48,
                height: 48,
                errorBuilder: (_, _, _) =>
                    Text(initials, style: const TextStyle(color: Colors.white)),
              ),
      ),
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) => const BizCard(
    padding: EdgeInsets.all(12),
    child: Row(
      children: [
        BizSkeleton(width: 72, height: 72, radius: 16),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BizSkeleton(width: 70, height: 16),
              SizedBox(height: 8),
              BizSkeleton(height: 14),
              SizedBox(height: 8),
              BizSkeleton(width: 90, height: 18),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.busy,
    required this.activate,
    required this.onAll,
    required this.onClose,
    required this.onApply,
  });
  final int count;
  final bool busy, activate;
  final VoidCallback onAll, onClose, onApply;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
      decoration: BoxDecoration(
        color: Biz.navy,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x400E2E54),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Quitter la sélection',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count <= 1 ? '$count sélectionné' : '$count sélectionnés',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                GestureDetector(
                  onTap: onAll,
                  child: Text(
                    'Tout sélectionner',
                    style: t.labelMedium?.copyWith(
                      color: Colors.white70,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: BizButton(
              height: 46,
              busy: busy,
              color: activate ? Biz.green : Biz.red,
              icon: activate ? Icons.play_arrow_rounded : Icons.pause_rounded,
              label: activate ? 'Mettre en vente' : 'Retirer',
              onPressed: count == 0 ? null : onApply,
            ),
          ),
        ],
      ),
    );
  }
}

/// Choix d'une catégorie dans une feuille, avec recherche. Renvoie l'id
/// choisi, `''` pour « Toutes » ([allowAll]) ; `null` : fermée.
Future<String?> showCategorySheet(
  BuildContext context, {
  required List<ProductCategory> categories,
  String? selected,
  bool allowAll = false,
}) => showBizSheet<String>(
  context,
  title: 'Catégorie',
  expand: categories.length > 8,
  builder: (context) =>
      _CategoryPicker(all: categories, selected: selected, allowAll: allowAll),
);

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({
    required this.all,
    required this.selected,
    required this.allowAll,
  });
  final List<ProductCategory> all;
  final String? selected;
  final bool allowAll;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  var _q = '';

  String _fold(String s) => s.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final items = widget.all
        .where(
          (c) =>
              _q.isEmpty ||
              _fold(categoryLabel(c, widget.all)).contains(_fold(_q)),
        )
        .toList();
    Widget tile(String id, String label, {String? sub}) {
      final on = (widget.selected ?? '') == id;
      return ListTile(
        onTap: () => Navigator.pop(context, id),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(
          label,
          style: t.titleSmall?.copyWith(
            fontWeight: on ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        subtitle: sub == null ? null : Text(sub),
        trailing: AnimatedSwitcher(
          duration: Biz.fast,
          child: on
              ? const Icon(
                  Icons.check_circle_rounded,
                  color: Biz.blue,
                  key: ValueKey('on'),
                )
              : const Icon(
                  Icons.circle_outlined,
                  color: Biz.line,
                  key: ValueKey('off'),
                ),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (widget.all.length > 8)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: InputDecoration(
                hintText: 'Chercher une catégorie',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        if (widget.allowAll && _q.isEmpty) tile('', 'Toutes les catégories'),
        for (final c in items) tile(c.id, categoryLabel(c, widget.all)),
      ],
    );
  }
}
