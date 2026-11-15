import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Carte d'une boutique (accueil) : logo, nom, « quartier · distance ».
class ShopCard extends StatelessWidget {
  const ShopCard({
    super.key,
    required this.name,
    required this.logoUrl,
    required this.place,
    required this.distance,
    required this.onTap,
    this.acceptingOrders = true,
  });

  final String name;
  final String? logoUrl;

  /// Quartier ; `null` : inconnu.
  final String? place;

  /// Distance mise en forme ; `null` : inconnue.
  final String? distance;
  final bool acceptingOrders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final spoken = [
      name,
      ?place,
      ?distance,
      if (!acceptingOrders) 'commandes suspendues',
    ].join(', ');
    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
        child: InkWell(
          borderRadius: BorderRadius.circular(IviaRadius.large),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(IviaSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 2,
                  child: IviaNetworkImage(url: logoUrl),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    IviaSpacing.xs,
                    IviaSpacing.md,
                    IviaSpacing.xs,
                    IviaSpacing.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          text: place ?? '',
                          children: [
                            if (distance case final d?)
                              TextSpan(
                                text: place == null ? d : ' · $d',
                                style: const TextStyle(
                                  color: IviaColors.cobaltBlue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                      if (!acceptingOrders)
                        Text(
                          'Commandes suspendues',
                          style: textTheme.bodySmall?.copyWith(
                            color: IviaColors.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
