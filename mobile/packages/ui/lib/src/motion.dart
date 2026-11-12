import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Mouvement commun des apps ivia : durées et courbes courtes, jamais de boucle sans fin, et rien
/// quand le téléphone demande de réduire les animations.
abstract final class IviaMotion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);

  /// Courbe d'entrée : départ vif, arrivée douce.
  static const emphasized = Cubic(0.2, 0, 0, 1);
  static const standard = Curves.easeOutCubic;

  /// Le téléphone demande de réduire les animations.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], ou zéro si les animations sont réduites.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

/// Transition entre écrans : fondu et léger glissement vers le haut (Android, web, ordinateur).
/// Sur iPhone, la transition native reste, avec son retour par glissement.
class IviaPageTransitionsBuilder extends PageTransitionsBuilder {
  const IviaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (IviaMotion.reduced(context)) return child;
    final enter = CurvedAnimation(
      parent: animation,
      curve: IviaMotion.emphasized,
      reverseCurve: Curves.easeInCubic,
    );
    final leave = CurvedAnimation(
      parent: secondaryAnimation,
      curve: IviaMotion.standard,
    );
    return SlideTransition(
      // L'écran quitté recule un peu vers la gauche en s'estompant.
      position: Tween(
        begin: Offset.zero,
        end: const Offset(-0.12, 0),
      ).animate(leave),
      child: FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.55).animate(leave),
        child: FadeTransition(
          opacity: enter,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0.18, 0),
              end: Offset.zero,
            ).animate(enter),
            child: ScaleTransition(
              scale: Tween(begin: 0.98, end: 1.0).animate(enter),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Transitions d'écran du thème ivia.
const iviaPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: IviaPageTransitionsBuilder(),
    TargetPlatform.fuchsia: IviaPageTransitionsBuilder(),
    TargetPlatform.linux: IviaPageTransitionsBuilder(),
    TargetPlatform.windows: IviaPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
  },
);

/// Apparition en cascade d'une section ou d'un élément de liste : fondu et montée de quelques
/// pixels, décalés selon [index] (au plus 8 crans). Une seule fois, à la première construction.
class IviaReveal extends StatefulWidget {
  const IviaReveal({super.key, this.index = 0, required this.child});

  final int index;
  final Widget child;

  @override
  State<IviaReveal> createState() => _IviaRevealState();
}

class _IviaRevealState extends State<IviaReveal>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: IviaMotion.slow);
  late final _a = CurvedAnimation(parent: _c, curve: IviaMotion.emphasized);
  Timer? _timer;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (IviaMotion.reduced(context)) {
      _c.value = 1;
      return;
    }
    _timer = Timer(Duration(milliseconds: 45 * widget.index.clamp(0, 8)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _a,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(_a),
      child: widget.child,
    ),
  );
}

/// Élément qui s'enfonce légèrement sous le doigt, avec une vibration discrète à l'appui.
/// À placer autour d'une carte ou d'une tuile ; l'appui lui-même reste géré par l'enfant.
class IviaPressable extends StatefulWidget {
  const IviaPressable({
    super.key,
    required this.child,
    this.scale = 0.97,
    this.haptic = true,
  });

  final Widget child;
  final double scale;
  final bool haptic;

  @override
  State<IviaPressable> createState() => _IviaPressableState();
}

class _IviaPressableState extends State<IviaPressable> {
  var _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      _set(true);
      if (widget.haptic) HapticFeedback.selectionClick();
    },
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down ? widget.scale : 1,
      duration: IviaMotion.of(context, IviaMotion.fast),
      curve: IviaMotion.standard,
      child: widget.child,
    ),
  );
}

/// Passage en fondu d'un état à l'autre (chargement, contenu, erreur) : la clé de chaque état doit
/// être différente.
class IviaStateSwitcher extends StatelessWidget {
  const IviaStateSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: IviaMotion.of(context, IviaMotion.medium),
    switchInCurve: IviaMotion.standard,
    switchOutCurve: Curves.easeIn,
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.topCenter,
      children: [...previous, ?current],
    ),
    child: child,
  );
}

/// Nombre qui change avec un petit rebond (compteur du panier, pastilles).
class IviaAnimatedCount extends StatelessWidget {
  const IviaAnimatedCount({super.key, required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: IviaMotion.of(context, IviaMotion.medium),
    transitionBuilder: (child, a) => ScaleTransition(
      scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
      child: FadeTransition(opacity: a, child: child),
    ),
    child: Text('$value', key: ValueKey(value), style: style),
  );
}

/// Contenu centré à une largeur lisible sur grand écran (tablette, ordinateur) ; sans effet sur
/// un téléphone.
class IviaMaxWidth extends StatelessWidget {
  const IviaMaxWidth({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Nombre de colonnes d'une grille selon la largeur disponible : 2 sur téléphone, plus au-delà.
int iviaGridColumns(
  double width, {
  double minTileWidth = 168,
  int min = 2,
  int max = 6,
}) => (width / minTileWidth).floor().clamp(min, max);

/// Bloc gris de chargement, balayé d'un reflet pendant quelques secondes au plus (puis fixe :
/// jamais d'animation sans fin).
class IviaSkeleton extends StatefulWidget {
  const IviaSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = IviaRadius.tile,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<IviaSkeleton> createState() => _IviaSkeletonState();
}

class _IviaSkeletonState extends State<IviaSkeleton>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  var _runs = 0;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && ++_runs < 6) _c.forward(from: 0);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!IviaMotion.reduced(context) && !_c.isAnimating && _runs == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * 2 - 0.5;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + t * 2, 0),
              end: Alignment(t * 2, 0),
              colors: const [
                Color(0xFFEDEFF3),
                Color(0xFFF7F8FA),
                Color(0xFFEDEFF3),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Squelette d'une carte produit (photo, nom, prix).
class IviaProductCardSkeleton extends StatelessWidget {
  const IviaProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(IviaSpacing.sm),
    decoration: BoxDecoration(
      color: IviaColors.surface,
      borderRadius: BorderRadius.circular(IviaRadius.large),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1.3,
          child: IviaSkeleton(radius: IviaRadius.button),
        ),
        SizedBox(height: IviaSpacing.md),
        IviaSkeleton(height: 14),
        SizedBox(height: IviaSpacing.sm),
        IviaSkeleton(width: 80, height: 14),
        SizedBox(height: IviaSpacing.sm),
        IviaSkeleton(width: 60, height: 12),
      ],
    ),
  );
}

/// Squelette d'une liste de lignes (icône ronde, deux lignes de texte).
class IviaListSkeleton extends StatelessWidget {
  const IviaListSkeleton({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Chargement',
    child: Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: IviaSpacing.sm),
            child: Row(
              children: [
                const IviaSkeleton(width: 44, height: 44, radius: 22),
                const SizedBox(width: IviaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const IviaSkeleton(height: 14),
                      const SizedBox(height: IviaSpacing.sm),
                      FractionallySizedBox(
                        widthFactor: i.isEven ? 0.6 : 0.4,
                        child: const IviaSkeleton(height: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Squelette d'une grille de cartes produit (2 colonnes sur téléphone, plus au-delà).
class IviaGridSkeleton extends StatelessWidget {
  const IviaGridSkeleton({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Chargement',
    child: LayoutBuilder(
      builder: (context, constraints) {
        final columns = iviaGridColumns(constraints.maxWidth);
        final rows = (count / columns).ceil();
        return Column(
          children: [
            for (var r = 0; r < rows; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: IviaSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) const SizedBox(width: IviaSpacing.sm),
                      const Expanded(child: IviaProductCardSkeleton()),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Squelette d'une page de détail (grande photo, titre, lignes de texte).
class IviaPageSkeleton extends StatelessWidget {
  const IviaPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Chargement',
    child: const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      padding: EdgeInsets.all(IviaSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.4,
            child: IviaSkeleton(radius: IviaRadius.large),
          ),
          SizedBox(height: IviaSpacing.xl),
          IviaSkeleton(height: 22, width: 220),
          SizedBox(height: IviaSpacing.md),
          IviaSkeleton(height: 16, width: 140),
          SizedBox(height: IviaSpacing.xl),
          IviaSkeleton(height: 14),
          SizedBox(height: IviaSpacing.sm),
          IviaSkeleton(height: 14),
          SizedBox(height: IviaSpacing.sm),
          IviaSkeleton(height: 14, width: 180),
        ],
      ),
    ),
  );
}
