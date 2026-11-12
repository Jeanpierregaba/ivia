import 'package:flutter/material.dart';

import 'brand.dart';
import 'components.dart';
import 'motion.dart';
import 'tokens.dart';

/// Puce de filtre en pilule : blanche au repos, Berkeley quand elle est
/// active ; [dropdown] ajoute une flèche (elle ouvre un choix).
class IviaChip extends StatelessWidget {
  const IviaChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.dropdown = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool dropdown;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : IviaColors.text;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? IviaColors.tertiary : IviaColors.surface,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.lg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: foreground),
                  ),
                  if (dropdown) ...[
                    const SizedBox(width: IviaSpacing.xs),
                    Icon(Icons.arrow_drop_down, color: foreground),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Image d'une URL publique ; emplacement hachuré sans URL ou en cas
/// d'échec du chargement.
class IviaNetworkImage extends StatelessWidget {
  const IviaNetworkImage({
    super.key,
    required this.url,
    this.radius = IviaRadius.button,
  });

  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = IviaImagePlaceholder(radius: radius);
    final u = url;
    if (u == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        u,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

/// Carte d'un produit dans une grille : photo carrée, nom, ligne de la
/// boutique (distance en Cobalt), prix ; « Épuisé » s'il n'est pas en stock.
class IviaProductCard extends StatelessWidget {
  const IviaProductCard({
    super.key,
    required this.imageUrl,
    required this.name,
    required this.shopName,
    required this.price,
    required this.onTap,
    this.distance,
    this.soldOut = false,
    this.onAdd,
    this.adding = false,
    this.oldPrice,
    this.badge,
  });

  final String? imageUrl;
  final String name;
  final String shopName;

  /// Prix normal barré pendant une promotion (déjà mis en forme).
  final String? oldPrice;

  /// Badge commercial sur la photo (« Promotion », « Produit vedette »).
  final String? badge;

  /// Distance déjà mise en forme (« 350 m ») ; `null` : inconnue.
  final String? distance;

  /// Prix déjà mis en forme (« 4 500 F »).
  final String price;
  final bool soldOut;
  final VoidCallback onTap;

  /// Ajout rapide au panier (« + » sur la photo) ; `null` : pas de bouton.
  final VoidCallback? onAdd;

  /// Ajout en cours : le « + » attend.
  final bool adding;

  @override
  Widget build(BuildContext context) {
    final card = _card(context);
    final add = onAdd;
    if (add == null) return card;
    return Stack(
      children: [
        card,
        Positioned(
          top: IviaSpacing.xs,
          right: IviaSpacing.xs,
          child: IviaAddButton(
            label: 'Ajouter $name au panier',
            onPressed: add,
            busy: adding,
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final spoken = [
      name,
      ?badge,
      price,
      if (oldPrice case final old?) 'au lieu de $old',
      shopName,
      ?distance,
      if (soldOut) 'épuisé',
    ].join(', ');
    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: IviaPressable(
        haptic: false,
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
                    aspectRatio: 1.3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        IviaNetworkImage(url: imageUrl),
                        if (badge case final b?)
                          Positioned(
                            right: IviaSpacing.xs,
                            bottom: IviaSpacing.xs,
                            child: IviaPromoBadge(label: b),
                          ),
                      ],
                    ),
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            text: shopName,
                            children: [
                              if (distance case final d?)
                                TextSpan(
                                  text: ' · $d',
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
                        const SizedBox(height: IviaSpacing.xs),
                        Wrap(
                          spacing: IviaSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          children: [
                            Text(
                              price,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: oldPrice == null
                                    ? null
                                    : IviaColors.imperialRed,
                              ),
                            ),
                            if (oldPrice case final old?)
                              Text(
                                old,
                                style: textTheme.bodySmall?.copyWith(
                                  decoration: TextDecoration.lineThrough,
                                  color: IviaColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                        if (soldOut)
                          Text(
                            'Épuisé',
                            style: textTheme.bodySmall?.copyWith(
                              color: IviaColors.error,
                              fontWeight: FontWeight.w700,
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
      ),
    );
  }
}

/// « + » rond d'ajout rapide au panier : 36 dp visibles, 48 dp au doigt.
class IviaAddButton extends StatelessWidget {
  const IviaAddButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  /// Lu par le lecteur d'écran (« Ajouter Riz parfumé au panier »).
  final String label;
  final VoidCallback? onPressed;

  /// Envoi en cours : indicateur à la place du « + », appui ignoré.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = IviaAppBrand.of(context).action;
    return Semantics(
      button: true,
      enabled: onPressed != null && !busy,
      label: label,
      excludeSemantics: true,
      onTap: busy ? null : onPressed,
      child: SizedBox.square(
        dimension: 48,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: busy ? null : onPressed,
            radius: 24,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: ShapeDecoration(
                  color: onPressed == null ? IviaColors.textSecondary : color,
                  shape: const CircleBorder(
                    side: BorderSide(color: IviaColors.surface, width: 2),
                  ),
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(IviaSpacing.sm),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: IviaColors.surface,
                        ),
                      )
                    : const Icon(
                        Icons.add,
                        size: 22,
                        color: IviaColors.surface,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Photos qui défilent, avec des points ; une seule photo : pas de points.
class IviaPhotoCarousel extends StatefulWidget {
  const IviaPhotoCarousel({super.key, required this.urls});

  final List<String> urls;

  @override
  State<IviaPhotoCarousel> createState() => _IviaPhotoCarouselState();
}

class _IviaPhotoCarouselState extends State<IviaPhotoCarousel> {
  var _page = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.isEmpty) return const IviaImagePlaceholder(radius: 0);
    return Semantics(
      label: urls.length == 1
          ? 'Photo du produit'
          : 'Photo ${_page + 1} sur ${urls.length}',
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView(
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final url in urls) IviaNetworkImage(url: url, radius: 0),
              ],
            ),
          ),
          if (urls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: IviaSpacing.xl,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < urls.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 20 : 8,
                        height: 8,
                        decoration: ShapeDecoration(
                          color: IviaColors.surface.withValues(
                            alpha: i == _page ? 1 : 0.7,
                          ),
                          shape: const StadiumBorder(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pastille commerciale (« Promotion », « Produit vedette ») : Imperial Red,
/// texte blanc, sur une photo ou au-dessus d'un titre.
class IviaPromoBadge extends StatelessWidget {
  const IviaPromoBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: IviaSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: IviaColors.imperialRed,
        borderRadius: BorderRadius.circular(IviaRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }
}
