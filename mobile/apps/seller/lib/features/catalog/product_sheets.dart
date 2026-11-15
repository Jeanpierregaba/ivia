import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'catalog_labels.dart';

/// Vignette d'un produit : photo envoyée, photo choisie, ou emplacement vide.
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, this.url, this.bytes, this.size = 56});

  final String? url;
  final Uint8List? bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(IviaRadius.button);
    const placeholder = IviaImagePlaceholder();
    final image = switch ((bytes, url)) {
      (final Uint8List b, _) => Image.memory(b, fit: BoxFit.cover),
      (_, final String u) => Image.network(
        u,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      ),
      _ => placeholder,
    };
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ClipRRect(borderRadius: radius, child: image),
      ),
    );
  }
}

/// Titre d'une feuille.
class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
  );
}

/// Contenu d'une feuille : marges, défilement, clavier.
Future<T?> _sheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            IviaSpacing.screen,
            0,
            IviaSpacing.screen,
            IviaSpacing.screen,
          ),
          child: builder(context),
        ),
      ),
    );

/// « Retirer ce produit de la vente ? » ; `true` : confirmé.
Future<bool> showWithdrawSheet(BuildContext context, Product product) async {
  final confirmed = await _sheet<bool>(context, (context) {
    final textTheme = Theme.of(context).textTheme;
    const points = [
      "Il n'apparaît plus dans la recherche ni dans votre boutique.",
      'Les commandes déjà payées restent à préparer.',
      'Vous pourrez le remettre en vente à tout moment.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(IviaSpacing.md),
          decoration: BoxDecoration(
            color: IviaColors.background,
            borderRadius: BorderRadius.circular(IviaRadius.large),
          ),
          child: Row(
            children: [
              ProductThumb(url: product.images.firstOrNull?.url, size: 48),
              const SizedBox(width: IviaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: textTheme.titleSmall),
                    Text(
                      [
                        formatXof(product.priceXof),
                        if (product.stockMode == StockMode.tracked)
                          stockLabel(product),
                      ].join(' · '),
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: IviaSpacing.xl),
        const _SheetTitle('Retirer ce produit de la vente ?'),
        const SizedBox(height: IviaSpacing.md),
        for (final point in points)
          Padding(
            padding: const EdgeInsets.only(bottom: IviaSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(child: Text('•  ')),
                Expanded(
                  child: Text(
                    point,
                    style: textTheme.bodyLarge?.copyWith(
                      color: IviaColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: IviaSpacing.lg),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: IviaColors.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Retirer de la vente'),
        ),
        const SizedBox(height: IviaSpacing.sm),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: IviaColors.background,
            foregroundColor: IviaColors.text,
          ),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
      ],
    );
  });
  return confirmed ?? false;
}

/// Quantité d'un stock suivi ; `null` : abandon.
Future<int?> showStockSheet(BuildContext context, {required int initial}) =>
    _sheet<int>(context, (context) => _StockSheet(initial: initial));

/// Contenu de la feuille « Stock ». La quantité vit dans l'état du widget :
/// la feuille se reconstruit à chaque mouvement du clavier.
class _StockSheet extends StatefulWidget {
  const _StockSheet({required this.initial});

  final int initial;

  @override
  State<_StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends State<_StockSheet> {
  late var _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetTitle('Stock'),
        const SizedBox(height: IviaSpacing.sm),
        Text(
          'La quantité baisse à chaque commande. Impossible de vendre plus '
          'que le stock.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: IviaColors.textSecondary),
        ),
        const SizedBox(height: IviaSpacing.xl),
        Center(
          child: IviaQuantityStepper(
            label: 'Quantité disponible',
            value: _value,
            onChanged: (v) => setState(() => _value = v),
          ),
        ),
        const SizedBox(height: IviaSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.pop(context, _value),
          child: const Text('Valider'),
        ),
      ],
    );
  }
}

/// Explication d'un stock non suivi (mode figé à la création).
Future<void> showUntrackedStockSheet(BuildContext context) =>
    _sheet<void>(context, (context) {
      final textTheme = Theme.of(context).textTheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetTitle('Stock non suivi'),
          const SizedBox(height: IviaSpacing.sm),
          Text(
            'Vous confirmez la disponibilité à chaque commande. Le mode de '
            'stock est choisi à la création du produit et ne change plus : '
            'des commandes peuvent réserver la quantité.',
            style: textTheme.bodyMedium?.copyWith(
              color: IviaColors.textSecondary,
            ),
          ),
          const SizedBox(height: IviaSpacing.xl),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Compris'),
          ),
        ],
      );
    });

/// Description, 500 caractères au plus ; `null` : abandon.
Future<String?> showDescriptionSheet(BuildContext context, String initial) {
  final controller = TextEditingController(text: initial);
  return _sheet<String>(
    context,
    (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetTitle('Description'),
        const SizedBox(height: IviaSpacing.lg),
        DescriptionField(controller: controller, autofocus: true),
        const SizedBox(height: IviaSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Valider'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// Champ de description avec compteur « 98 / 500 ».
class DescriptionField extends StatelessWidget {
  const DescriptionField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
  });

  static const maxLength = 500;

  final TextEditingController controller;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return IviaFieldLabel(
      label: 'Description',
      child: TextField(
        controller: controller,
        enabled: enabled,
        autofocus: autofocus,
        onChanged: onChanged,
        minLines: 3,
        maxLines: 6,
        maxLength: maxLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Taille, origine, conseils d’utilisation…',
        ),
      ),
    );
  }
}

/// Choix de la taille du colis, avec son explication.
class ParcelSizePicker extends StatelessWidget {
  const ParcelSizePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final ParcelSize? value;
  final ValueChanged<ParcelSize>? onChanged;
  final String? errorText;

  static const _squares = {
    ParcelSize.small: 20.0,
    ParcelSize.medium: 32.0,
    ParcelSize.large: 46.0,
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final action = IviaAppBrand.of(context).action;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Taille du colis', style: textTheme.labelLarge),
        ),
        const SizedBox(height: IviaSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, size) in ParcelSize.values.indexed) ...[
              if (i > 0) const SizedBox(width: IviaSpacing.sm),
              Expanded(
                child: IviaChoiceCard(
                  label: parcelLabel(size),
                  selected: value == size,
                  onTap: onChanged == null ? null : () => onChanged!(size),
                  visual: Container(
                    width: _squares[size],
                    height: _squares[size],
                    decoration: BoxDecoration(
                      color: value == size ? action : IviaColors.border,
                      borderRadius: BorderRadius.circular(IviaRadius.tile),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: IviaSpacing.sm),
        Text(
          'La taille détermine le véhicule envoyé pour la livraison (moto ou '
          'voiture).',
          style: textTheme.bodySmall,
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: IviaSpacing.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(
                errorText!,
                style: textTheme.bodySmall?.copyWith(color: IviaColors.error),
              ),
            ),
          ),
      ],
    );
  }
}

/// Taille du colis ; `null` : abandon.
Future<ParcelSize?> showParcelSheet(BuildContext context, ParcelSize initial) =>
    _sheet<ParcelSize>(
      context,
      (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ParcelSizePicker(
            value: initial,
            onChanged: (size) => Navigator.pop(context, size),
          ),
        ],
      ),
    );

/// Action sur une photo choisie.
enum PhotoAction { makeMain, remove }

Future<PhotoAction?> showPhotoActions(
  BuildContext context, {
  required bool isMain,
}) => showModalBottomSheet<PhotoAction>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isMain)
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Mettre en principale'),
              onTap: () => Navigator.pop(context, PhotoAction.makeMain),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: IviaColors.error),
            title: const Text('Supprimer'),
            onTap: () => Navigator.pop(context, PhotoAction.remove),
          ),
        ],
      ),
    ),
  ),
);
