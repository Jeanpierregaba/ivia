import 'package:flutter/material.dart';

import 'brand.dart';
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

/// Barre du bas en pilule blanche : l'onglet actif est une pilule pleine
/// (icône et libellé), les autres une icône seule.
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
    final textTheme = Theme.of(context).textTheme;
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
        child: Row(
          children: [
            for (final (i, item) in items.indexed)
              Expanded(
                flex: i == currentIndex ? 2 : 1,
                child: Semantics(
                  button: true,
                  selected: i == currentIndex,
                  label: item.semanticLabel,
                  excludeSemantics: true,
                  onTap: () => onSelected(i),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => onSelected(i),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: _height - 16,
                      ),
                      child: i == currentIndex
                          ? DecoratedBox(
                              decoration: ShapeDecoration(
                                color: brand.action,
                                shape: const StadiumBorder(),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: IviaSpacing.md,
                                  vertical: IviaSpacing.sm,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _NavIcon(item: item, color: Colors.white),
                                    const SizedBox(width: IviaSpacing.sm),
                                    Flexible(
                                      child: Text(
                                        item.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.titleSmall?.copyWith(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          // Hauteur fixe : un Center seul s'étirerait sur
                          // tout l'écran dans `Scaffold.bottomNavigationBar`.
                          : SizedBox(
                              height: _height - 16,
                              child: Center(
                                child: _NavIcon(
                                  item: item,
                                  color: IviaColors.textMuted,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
