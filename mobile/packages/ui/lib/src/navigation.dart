import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'motion.dart';
import 'tokens.dart';

/// Onglet de [IviaBottomNav].
class IviaNavItem {
  const IviaNavItem({
    required this.icon,
    required this.label,
    this.badge,
    this.badgeLabel,
  });

  final IconData icon;

  /// Affiché sur l'onglet actif, lu par le lecteur d'écran sur tous.
  final String label;

  /// Nombre affiché en pastille sur l'icône (« 9+ » au-delà de 9) ; rien
  /// si `null` ou 0.
  final int? badge;

  /// Lecture de la pastille (« 2 nouvelles ») ; le nombre seul par défaut.
  final String? badgeLabel;

  bool get hasBadge => (badge ?? 0) > 0;

  /// Libellé lu par le lecteur d'écran : « Commandes, 2 nouvelles ».
  String get semanticLabel =>
      hasBadge ? '$label, ${badgeLabel ?? '$badge'}' : label;
}

/// Icône d'onglet avec sa pastille éventuelle.
class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.item, required this.color});

  final IviaNavItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(item.icon, color: color);
    if (!item.hasBadge) return icon;
    final count = item.badge!;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          top: -6,
          right: -10,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const ShapeDecoration(
              // Cornell : le blanc y atteint 4,5:1, pas sur Imperial.
              color: IviaColors.error,
              shape: StadiumBorder(
                side: BorderSide(color: IviaColors.surface, width: 1.5),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              count > 9 ? '9+' : '$count',
              // Taille fixe : la pastille ne doit pas grossir avec la police.
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Barre du bas en pilule blanche : l'onglet actif est une pilule pleine (icône et libellé) qui
/// glisse et s'élargit d'un onglet à l'autre ; les autres sont une icône seule.
class IviaBottomNav extends StatelessWidget {
  const IviaBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<IviaNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const _height = 64.0;

  @override
  Widget build(BuildContext context) {
    final brand = IviaAppBrand.of(context);
    final duration = IviaMotion.of(context, IviaMotion.medium);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        IviaSpacing.lg,
        0,
        IviaSpacing.lg,
        IviaSpacing.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(IviaSpacing.sm),
        decoration: const ShapeDecoration(
          color: IviaColors.surface,
          shape: StadiumBorder(),
          shadows: IviaShadows.navigation,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // L'onglet actif compte double : il prend la place de son libellé.
            final unit = constraints.maxWidth / (items.length + 1);
            return Row(
              children: [
                for (final (i, item) in items.indexed)
                  _NavTab(
                    item: item,
                    selected: i == currentIndex,
                    width: unit * (i == currentIndex ? 2 : 1),
                    height: _height - 16,
                    color: brand.action,
                    duration: duration,
                    onTap: () {
                      if (i != currentIndex) HapticFeedback.selectionClick();
                      onSelected(i);
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.selected,
    required this.width,
    required this.height,
    required this.color,
    required this.duration,
    required this.onTap,
  });

  final IviaNavItem item;
  final bool selected;
  final double width, height;
  final Color color;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fg = selected ? Colors.white : IviaColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: AnimatedContainer(
        duration: duration,
        curve: IviaMotion.emphasized,
        width: width,
        height: height,
        decoration: ShapeDecoration(
          color: selected ? color : color.withValues(alpha: 0),
          shape: const StadiumBorder(),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    scale: selected ? 1.06 : 1,
                    duration: duration,
                    curve: Curves.easeOutBack,
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: fg),
                      duration: duration,
                      builder: (context, c, _) =>
                          _NavIcon(item: item, color: c ?? fg),
                    ),
                  ),
                  // Libellé de l'onglet actif seulement : il apparaît en fondu en s'élargissant.
                  Flexible(
                    child: AnimatedSize(
                      duration: duration,
                      curve: IviaMotion.emphasized,
                      child: selected
                          ? Padding(
                              padding: const EdgeInsets.only(
                                left: IviaSpacing.sm,
                              ),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: 1),
                                duration: duration,
                                builder: (context, v, child) =>
                                    Opacity(opacity: v, child: child),
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleSmall?.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
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
