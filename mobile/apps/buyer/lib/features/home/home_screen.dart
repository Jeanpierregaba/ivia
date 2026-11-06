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
import '../promo/promo_state.dart';
import '../promo/promo_widgets.dart';
import '../search/product_grid.dart';
import '../search/search_sheets.dart';
import '../search/search_state.dart';
import '../pharmacy/pharmacy_hub_screen.dart';
import '../pharmacy/pharmacy_state.dart';
import '../services/services_screens.dart';
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

  /// Filtres : catégorie puis tri, appliqués dans l'onglet Recherche.
  Future<void> _filters(List<ProductCategory> categories) async {
    final cat = await showCategorySheet(context, categories, null);
    if (cat == null || !mounted) return;
    final sort = await showSortSheet(
      context,
      current: SearchSort.relevance,
      withDistance: ref.read(buyerAreaProvider).point != null,
      products: true,
    );
    _search(categoryId: cat.value, sort: sort?.value ?? SearchSort.relevance);
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(homeShopsProvider)
      ..invalidate(homeProductsProvider)
      ..invalidate(categoriesProvider)
      ..invalidate(neighborhoodsProvider)
      ..invalidate(promoFeedProvider);
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
          // Sections préparées avant d'être visibles (boutiques sous les services).
          // ignore: deprecated_member_use
          cacheExtent: 1500,
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
            if (firstName.isNotEmpty)
              _pad(
                Text(
                  'Bonjour $firstName',
                  style: textTheme.bodyLarge?.copyWith(
                    color: IviaColors.textSecondary,
                  ),
                ),
              ),
            // Maquette A01.
            _pad(
              Semantics(
                header: true,
                child: Text.rich(
                  TextSpan(
                    text: "Tout ce qu'il vous faut,\n",
                    children: [
                      TextSpan(
                        text: 'tout près de vous.',
                        style: TextStyle(color: brand.highlight),
                      ),
                    ],
                  ),
                  style: textTheme.headlineLarge,
                ),
              ),
            ),
            const SizedBox(height: IviaSpacing.xl),
            _pad(
              Row(
                children: [
                  Expanded(
                    child: _SearchEntry(onTap: () => _search(focus: true)),
                  ),
                  const SizedBox(width: IviaSpacing.md),
                  _RoundIcon(
                    icon: Icons.tune,
                    label: 'Filtres',
                    onTap: () => _filters(categories),
                  ),
                ],
              ),
            ),
            const SizedBox(height: IviaSpacing.lg),
            _pad(
              _ServicesGrid(
                onPharmacy: () => context.push(Routes.pharmacy),
                onShops: () => _search(tab: SearchTab.shops),
                onProducts: () => _search(),
              ),
            ),
            const PromoHeroCarousel(),
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
              const FeaturedProductsStrip(),
              _pad(
                _SectionTitle(
                  title: 'Boutiques près de vous',
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
              const _OnDutySection(),
              const _RestaurantsSection(),
              const _PropertiesSection(),
              const PromoInlineBanner(placement: PromoPlacement.homeFeed),
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
                      Text('Livrer à', style: textTheme.bodySmall),
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
                    'Pharmacie, plat, taxi…',
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
      AsyncValue(value: final items?) => ProductGrid(
        items: withFeatured(ref, items),
      ),
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

/// Les 8 services de la maquette A01 ; ceux sans module affichent
/// « Bientôt disponible ».
class _ServicesGrid extends StatelessWidget {
  const _ServicesGrid({
    required this.onPharmacy,
    required this.onShops,
    required this.onProducts,
  });

  final VoidCallback onPharmacy, onShops, onProducts;

  @override
  Widget build(BuildContext context) {
    void soon(String name) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('$name : bientôt disponible sur ivia.')),
      );
    const red = Color(0xFFFDE8EA), blue = Color(0xFFE5EEF8);
    const navy = Color(0xFF0E2E54);
    final services = <(IconData, String, Color, Color, VoidCallback)>[
      (Icons.add_box_outlined, 'Pharmacie', blue, navy, onPharmacy),
      (
        Icons.shopping_basket_outlined,
        'Alimentation',
        red,
        IviaColors.primary,
        onShops,
      ),
      (
        Icons.restaurant,
        'Restaurant',
        red,
        IviaColors.primary,
        () => context.push(Routes.restaurants),
      ),
      (
        Icons.directions_car_outlined,
        'Taxi',
        blue,
        navy,
        () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => const RouteScreen(
              title: 'Mon trajet',
              withPrice: true,
              profile: 'car',
            ),
          ),
        ),
      ),
      (
        Icons.storefront_outlined,
        'E-Bazar',
        red,
        IviaColors.primary,
        onProducts,
      ),
      (
        Icons.article_outlined,
        'Immobilier',
        blue,
        navy,
        () => context.push(Routes.properties),
      ),
      (
        Icons.room_service_outlined,
        'Conciergerie',
        blue,
        navy,
        () => soon('Conciergerie'),
      ),
      (
        Icons.pedal_bike,
        'Coursier',
        red,
        IviaColors.primary,
        () => soon('Coursier'),
      ),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: IviaSpacing.sm,
      crossAxisSpacing: IviaSpacing.sm,
      childAspectRatio: MediaQuery.textScalerOf(context).scale(1) > 1.3
          ? 0.6
          : 0.85,
      children: [
        for (final (icon, label, bg, fg, onTap) in services)
          Material(
            color: IviaColors.surface,
            borderRadius: BorderRadius.circular(IviaRadius.large),
            child: InkWell(
              borderRadius: BorderRadius.circular(IviaRadius.large),
              onTap: onTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: fg),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// « Pharmacies de garde » (A01) : les 3 plus proches.
class _OnDutySection extends ConsumerWidget {
  const _OnDutySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(onDutyPharmaciesProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IviaSpacing.screen,
        IviaSpacing.xxl,
        IviaSpacing.screen,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: 'Pharmacies de garde',
            onSeeAll: () => context.push(Routes.pharmacy),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.md),
            decoration: BoxDecoration(
              color: IviaColors.surface,
              borderRadius: BorderRadius.circular(IviaRadius.large),
            ),
            child: Column(
              children: [for (final p in items) OnDutyTile(pharmacy: p)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton rond blanc des en-têtes (filtres).
class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: IviaColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox.square(
          dimension: 60,
          child: Icon(Icons.tune, color: Color(0xFF111C33)),
        ),
      ),
    ),
  );
}

/// « Restaurants autour de vous » (A01).
class _RestaurantsSection extends ConsumerWidget {
  const _RestaurantsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(restaurantsProvider).value ?? const <ShopHit>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: IviaSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
            child: _SectionTitle(
              title: 'Restaurants autour de vous',
              onSeeAll: () => context.push(Routes.restaurants),
            ),
          ),
          const SizedBox(height: IviaSpacing.md),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: IviaSpacing.screen,
              ),
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
                    distance: s.distanceM == null
                        ? null
                        : formatDistance(s.distanceM!),
                    acceptingOrders: s.acceptingOrders,
                    onTap: () => context.push(Routes.shop(s.id)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// « Biens immobiliers » (A01).
class _PropertiesSection extends ConsumerWidget {
  const _PropertiesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(propertiesProvider(null)).value ?? const <Property>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: IviaSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
            child: _SectionTitle(
              title: 'Biens immobiliers',
              onSeeAll: () => context.push(Routes.properties),
            ),
          ),
          const SizedBox(height: IviaSpacing.md),
          SizedBox(
            height: 300,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: IviaSpacing.screen,
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: IviaSpacing.md),
              itemBuilder: (context, i) =>
                  PropertyCard(property: items[i], width: 270),
            ),
          ),
        ],
      ),
    );
  }
}
