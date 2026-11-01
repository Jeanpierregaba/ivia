import 'package:flutter/material.dart';

import 'brand.dart';
import 'tokens.dart';

/// Onglet de [IviaBottomNav].
class IviaNavItem {
  const IviaNavItem({required this.icon, required this.label});

  final IconData icon;

  /// Affiché sur l'onglet actif, lu par le lecteur d'écran sur tous.
  final String label;
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
                  label: item.label,
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
                                    Icon(item.icon, color: Colors.white),
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
                                child: Icon(
                                  item.icon,
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
