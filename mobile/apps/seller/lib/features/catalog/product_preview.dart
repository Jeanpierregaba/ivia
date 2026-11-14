import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'product_form.dart';
import 'product_sheets.dart';

/// Carte du produit telle que l'acheteur la verra : photos défilantes,
/// nom, prix, boutique, étiquettes, début de la description.
class ProductPreviewCard extends StatefulWidget {
  const ProductPreviewCard({
    super.key,
    required this.photos,
    required this.name,
    required this.price,
    required this.shopLine,
    required this.availability,
    required this.chips,
    required this.description,
  });

  final List<EditorPhoto> photos;
  final String name;
  final String price;

  /// « Chez Afi · Tokoin ».
  final String shopLine;

  /// « En stock », « Épuisé », « Disponible ».
  final String availability;
  final List<String> chips;
  final String description;

  @override
  State<ProductPreviewCard> createState() => _ProductPreviewCardState();
}

class _ProductPreviewCardState extends State<ProductPreviewCard> {
  var _page = 0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final photos = widget.photos;
    return Container(
      padding: const EdgeInsets.all(IviaSpacing.sm),
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.6,
            child: Stack(
              children: [
                Positioned.fill(
                  child: photos.isEmpty
                      ? const IviaImagePlaceholder(radius: IviaRadius.large)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(IviaRadius.large),
                          child: PageView(
                            onPageChanged: (i) => setState(() => _page = i),
                            children: [
                              for (final photo in photos)
                                LayoutBuilder(
                                  builder: (context, c) => FittedBox(
                                    fit: BoxFit.cover,
                                    clipBehavior: Clip.hardEdge,
                                    child: ProductThumb(
                                      url: photo.url,
                                      bytes: photo.bytes,
                                      size: c.maxWidth,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
                if (photos.length > 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: IviaSpacing.md,
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < photos.length; i++)
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
          ),
          Padding(
            padding: const EdgeInsets.all(IviaSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: IviaSpacing.md,
                  children: [
                    Text(widget.name, style: textTheme.titleLarge),
                    Text(widget.price, style: textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: IviaSpacing.xs),
                Text.rich(
                  TextSpan(
                    text: widget.shopLine.isEmpty
                        ? ''
                        : '${widget.shopLine} · ',
                    children: [
                      TextSpan(
                        text: widget.availability,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: widget.availability == 'Épuisé'
                              ? IviaColors.error
                              : IviaColors.cobaltBlue,
                        ),
                      ),
                    ],
                  ),
                  style: textTheme.bodyMedium?.copyWith(
                    color: IviaColors.textMuted,
                  ),
                ),
                const SizedBox(height: IviaSpacing.md),
                Wrap(
                  spacing: IviaSpacing.sm,
                  runSpacing: IviaSpacing.sm,
                  children: [
                    for (final chip in widget.chips)
                      IviaStatusPill(label: chip, tone: IviaPillTone.neutral),
                  ],
                ),
                if (widget.description.isNotEmpty) ...[
                  const SizedBox(height: IviaSpacing.md),
                  Text(
                    widget.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: IviaColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vérification de l'aperçu : coche Cobalt et texte.
class PreviewCheck extends StatelessWidget {
  const PreviewCheck(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: IviaSpacing.md),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: IviaColors.cobaltBlue,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 18, color: Colors.white),
          ),
          const SizedBox(width: IviaSpacing.md),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

/// Deux éléments côte à côte, l'un sous l'autre sur un écran étroit ou
/// avec une police agrandie.
class SideBySide extends StatelessWidget {
  const SideBySide({
    super.key,
    required this.start,
    required this.end,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final Widget start;
  final Widget end;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 340 && !large
          ? Row(
              crossAxisAlignment: crossAxisAlignment,
              children: [
                Expanded(child: start),
                const SizedBox(width: IviaSpacing.md),
                Expanded(child: end),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                start,
                const SizedBox(height: IviaSpacing.md),
                end,
              ],
            ),
    );
  }
}

/// Nombre de photos manquantes pour publier : message de l'étape.
String? photosMissing(ProductForm form) =>
    form.photos.isEmpty ? 'Ajoutez au moins une photo.' : null;
