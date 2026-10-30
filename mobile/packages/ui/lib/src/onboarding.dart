import 'package:flutter/material.dart';

import 'brand.dart';
import 'tokens.dart';

/// Une page de la présentation.
class OnboardingSlide {
  const OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
  });

  /// Pictogramme provisoire, en attendant les illustrations du designer.
  final IconData icon;
  final String title;
  final String body;
}

/// Présentation du premier lancement : pages à faire défiler, « Passer »,
/// « Suivant » puis « Commencer ». Le retour Android revient à la page
/// précédente ; sur la première page, il quitte l'écran.
class IviaOnboarding extends StatefulWidget {
  const IviaOnboarding({
    super.key,
    required this.brand,
    required this.slides,
    required this.onDone,
  }) : assert(slides.length > 0);

  final IviaAppBrand brand;
  final List<OnboardingSlide> slides;

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
        backgroundColor: IviaColors.surface,
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
                child: Row(
                  children: [
                    IviaLogo(color: brand.logoOnLight, height: 28),
                    const Spacer(),
                    // Taille gardée sur la dernière page : l'en-tête ne bouge pas.
                    Visibility(
                      visible: !_isLast,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: TextButton(
                        onPressed: widget.onDone,
                        child: const Text('Passer'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.slides.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, i) =>
                      _SlideView(slide: widget.slides[i], brand: brand),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  IviaSpacing.screen,
                  IviaSpacing.lg,
                  IviaSpacing.screen,
                  IviaSpacing.xxl,
                ),
                child: Column(
                  children: [
                    _PageIndicator(
                      count: widget.slides.length,
                      current: _page,
                      color: brand.accent,
                    ),
                    const SizedBox(height: IviaSpacing.xxl),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isLast
                            ? widget.onDone
                            : () => _goTo(_page + 1),
                        child: Text(_isLast ? 'Commencer' : 'Suivant'),
                      ),
                    ),
                  ],
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
  const _SlideView({required this.slide, required this.brand});

  final OnboardingSlide slide;
  final IviaAppBrand brand;

  static const _illustrationSize = 168.0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Défilement : le texte doit rester lisible avec la police agrandie.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: _illustrationSize,
                height: _illustrationSize,
                decoration: BoxDecoration(
                  color: brand.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(slide.icon, size: 72, color: brand.accent),
              ),
              const SizedBox(height: IviaSpacing.huge),
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: IviaOnboarding.titleMaxTextScale,
                child: Semantics(
                  header: true,
                  child: Text(
                    slide.title,
                    style: textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: IviaSpacing.md),
              Text(
                slide.body,
                style: textTheme.bodyLarge?.copyWith(
                  color: IviaColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: IviaSpacing.xs),
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
