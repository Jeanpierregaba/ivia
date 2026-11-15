import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../search/product_grid.dart';
import 'promo_actions.dart';
import 'promo_state.dart';

/// Carrousel d'accueil : visuels « Accueil — carrousel » dans un ordre tiré au
/// hasard à chaque ouverture, qui défilent seuls toutes les 5 s.
class PromoHeroCarousel extends ConsumerStatefulWidget {
  const PromoHeroCarousel({super.key});

  static const interval = Duration(seconds: 5);

  @override
  ConsumerState<PromoHeroCarousel> createState() => _PromoHeroCarouselState();
}

class _PromoHeroCarouselState extends ConsumerState<PromoHeroCarousel> {
  final _controller = PageController(viewportFraction: 0.92);
  Timer? _timer;
  List<PromoVisual>? _order;
  final _seen = <String>{};
  var _page = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _start(int count) {
    _timer?.cancel();
    if (count < 2) return;
    _timer = Timer.periodic(PromoHeroCarousel.interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % count;
      unawaited(
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _shown(PromoVisual v) {
    // Un affichage par visuel et par ouverture de l'accueil.
    if (_seen.add(v.id)) {
      ref
          .read(promoTrackerProvider)
          .track('impression', visual: v, placement: PromoPlacement.homeHero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(promoFeedProvider).value;
    if (feed == null ||
        !feed.settings.enabled ||
        !feed.settings.bannersEnabled) {
      return const SizedBox.shrink();
    }
    final visuals = feed.at(PromoPlacement.homeHero);
    if (visuals.isEmpty) return const SizedBox.shrink();
    if (_order == null || _order!.length != visuals.length) {
      _order = List.of(visuals)..shuffle(ref.read(promoRandomProvider));
      _start(_order!.length);
    }
    final order = _order!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shown(order[_page % order.length]);
    });
    return Column(
      children: [
        const SizedBox(height: IviaSpacing.lg),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: PageView.builder(
            controller: _controller,
            itemCount: order.length,
            onPageChanged: (i) {
              setState(() => _page = i);
              _shown(order[i]);
            },
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.xs),
              child: PromoBanner(
                visual: order[i],
                settings: feed.settings,
                placement: PromoPlacement.homeHero,
              ),
            ),
          ),
        ),
        if (order.length > 1) ...[
          const SizedBox(height: IviaSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < order.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? IviaColors.primary : IviaColors.border,
                    borderRadius: BorderRadius.circular(IviaRadius.pill),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Bannière : image plein cadre, titre et bouton ; un appui ouvre le produit
/// (ou le site officiel s'il n'y a pas de produit).
class PromoBanner extends ConsumerWidget {
  const PromoBanner({
    super.key,
    required this.visual,
    required this.settings,
    required this.placement,
  });

  final PromoVisual visual;
  final PromoSettings settings;
  final PromoPlacement placement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final product = visual.product;
    final site = promoSiteOf(visual, settings);
    void open() {
      if (product != null) {
        openPromoProduct(
          context,
          ref,
          product.id,
          visual: visual,
          placement: placement,
        );
      } else if (site.isNotEmpty) {
        unawaited(
          visitPromoSite(
            context,
            ref,
            site,
            visual: visual,
            placement: placement,
          ),
        );
      }
    }

    return Semantics(
      button: true,
      label: 'Publicité : ${visual.title}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(IviaRadius.large),
        child: Material(
          color: IviaColors.tertiary,
          child: InkWell(
            onTap: open,
            child: Stack(
              fit: StackFit.expand,
              children: [
                IviaNetworkImage(url: visual.imageUrl, radius: 0),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC0E2E54)],
                      stops: [0.45, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: IviaSpacing.lg,
                  right: IviaSpacing.lg,
                  bottom: IviaSpacing.md,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          visual.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (product != null) ...[
                        const SizedBox(width: IviaSpacing.sm),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(
                              horizontal: IviaSpacing.lg,
                            ),
                          ),
                          onPressed: () => orderFromPromo(
                            context,
                            ref,
                            product,
                            visual: visual,
                            placement: placement,
                          ),
                          child: Text(
                            visual.ctaLabel.isEmpty
                                ? 'Commander'
                                : visual.ctaLabel,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  top: IviaSpacing.sm,
                  left: IviaSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: IviaSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(IviaRadius.pill),
                    ),
                    child: Text(
                      'Publicité',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
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

/// « Produits vedettes » : produits mis en avant (IVI d'abord), en cartes.
class FeaturedProductsStrip extends ConsumerWidget {
  const FeaturedProductsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(promoFeedProvider).value;
    if (feed == null ||
        !feed.settings.enabled ||
        !feed.settings.bannersEnabled) {
      return const SizedBox.shrink();
    }
    final hits = featuredHits(feed);
    if (hits.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
          child: Row(
            children: [
              const Icon(
                Icons.local_fire_department,
                color: IviaColors.primary,
              ),
              const SizedBox(width: IviaSpacing.xs),
              Semantics(
                header: true,
                child: Text(
                  'Produits vedettes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: IviaSpacing.md),
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 330 : 270,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
            itemCount: hits.length,
            separatorBuilder: (_, _) => const SizedBox(width: IviaSpacing.md),
            itemBuilder: (context, i) => SizedBox(
              width: 180,
              child: ProductHitCard(hit: hits[i], fromPromo: true),
            ),
          ),
        ),
        const SizedBox(height: IviaSpacing.xxl),
      ],
    );
  }
}

/// Bannière glissée dans une liste (accueil, recherche, boutique) : un visuel
/// de l'emplacement tiré au hasard à chaque affichage de l'écran (à défaut,
/// un visuel du carrousel), pour que la marque revienne pendant la
/// navigation.
class PromoInlineBanner extends ConsumerStatefulWidget {
  const PromoInlineBanner({super.key, required this.placement});

  final PromoPlacement placement;

  @override
  ConsumerState<PromoInlineBanner> createState() => _PromoInlineBannerState();
}

class _PromoInlineBannerState extends ConsumerState<PromoInlineBanner> {
  PromoVisual? _visual;

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(promoFeedProvider).value;
    if (feed == null ||
        !feed.settings.enabled ||
        !feed.settings.bannersEnabled) {
      return const SizedBox.shrink();
    }
    if (_visual == null) {
      var pool = feed.at(widget.placement);
      if (pool.isEmpty) pool = feed.at(PromoPlacement.homeHero);
      _visual = pickVisual(
        pool,
        PromoRotation.random,
        ref.read(promoRandomProvider),
      );
      if (_visual case final v?) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref
                .read(promoTrackerProvider)
                .track('impression', visual: v, placement: widget.placement);
          }
        });
      }
    }
    final v = _visual;
    if (v == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IviaSpacing.screen,
        vertical: IviaSpacing.lg,
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: PromoBanner(
          visual: v,
          settings: feed.settings,
          placement: widget.placement,
        ),
      ),
    );
  }
}
