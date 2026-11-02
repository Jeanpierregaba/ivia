import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/buyer_area.dart';
import '../../app/catalog_data.dart';
import '../../app/router.dart';
import '../cart/cart_button.dart';
import '../search/product_grid.dart';
import '../search/search_state.dart';
import 'area_sheet.dart';
import 'home_providers.dart';
import 'shop_card.dart';

/// Accueil : zone, salutation, recherche, catégories, boutiques autour de
/// l'acheteur et nouveautés.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Sans quartier choisi, la position est demandée à l'ouverture.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(buyerAreaProvider.notifier).ensure();
    });
  }

  /// Onglet Recherche, préparé depuis l'accueil.
  void _search({
    String? categoryId,
    SearchTab tab = SearchTab.products,
    SearchSort sort = SearchSort.relevance,
    bool focus = false,
  }) {
    ref
        .read(searchFiltersProvider.notifier)
        .startFromHome(categoryId: categoryId, tab: tab, sort: sort);
    if (focus) ref.read(searchFocusRequestProvider.notifier).request();
    context.go(Routes.search);
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(homeShopsProvider)
      ..invalidate(homeProductsProvider)
      ..invalidate(categoriesProvider)
      ..invalidate(neighborhoodsProvider);
    try {
      await Future.wait([
        ref.read(homeShopsProvider.future),
        ref.read(homeProductsProvider.future),
      ]);
    } on Exception {
      // Les sections déjà affichées restent : un message dit qu'elles ne
      // sont pas à jour (au premier chargement, la section montre l'erreur).
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Accueil non actualisé. Vérifiez votre connexion.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    final area = ref.watch(buyerAreaProvider);
    final firstName = switch (ref.watch(authControllerProvider)) {
      AuthSignedIn(:final user) => user.firstName,
      _ => '',
    };
    final categories = ref.watch(categoriesProvider).value ?? const [];
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          // Tirer pour actualiser, même quand l'accueil est court.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: IviaSpacing.lg),
          children: [
            _pad(
              Row(
                children: [
                  Expanded(child: _AreaButton(area: area)),
                  const SizedBox(width: IviaSpacing.sm),
                  const CartButton(),
                ],
              ),
            ),
            const SizedBox(height: IviaSpacing.xl),
            _pad(
              Semantics(
                header: true,
                child: Text.rich(
                  TextSpan(
                    text: firstName.isEmpty
                        ? 'Bonjour,\n'
                        : 'Bonjour $firstName,\n',
                    children: [
                      TextSpan(
                        text: 'que cherchez-vous ?',
                        style: TextStyle(color: brand.highlight),
                      ),
                    ],
                  ),
                  style: textTheme.headlineLarge,
                ),
              ),
            ),
            const SizedBox(height: IviaSpacing.xl),
            _pad(_SearchEntry(onTap: () => _search(focus: true))),
            if (area case AreaUnknown(:final failure?)) ...[
              const SizedBox(height: IviaSpacing.lg),
              _pad(_AreaMissing(failure: failure)),
            ],
            if (area is AreaLocating)
              const Padding(
                padding: EdgeInsets.all(IviaSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (categories.any((c) => c.parentId == null)) ...[
                const SizedBox(height: IviaSpacing.lg),
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: IviaSpacing.screen,
                    ),
                    children: [
                      IviaChip(
                        label: 'Tout',
                        selected: true,
                        onTap: () => _search(),
                      ),
                      for (final c in categories.where(
                        (c) => c.parentId == null,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(left: IviaSpacing.sm),
                          child: IviaChip(
                            label: c.name,
                            onTap: () => _search(categoryId: c.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: IviaSpacing.xxl),
              _pad(
                _SectionTitle(
                  title: 'Boutiques autour de vous',
                  onSeeAll: () => _search(
                    tab: SearchTab.shops,
                    sort: area.point == null
                        ? SearchSort.relevance
                        : SearchSort.distance,
                  ),
                ),
              ),
              const SizedBox(height: IviaSpacing.md),
              _ShopsSection(),
              const SizedBox(height: IviaSpacing.xxl),
              _pad(
                _SectionTitle(
                  title: 'Nouveautés autour de vous',
                  onSeeAll: () => _search(),
                ),
              ),
              const SizedBox(height: IviaSpacing.md),
              _pad(const _ProductsSection()),
            ],
            const SizedBox(height: IviaSpacing.xxl),
          ],
        ),
      ),
    );
  }

  static Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
    child: child,
  );
}

/// « Près de · Tokoin ▾ » : ouvre le choix de la zone.
class _AreaButton extends StatelessWidget {
  const _AreaButton({required this.area});

  final BuyerArea area;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: 'Zone de recherche : ${area.label}. Changer',
        excludeSemantics: true,
        onTap: () => showAreaSheet(context),
        child: InkWell(
          borderRadius: BorderRadius.circular(IviaRadius.large),
          onTap: () => showAreaSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: IviaSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: IviaColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.place, color: brand.accent),
                ),
                const SizedBox(width: IviaSpacing.md),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Près de', style: textTheme.bodySmall),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              area.label,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Champ factice : un appui ouvre l'onglet Recherche, champ actif.
class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Rechercher un produit ou une boutique',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: IviaColors.surface,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: IviaSpacing.xl,
              vertical: IviaSpacing.lg,
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: IviaColors.textMuted),
                const SizedBox(width: IviaSpacing.md),
                Expanded(
                  child: Text(
                    'Produit ou boutique…',
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: IviaColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Position manquante : raison et choix du quartier.
class _AreaMissing extends StatelessWidget {
  const _AreaMissing({required this.failure});

  final LocationFailure failure;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(IviaSpacing.lg),
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              locationFailureMessage(failure),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: IviaSpacing.sm),
          Wrap(
            spacing: IviaSpacing.sm,
            children: [
              TextButton(
                onPressed: () => showAreaSheet(context),
                child: const Text('Choisir mon quartier'),
              ),
              // Refus définitif : seule l'app Réglages peut le lever.
              if (failure == LocationFailure.deniedForever)
                Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () =>
                        ref.read(locationServiceProvider).openSettings(),
                    child: const Text('Ouvrir les réglages'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.onSeeAll});

  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    // Wrap : « Voir tout » passe sous le titre avec une police agrandie.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        TextButton(
          onPressed: onSeeAll,
          child: Text('Voir tout', semanticsLabel: 'Voir tout : $title'),
        ),
      ],
    );
  }
}

class _ShopsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shops = ref.watch(homeShopsProvider);
    return switch (shops) {
      AsyncValue(value: final items?) when items.isEmpty =>
        const _SectionMessage('Aucune boutique autour de vous pour l’instant.'),
      AsyncValue(value: final items?) => SizedBox(
        height: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 280 : 210,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: IviaSpacing.md),
          itemBuilder: (context, i) {
            final s = items[i];
            return SizedBox(
              width: 220,
              child: ShopCard(
                name: s.name,
                logoUrl: s.logoUrl,
                place: neighborhoodName(ref, s.neighborhoodId),
                distance: switch (s.distanceM) {
                  final m? => formatDistance(m),
                  null => null,
                },
                acceptingOrders: s.acceptingOrders,
                onTap: () => context.push(Routes.shop(s.id)),
              ),
            );
          },
        ),
      ),
      AsyncError(:final error) => _SectionError(
        error: error,
        onRetry: () => ref.invalidate(homeShopsProvider),
      ),
      _ => const _SectionLoading(),
    };
  }
}

class _ProductsSection extends ConsumerWidget {
  const _ProductsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(homeProductsProvider);
    return switch (products) {
      AsyncValue(value: final items?) when items.isEmpty =>
        const _SectionMessage('Aucun produit autour de vous pour l’instant.'),
      AsyncValue(value: final items?) => ProductGrid(items: items),
      AsyncError(:final error) => _SectionError(
        error: error,
        onRetry: () => ref.invalidate(homeProductsProvider),
      ),
      _ => const _SectionLoading(),
    };
  }
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: IviaSpacing.screen,
      vertical: IviaSpacing.md,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(color: IviaColors.textSecondary),
    ),
  );
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is ApiException && !(error as ApiException).isNetwork
        ? (error as ApiException).message
        : 'Impossible de charger cette section. Vérifiez votre connexion.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(IviaSpacing.xl),
    child: Center(child: CircularProgressIndicator()),
  );
}
