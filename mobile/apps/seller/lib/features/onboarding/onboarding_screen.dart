import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../business/pro_ui.dart';

/// Présentation d'Ivia Business : les exemples des visuels illustrent le
/// produit, ce ne sont pas des données.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  var _page = 0;

  static const _slides = [
    (
      'Une seule app pour ',
      'toute votre activité.',
      'Boutique, restaurant, agence immobilière ou artisan : Ivia Business s\'adapte à votre métier.',
    ),
    (
      'Les clients du quartier ',
      'vous trouvent.',
      'Votre activité apparaît dans l\'app ivia et sur la carte, avec la distance.',
    ),
    (
      'Encaissez ',
      'par Mobile Money.',
      'Commandes et réservations sont payées dans l\'app avant que vous ne commenciez.',
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _done() => ref.read(onboardingSeenProvider.notifier).complete();

  void _next() {
    if (_page == _slides.length - 1) {
      _done();
    } else {
      _pages.nextPage(duration: Pro.medium, curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Pro.page,
      body: PageView.builder(
        controller: _pages,
        itemCount: _slides.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (context, i) {
          final (start, colored, body) = _slides[i];
          return Column(
            children: [
              Expanded(
                child: ProPanel(
                  accent: const [
                    IviaColors.cobaltBlue,
                    Color(0xFF0F766E),
                    Color(0xFFB9500A),
                  ][i],
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const IviaLogoTile(
                            size: 34,
                            color: IviaColors.cobaltBlue,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Business',
                            style: t.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          if (i < _slides.length - 1)
                            TextButton(
                              onPressed: _done,
                              child: const Text(
                                'Passer',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: switch (i) {
                            0 => const _SectorsVisual(),
                            1 => const _VisibilityVisual(),
                            _ => const _PaymentVisual(),
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Reveal(
                      child: Text.rich(
                        TextSpan(
                          text: start,
                          children: [
                            TextSpan(
                              text: colored,
                              style: const TextStyle(
                                color: IviaColors.cobaltBlue,
                              ),
                            ),
                          ],
                        ),
                        style: t.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Reveal(
                      index: 1,
                      child: Text(
                        body,
                        style: t.bodyLarge?.copyWith(color: Pro.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: Pro.medium,
                        height: 3,
                        margin: const EdgeInsets.only(right: 4, bottom: 14),
                        decoration: BoxDecoration(
                          color: i <= _page ? IviaColors.cobaltBlue : Pro.line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
              ProButton(
                label: _page == _slides.length - 1 ? 'Commencer' : 'Suivant',
                onPressed: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectorsVisual extends StatelessWidget {
  const _SectorsVisual();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const sectors = [
      ('shop', 'Boutique'),
      ('restaurant', 'Restaurant'),
      ('real_estate', 'Agence'),
      ('artisan', 'Artisan'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final (i, (code, label)) in sectors.indexed)
          Reveal(
            index: i,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Pro.ink2,
                borderRadius: BorderRadius.circular(Pro.radius),
                border: Border(
                  left: BorderSide(color: Pro.accent(code), width: 4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Pro.icon(code), color: Colors.white),
                  Text(
                    label,
                    style: t.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _VisibilityVisual extends StatelessWidget {
  const _VisibilityVisual();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const rows = [
      ('shop', 'Votre boutique', '350 m'),
      ('restaurant', 'Votre restaurant', '1,1 km'),
      ('artisan', 'Votre atelier', '2 km'),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, (code, title, distance)) in rows.indexed)
          Reveal(
            index: i,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Pro.radius),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Pro.accent(code),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(Pro.icon(code), size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    distance,
                    style: t.labelLarge?.copyWith(color: Pro.muted),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PaymentVisual extends StatelessWidget {
  const _PaymentVisual();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Reveal(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Pro.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COMMANDE PAYÉE',
                  style: t.labelSmall?.copyWith(
                    color: IviaColors.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Mobile Money',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Avant que vous ne commenciez',
                  style: t.bodySmall?.copyWith(color: Pro.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Reveal(
          index: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: IviaColors.success,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  'Paiement reçu',
                  style: t.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
