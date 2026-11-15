import 'package:flutter/material.dart';

import 'brand.dart';
import 'components.dart';
import 'tokens.dart';

/// Une page de la présentation.
class OnboardingSlide {
  const OnboardingSlide({
    required this.illustration,
    required this.title,
    this.highlight,
    required this.body,
  });

  /// Illustration décorative, en général un [OnboardingArtboard].
  final Widget illustration;
  final String title;

  /// Partie du titre affichée en rouge ; doit figurer dans [title].
  final String? highlight;
  final String body;
}

/// Plan de dessin des illustrations (324 × 421 dp, celui des maquettes),
/// mis à l'échelle de la place disponible. Décoratif : ignoré par le lecteur
/// d'écran, et insensible à la taille de police (le texte utile est sous
/// l'illustration).
class OnboardingArtboard extends StatelessWidget {
  const OnboardingArtboard({super.key, required this.child});

  static const size = Size(324, 421);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: FittedBox(
          child: SizedBox.fromSize(size: size, child: child),
        ),
      ),
    );
  }
}

/// Illustration provisoire : pictogramme dans une carte de la couleur de
/// l'app, en attendant les maquettes.
class OnboardingIconIllustration extends StatelessWidget {
  const OnboardingIconIllustration({
    super.key,
    required this.brand,
    required this.icon,
  });

  final IviaAppBrand brand;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return OnboardingArtboard(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: brand.accent,
          borderRadius: BorderRadius.circular(IviaRadius.large),
        ),
        child: Center(
          child: Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 80, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Présentation du premier lancement : pages à faire défiler, « Passer »,
/// « Suivant » puis « Commencer ». Le bouton retour rond et le retour
/// Android reviennent à la page précédente ; sur la première page, le retour
/// Android quitte l'écran.
class IviaOnboarding extends StatefulWidget {
  const IviaOnboarding({
    super.key,
    required this.brand,
    required this.slides,
    required this.onDone,
    this.appName,
  }) : assert(slides.length > 0);

  final IviaAppBrand brand;
  final List<OnboardingSlide> slides;

  /// Nom affiché à côté du logo sur la première page (« Marchand »).
  final String? appName;

  /// Appelé par « Passer » et par « Commencer ».
  final VoidCallback onDone;

  /// Agrandissement maximal des titres : au-delà, un mot long (« Disponible »)
  /// serait coupé en deux sur un écran de 320 dp. Le texte courant, lui,
  /// suit la police du téléphone sans limite.
  static const titleMaxTextScale = 1.5;

  @override
  State<IviaOnboarding> createState() => _IviaOnboardingState();
}

class _IviaOnboardingState extends State<IviaOnboarding> {
  static const _pageDuration = Duration(milliseconds: 300);

  final _controller = PageController();
  var _page = 0;

  bool get _isLast => _page == widget.slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) => _controller.animateToPage(
    page,
    duration: _pageDuration,
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final brand = widget.brand;
    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_page - 1);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  IviaSpacing.screen,
                  IviaSpacing.sm,
                  IviaSpacing.sm,
                  0,
                ),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      if (_page == 0) ...[
                        IviaLogoTile(color: brand.accent),
                        if (widget.appName case final name?) ...[
                          const SizedBox(width: IviaSpacing.md),
                          // Souple : tronqué plutôt que de pousser « Passer »
                          // hors de l'écran avec une police très agrandie.
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: brand.accent),
                            ),
                          ),
                        ],
                      ] else
                        IviaBackButton(onPressed: () => _goTo(_page - 1)),
                      const Spacer(),
                      // Taille gardée sur la dernière page : l'en-tête ne bouge pas.
                      Visibility(
                        visible: !_isLast,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: TextButton(
                          onPressed: widget.onDone,
                          style: TextButton.styleFrom(
                            foregroundColor: IviaColors.textSecondary,
                          ),
                          child: const Text('Passer'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.slides.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, i) => _SlideView(
                    slide: widget.slides[i],
                    index: i,
                    count: widget.slides.length,
                    brand: brand,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  IviaSpacing.screen,
                  IviaSpacing.lg,
                  IviaSpacing.screen,
                  IviaSpacing.xl,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLast ? widget.onDone : () => _goTo(_page + 1),
                    child: Text(_isLast ? 'Commencer' : 'Suivant'),
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

class _SlideView extends StatelessWidget {
  const _SlideView({
    required this.slide,
    required this.index,
    required this.count,
    required this.brand,
  });

  final OnboardingSlide slide;
  final int index;
  final int count;
  final IviaAppBrand brand;

  /// Hauteur réservée au texte sous l'illustration, à police normale.
  static const _textBlockHeight = 190.0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        // L'illustration prend la place laissée par le texte ; avec une
        // police très agrandie, elle garde une taille minimale et la page
        // défile.
        final artHeight =
            (constraints.maxHeight -
                    IviaSpacing.lg -
                    _textBlockHeight * textScale)
                .clamp(200.0, 440.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: IviaSpacing.lg),
              SizedBox(
                height: artHeight,
                width: double.infinity,
                child: slide.illustration,
              ),
              const SizedBox(height: IviaSpacing.xxl),
              _PageIndicator(count: count, current: index, color: brand.accent),
              const SizedBox(height: IviaSpacing.lg),
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: IviaOnboarding.titleMaxTextScale,
                child: Semantics(
                  header: true,
                  child: Text.rich(
                    _titleSpan(slide, brand.highlight),
                    style: textTheme.headlineMedium,
                  ),
                ),
              ),
              const SizedBox(height: IviaSpacing.sm),
              Text(
                slide.body,
                style: textTheme.bodyLarge?.copyWith(
                  color: IviaColors.textSecondary,
                ),
              ),
              const SizedBox(height: IviaSpacing.sm),
            ],
          ),
        );
      },
    );
  }

  /// Couleur des titres de l'app (Imperial ou Cobalt), permise pour un
  /// titre de 24 px et plus (docs/DESIGN.md, Contrastes).
  static TextSpan _titleSpan(OnboardingSlide slide, Color highlightColor) {
    final highlight = slide.highlight;
    final start = highlight == null ? -1 : slide.title.indexOf(highlight);
    if (highlight == null || start < 0) return TextSpan(text: slide.title);
    return TextSpan(
      children: [
        TextSpan(text: slide.title.substring(0, start)),
        TextSpan(
          text: highlight,
          style: TextStyle(color: highlightColor),
        ),
        TextSpan(text: slide.title.substring(start + highlight.length)),
      ],
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.count,
    required this.current,
    required this.color,
  });

  final int count;
  final int current;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Région « live » : le lecteur d'écran annonce le changement de page.
    return Semantics(
      liveRegion: true,
      label: 'Page ${current + 1} sur $count',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < count; i++)
              Container(
                margin: const EdgeInsets.only(right: IviaSpacing.sm),
                width: i == current ? IviaSpacing.xxl : IviaSpacing.sm,
                height: IviaSpacing.sm,
                decoration: BoxDecoration(
                  color: i == current ? color : IviaColors.borderInput,
                  borderRadius: BorderRadius.circular(IviaRadius.pill),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
