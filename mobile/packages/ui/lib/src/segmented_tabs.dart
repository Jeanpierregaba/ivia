import 'package:flutter/material.dart';

import 'brand.dart';
import 'tokens.dart';

/// Onglet de [IviaSegmentedTabs] ; [count] `null` : nombre pas encore connu.
class IviaSegment {
  const IviaSegment({required this.label, this.count});

  final String label;
  final int? count;
}

/// Onglets dans une carte blanche (ex. En vente, Brouillons, Retirés) :
/// l'onglet actif est plein, chacun peut porter un nombre.
class IviaSegmentedTabs extends StatelessWidget {
  const IviaSegmentedTabs({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
  });

  final List<IviaSegment> segments;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final brand = IviaAppBrand.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(IviaSpacing.sm),
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
      ),
      child: Row(
        children: [
          for (final (i, segment) in segments.indexed)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                label: segment.count == null
                    ? segment.label
                    : '${segment.label}, ${segment.count}',
                excludeSemantics: true,
                onTap: () => onSelected(i),
                child: Material(
                  color: i == selected ? brand.action : Colors.transparent,
                  borderRadius: BorderRadius.circular(IviaRadius.button),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(IviaRadius.button),
                    onTap: () => onSelected(i),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: IviaSpacing.xs,
                          vertical: IviaSpacing.sm,
                        ),
                        child: Center(
                          child: Text.rich(
                            TextSpan(
                              text: segment.label,
                              children: [
                                if (segment.count case final count?)
                                  TextSpan(
                                    text: ' $count',
                                    style: TextStyle(
                                      fontSize:
                                          (textTheme.titleSmall?.fontSize ??
                                              15) *
                                          0.85,
                                      color: i == selected
                                          ? IviaColors.secondarySoft
                                          : IviaColors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall?.copyWith(
                              color: i == selected
                                  ? Colors.white
                                  : IviaColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
