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
import '../notifications/notification_bell.dart';
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
                  const NotificationBell(),
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
                padding: EdgeInsets.all(IviaSpacing.screen),
                child: IviaListSkeleton(rows: 3),
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

/// Position manquante : invitation à activer la localisation, ou à choisir
/// son quartier, sans jamais parler de saisie à la main.
class _AreaMissing extends ConsumerWidget {
  const _AreaMissing({required this.failure});

  final LocationFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final brand = IviaAppBrand.of(context);
    // Refus définitif ou localisation coupée : seuls les réglages la rétablissent.
    final settings =
        failure == LocationFailure.deniedForever ||
        failure == LocationFailure.serviceDisabled;
    return Container(
      padding: const EdgeInsets.all(IviaSpacing.lg),
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: brand.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.near_me_outlined, color: brand.accent),
          ),
          const SizedBox(width: IviaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voir ce qui est près de vous',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: IviaSpacing.xs),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    locationFailureMessage(failure),
                    style: t.bodyMedium?.copyWith(
                      color: IviaColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: IviaSpacing.md),
                Wrap(
                  spacing: IviaSpacing.sm,
                  runSpacing: IviaSpacing.sm,
                  children: [
                    FilledButton.tonal(
                      onPressed: () async {
                        if (settings) {
                          await ref
                              .read(locationServiceProvider)
                              .openSettings();
                          return;
                        }
                        if (await askForLocation(context, ref)) {
                          await ref.read(buyerAreaProvider.notifier).locate();
                        }
                      },
                      child: Text(
                        settings
                            ? 'Ouvrir les réglages'
                            : 'Activer la localisation',
                      ),
                    ),
                    TextButton(
                      onPressed: () => showAreaSheet(context),
                      child: const Text('Choisir mon quartier'),
                    ),
                  ],
                ),
              ],
            ),
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
    padding: EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
    child: IviaGridSkeleton(count: 2),
  );
}

typedef _Service = (IconData, String, Color, Color, VoidCallback);

/// Services de l'accueil (maquette A01) ; ceux sans module affichent
/// « Bientôt disponible ». Sept tuiles, puis « Plus » qui ouvre la liste
/// complète : d'autres services viendront.
class _ServicesGrid extends StatelessWidget {
  const _ServicesGrid({
    required this.onPharmacy,
    required this.onShops,
    required this.onProducts,
  });

  final VoidCallback onPharmacy, onShops, onProducts;

  static const _visible = 7;

  List<_Service> _services(BuildContext context) {
    void soon(String name) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('$name : bientôt disponible sur ivia.')),
      );
    const red = IviaColors.primarySoft, blue = IviaColors.secondarySoft;
    const navy = IviaColors.berkeleyBlue;
    return [
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
  }

  @override
  Widget build(BuildContext context) {
    final all = _services(context);
    final shown = all.take(_visible).toList();
    return _ServiceTiles(
      tiles: [
        for (final (i, s) in shown.indexed) _ServiceTile(service: s, index: i),
        _ServiceTile(
          index: shown.length,
          service: (
            Icons.grid_view_rounded,
            'Plus',
            IviaColors.backgroundAlt,
            IviaColors.textSecondary,
            () => _showAllServices(context, all),
          ),
        ),
      ],
    );
  }
}

/// Grille des tuiles : 4 par ligne, plus sur un grand écran.
class _ServiceTiles extends StatelessWidget {
  const _ServiceTiles({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 600 ? 8 : 4;
      final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: IviaSpacing.sm,
        crossAxisSpacing: IviaSpacing.sm,
        childAspectRatio: large ? 0.6 : 0.82,
        children: tiles,
      );
    },
  );
}

/// Tuile d'un service : pastille d'icône et libellé centrés, qui s'enfonce
/// sous le doigt.
class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.index});

  final _Service service;
  final int index;

  @override
  Widget build(BuildContext context) {
    final (icon, label, bg, fg, onTap) = service;
    return IviaReveal(
      index: index,
      child: IviaPressable(
        child: Material(
          color: IviaColors.surface,
          borderRadius: BorderRadius.circular(IviaRadius.large),
          child: InkWell(
            borderRadius: BorderRadius.circular(IviaRadius.large),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: IviaSpacing.xs,
                vertical: IviaSpacing.sm,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: fg),
                  ),
                  const SizedBox(height: IviaSpacing.sm),
                  Text(
                    label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// « Tous les services » : la liste complète, dans une feuille.
Future<void> _showAllServices(BuildContext context, List<_Service> all) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: IviaColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            IviaSpacing.screen,
            0,
            IviaSpacing.screen,
            IviaSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tous les services',
                style: Theme.of(sheet).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: IviaSpacing.lg),
              _ServiceTiles(
                tiles: [
                  for (final (i, (icon, label, bg, fg, onTap)) in all.indexed)
                    _ServiceTile(
                      index: i,
                      service: (
                        icon,
                        label,
                        bg,
                        fg,
                        () {
                          Navigator.of(sheet).pop();
                          onTap();
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

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
