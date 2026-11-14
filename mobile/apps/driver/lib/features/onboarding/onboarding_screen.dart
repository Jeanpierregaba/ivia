import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/ui.dart';
import 'illustrations.dart';

/// Une page de la présentation : illustration, titre en deux couleurs, texte.
class DriverSlide {
  const DriverSlide({
    required this.illustration,
    required this.title,
    required this.highlight,
    required this.body,
  });
  final Widget illustration;

  /// Titre complet ; [highlight] en est la fin, en bleu.
  final String title, highlight;
  final String body;

  String get start =>
      title.substring(0, title.length - highlight.length).trim();
}

/// Maquettes D01 à D03 (spec 033).
const onboardingSlides = [
  DriverSlide(
    illustration: MissionOfferIllustration(),
    title: 'Des missions près de vous.',
    highlight: 'près de vous.',
    body:
        'Restez disponible et recevez des propositions avec la boutique, la '
        'distance et le gain indicatif.',
  ),
  DriverSlide(
    illustration: MissionStepsIllustration(),
    title: 'Guidé à chaque étape.',
    highlight: 'à chaque étape.',
    body:
        "L'itinéraire s'ouvre dans votre application de cartes : la "
        'boutique, puis le client.',
  ),
  DriverSlide(
    illustration: CustomerCodeIllustration(),
    title: 'Le code du client valide la livraison.',
    highlight: 'valide la livraison.',
    body:
        'Saisissez le code à 4 chiffres. La mission est terminée et vous '
        'redevenez disponible.',
  ),
];

/// Présentation d'Ivia Driver, au premier lancement. « Passer » et
/// « Commencer » mémorisent qu'elle a été vue ; le routeur ouvre alors la
/// connexion.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  /// Agrandissement maximal des titres : au-delà, un mot long serait coupé
  /// sur un écran de 320 dp. Le texte courant suit la police sans limite.
  static const titleMaxTextScale = 1.5;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  var _page = 0;

  bool get _isLast => _page == onboardingSlides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) => _controller.animateToPage(
    page,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOutCubic,
  );

  void _done() => ref.read(onboardingSeenProvider.notifier).complete();

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _page == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _goTo(_page - 1);
    },
    child: Scaffold(
      backgroundColor: D.page,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: onboardingSlides.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, i) =>
                    _SlidePage(slide: onboardingSlides[i], index: i),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(D.gutter, 16, D.gutter, 22),
              child: DButton(
                label: _isLast ? 'Commencer' : 'Suivant',
                onTap: _isLast ? _done : () => _goTo(_page + 1),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// Logo et « Driver » sur la première page, retour ensuite ; « Passer »
  /// sauf sur la dernière (place gardée : l'en-tête ne bouge pas).
  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(D.gutter, 10, 14, 0),
    child: SizedBox(
      height: 44,
      child: Row(
        children: [
          // Un seul bloc extensible à gauche : « Passer » reste collé à droite.
          Expanded(
            child: _page == 0
                ? Row(
                    children: [
                      const IviaLogoTile(color: D.blue, size: 40),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Driver',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DText.cardTitle.copyWith(
                            color: D.blue,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: DRound.back(onTap: () => _goTo(_page - 1)),
                  ),
          ),
          Visibility(
            visible: !_isLast,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: TextButton(
              onPressed: _done,
              style: TextButton.styleFrom(
                foregroundColor: D.muted,
                textStyle: DText.cardTitle.copyWith(fontSize: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Passer'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SlidePage extends StatelessWidget {
  const _SlidePage({required this.slide, required this.index});
  final DriverSlide slide;
  final int index;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: D.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 18),
              // Police très agrandie : la carte garde une hauteur minimale et
              // la page défile.
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 200),
                  child: slide.illustration,
                ),
              ),
              const SizedBox(height: 20),
              _Dots(current: index, count: onboardingSlides.length),
              const SizedBox(height: 14),
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: OnboardingScreen.titleMaxTextScale,
                child: Semantics(
                  header: true,
                  child: DTitle(slide.start, slide.highlight),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                slide.body,
                style: DText.body.copyWith(fontSize: 15, height: 1.43),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Points de page : l'actif en pilule bleue.
class _Dots extends StatelessWidget {
  const _Dots({required this.current, required this.count});
  final int current, count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Page ${current + 1} sur $count',
    excludeSemantics: true,
    child: Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 6),
            width: i == current ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current ? D.blue : IviaDriverColors.checkOff,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    ),
  );
}
