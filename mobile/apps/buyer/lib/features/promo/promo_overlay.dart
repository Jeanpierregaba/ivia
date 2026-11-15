import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import 'promo_actions.dart';
import 'promo_state.dart';

/// Diffuse fenêtres et interstitiels pendant la navigation, selon les
/// réglages de l'admin : premier affichage après le délai, intervalle
/// minimal, plafond par session, rotation. Jamais deux à la fois, jamais
/// pendant le panier, la commande ou le paiement, toujours fermables.
class PromoHost extends ConsumerStatefulWidget {
  const PromoHost({super.key, required this.child});

  final Widget child;

  /// Pas de l'horloge : le temps écoulé est compté en pas (testable).
  static const tick = Duration(seconds: 5);

  @override
  ConsumerState<PromoHost> createState() => _PromoHostState();
}

class _PromoHostState extends ConsumerState<PromoHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  var _elapsed = Duration.zero;
  Duration? _lastShownAt;
  var _shown = 0;
  var _showing = false;
  var _welcomeDone = false;
  String? _lastId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(PromoHost.tick, (_) => _onTick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Statistiques envoyées quand l'app passe en arrière-plan.
    if (state == AppLifecycleState.paused) {
      unawaited(ref.read(promoTrackerProvider).flush());
    }
  }

  /// Écrans où aucune publicité ne s'ouvre (achat en cours).
  static bool _quiet(String location) =>
      location.startsWith(Routes.cart) ||
      location.startsWith(Routes.checkout) ||
      location.contains('/pay') ||
      location.contains('/payments/');

  void _onTick() {
    _elapsed += PromoHost.tick;
    if (!mounted || _showing) return;
    final feed = ref.read(promoFeedProvider).value;
    if (feed == null || !feed.settings.enabled) return;
    final s = feed.settings;
    if (_shown >= s.maxPerSession) return;
    final location = ref
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
    if (_quiet(location)) return;

    // Bienvenue : une fois par session, dès le premier pas.
    if (!_welcomeDone && s.interstitialEnabled) {
      _welcomeDone = true;
      final welcome = feed.at(PromoPlacement.splash);
      final v = pickVisual(welcome, s.rotation, ref.read(promoRandomProvider));
      if (v != null) {
        unawaited(_show(v, PromoPlacement.splash, s, fullScreen: true));
        return;
      }
    }
    if (_elapsed < s.firstDelay) return;
    if (_lastShownAt case final last? when _elapsed - last < s.minInterval) {
      return;
    }
    final candidates = [
      if (s.modalEnabled)
        for (final v in feed.at(PromoPlacement.modal))
          (v, PromoPlacement.modal),
      if (s.interstitialEnabled)
        for (final v in feed.at(PromoPlacement.interstitial))
          (v, PromoPlacement.interstitial),
    ];
    final v = pickVisual(
      [for (final c in candidates) c.$1],
      s.rotation,
      ref.read(promoRandomProvider),
      lastId: _lastId,
    );
    if (v == null) return;
    final placement = candidates.firstWhere((c) => c.$1.id == v.id).$2;
    unawaited(
      _show(
        v,
        placement,
        s,
        fullScreen: placement == PromoPlacement.interstitial,
      ),
    );
  }

  Future<void> _show(
    PromoVisual v,
    PromoPlacement placement,
    PromoSettings settings, {
    required bool fullScreen,
  }) async {
    final navigator = ref.read(routerProvider).routerDelegate.navigatorKey;
    final context = navigator.currentContext;
    if (context == null || !context.mounted) return;
    _showing = true;
    _shown++;
    _lastId = v.id;
    final tracker = ref.read(promoTrackerProvider)
      ..track('impression', visual: v, placement: placement);
    final closed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer la publicité',
      barrierColor: Colors.black.withValues(alpha: fullScreen ? 0.85 : 0.55),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
      pageBuilder: (context, _, _) => PromoAdView(
        visual: v,
        settings: settings,
        placement: placement,
        fullScreen: fullScreen,
      ),
    );
    // Fermée sans choisir de bouton (croix, retour, appui à côté).
    if (closed != false) {
      tracker.track('dismiss', visual: v, placement: placement);
    }
    _lastShownAt = _elapsed;
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Contenu d'une publicité : grande image, nom, argumentaire, prix (promotion
/// comprise), badge, caractéristiques et boutons. Le dialogue rend `false`
/// quand un bouton a été choisi (pas une fermeture).
class PromoAdView extends ConsumerWidget {
  const PromoAdView({
    super.key,
    required this.visual,
    required this.settings,
    required this.placement,
    this.fullScreen = false,
  });

  final PromoVisual visual;
  final PromoSettings settings;
  final PromoPlacement placement;
  final bool fullScreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final product = visual.product;
    final site = promoSiteOf(visual, settings);
    // Navigateur racine : les écrans s'ouvrent sous la publicité fermée.
    final router = GoRouter.of(context);
    final rootContext = router.routerDelegate.navigatorKey.currentContext!;

    void choose(void Function() action) {
      Navigator.of(context).pop(false);
      action();
    }

    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (product?.badges.firstOrNull case final badge?)
          Align(
            alignment: Alignment.centerLeft,
            child: IviaPromoBadge(label: badge.label),
          ),
        const SizedBox(height: IviaSpacing.sm),
        Text(
          visual.title,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: fullScreen ? Colors.white : null,
          ),
        ),
        if (visual.subtitle.isNotEmpty)
          Text(
            visual.subtitle,
            style: textTheme.titleSmall?.copyWith(
              color: fullScreen ? Colors.white70 : IviaColors.textSecondary,
            ),
          ),
        if (visual.body.isNotEmpty) ...[
          const SizedBox(height: IviaSpacing.sm),
          Text(
            visual.body,
            style: textTheme.bodyMedium?.copyWith(
              color: fullScreen ? Colors.white : IviaColors.textSecondary,
            ),
          ),
        ],
        if (product != null) ...[
          const SizedBox(height: IviaSpacing.md),
          Wrap(
            spacing: IviaSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                formatXof(product.effectivePriceXof),
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: fullScreen ? Colors.white : IviaColors.primary,
                ),
              ),
              if (product.promoActive)
                Text(
                  formatXof(product.priceXof),
                  style: textTheme.bodyMedium?.copyWith(
                    decoration: TextDecoration.lineThrough,
                    color: fullScreen ? Colors.white60 : IviaColors.textMuted,
                  ),
                ),
            ],
          ),
          for (final f in product.features.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: fullScreen ? Colors.white : IviaColors.success,
                  ),
                  const SizedBox(width: IviaSpacing.xs),
                  Expanded(
                    child: Text(
                      f,
                      style: textTheme.bodySmall?.copyWith(
                        color: fullScreen ? Colors.white : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: IviaSpacing.lg),
        if (product != null) ...[
          FilledButton(
            onPressed: () => choose(
              () => orderFromPromo(
                rootContext,
                ref,
                product,
                visual: visual,
                placement: placement,
              ),
            ),
            child: Text(
              visual.ctaLabel.isEmpty
                  ? 'Commander maintenant'
                  : visual.ctaLabel,
            ),
          ),
          const SizedBox(height: IviaSpacing.sm),
          OutlinedButton(
            style: fullScreen
                ? OutlinedButton.styleFrom(
                    // Fond transparent : le thème met un fond blanc aux boutons
                    // à contour, qui masquait le texte blanc sur la photo.
                    backgroundColor: Colors.black26,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  )
                : null,
            onPressed: () => choose(
              () => openPromoProduct(
                rootContext,
                ref,
                product.id,
                visual: visual,
                placement: placement,
              ),
            ),
            child: const Text('Découvrir le produit'),
          ),
        ],
        if (site.isNotEmpty)
          TextButton.icon(
            style: fullScreen
                ? TextButton.styleFrom(foregroundColor: Colors.white)
                : null,
            onPressed: () => choose(
              () => unawaited(
                visitPromoSite(
                  rootContext,
                  ref,
                  site,
                  visual: visual,
                  placement: placement,
                ),
              ),
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Visiter le site officiel IVI'),
          ),
      ],
    );

    final close = Semantics(
      button: true,
      label: 'Fermer la publicité',
      child: Material(
        color: Colors.black.withValues(alpha: 0.5),
        shape: const CircleBorder(),
        child: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ),
    );

    if (fullScreen) {
      return Material(
        color: IviaColors.tertiary,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IviaNetworkImage(url: visual.imageUrl, radius: 0),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xF20E2E54)],
                  stops: [0.35, 0.75],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(IviaSpacing.sm),
                      child: close,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    flex: 3,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(IviaSpacing.xl),
                      child: details,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final size = MediaQuery.sizeOf(context);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: size.height * 0.9,
          ),
          child: Padding(
            padding: const EdgeInsets.all(IviaSpacing.lg),
            child: Material(
              color: IviaColors.surface,
              borderRadius: BorderRadius.circular(IviaRadius.large),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 4 / 3,
                          child: IviaNetworkImage(
                            url: visual.imageUrl,
                            radius: 0,
                          ),
                        ),
                        Positioned(
                          top: IviaSpacing.sm,
                          right: IviaSpacing.sm,
                          child: close,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(IviaSpacing.xl),
                      child: details,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
