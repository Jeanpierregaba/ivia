import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'catalog_labels.dart';
import 'catalog_providers.dart';
import 'product_form.dart';
import 'product_sheets.dart';

/// Photos du produit : 1 à 5, la première est la principale. Grande
/// mosaïque à la création, rangée de vignettes ([compact]) à la
/// modification.
class PhotosField extends ConsumerStatefulWidget {
  const PhotosField({
    super.key,
    required this.photos,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
    this.compact = false,
  });

  final List<EditorPhoto> photos;
  final ValueChanged<List<EditorPhoto>> onChanged;
  final bool enabled;
  final String? errorText;
  final bool compact;

  @override
  ConsumerState<PhotosField> createState() => _PhotosFieldState();
}

class _PhotosFieldState extends ConsumerState<PhotosField> {
  String? _error;

  Future<void> _add() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      // Défilable : police agrandie sur un petit écran.
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Prendre une photo'),
                onTap: () => Navigator.pop(context, PhotoSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choisir une photo'),
                onTap: () => Navigator.pop(context, PhotoSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      // 1600 px : net sur un téléphone, léger à envoyer en 3G.
      final bytes = await ref
          .read(photoPickerProvider)
          .pick(source: source, maxSide: 1600);
      if (bytes == null || !mounted) return;
      if (bytes.length > maxUploadBytes) {
        setState(() => _error = 'Photo trop lourde (5 Mo au plus).');
        return;
      }
      setState(() => _error = null);
      widget.onChanged([...widget.photos, EditorPhoto.local(bytes)]);
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Photo impossible à utiliser. Vérifiez les autorisations '
              "de l'appareil photo et des photos.",
        );
      }
    }
  }

  Future<void> _actions(int index) async {
    final action = await showPhotoActions(context, isMain: index == 0);
    if (action == null) return;
    final photos = [...widget.photos];
    final photo = photos.removeAt(index);
    if (action == PhotoAction.makeMain) photos.insert(0, photo);
    widget.onChanged(photos);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final error = _error ?? widget.errorText;
    final count = widget.photos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.compact) ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: IviaSpacing.sm,
            children: [
              Semantics(
                header: true,
                child: Text('Photos', style: textTheme.labelLarge),
              ),
              Text(
                '1 à $maxPhotos · la 1re est la principale',
                style: textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: IviaSpacing.sm),
        ],
        if (widget.compact)
          Wrap(
            spacing: IviaSpacing.sm,
            runSpacing: IviaSpacing.sm,
            children: [
              for (var i = 0; i < count; i++)
                SizedBox.square(dimension: 72, child: _photo(i)),
              if (count < maxPhotos)
                SizedBox.square(dimension: 72, child: _addTile(small: true)),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: AspectRatio(aspectRatio: 1, child: _slot(0))),
              const SizedBox(width: IviaSpacing.sm),
              Expanded(
                child: Column(
                  children: [
                    for (final row in const [
                      [1, 2],
                      [3, 4],
                    ]) ...[
                      if (row.first == 3)
                        const SizedBox(height: IviaSpacing.sm),
                      Row(
                        children: [
                          for (final i in row) ...[
                            if (i.isEven) const SizedBox(width: IviaSpacing.sm),
                            Expanded(
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: _slot(i),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: IviaSpacing.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: textTheme.bodySmall?.copyWith(color: IviaColors.error),
              ),
            ),
          ),
      ],
    );
  }

  Widget _slot(int i) {
    final count = widget.photos.length;
    if (i < count) return _photo(i);
    if (i == count) return _addTile(small: i > 0);
    return const _DashedBox(faint: true);
  }

  Widget _photo(int i) {
    final photo = widget.photos[i];
    return Semantics(
      button: true,
      label: i == 0
          ? 'Photo principale'
          : 'Photo ${i + 1} sur ${widget.photos.length}',
      excludeSemantics: true,
      onTap: widget.enabled ? () => _actions(i) : null,
      child: GestureDetector(
        onTap: widget.enabled ? () => _actions(i) : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, c) => ProductThumb(
                url: photo.url,
                bytes: photo.bytes,
                size: c.maxWidth,
              ),
            ),
            if (i == 0 && !widget.compact)
              Positioned(
                left: IviaSpacing.sm,
                bottom: IviaSpacing.sm,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IviaSpacing.md,
                    vertical: IviaSpacing.xs,
                  ),
                  decoration: ShapeDecoration(
                    color: IviaAppBrand.of(context).action,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    'Principale',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _addTile({required bool small}) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Ajouter une photo',
      excludeSemantics: true,
      onTap: widget.enabled ? _add : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(IviaRadius.button),
        onTap: widget.enabled ? _add : null,
        child: _DashedBox(
          // Réduit dans sa case avec une police très agrandie : le nom
          // reste lu par le lecteur d'écran.
          child: Padding(
            padding: const EdgeInsets.all(IviaSpacing.xs),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, color: IviaColors.text),
                  if (!widget.compact)
                    Text(
                      small ? 'Ajouter' : 'Ajouter une photo',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall,
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

/// Emplacement de photo à bordure en tirets.
class _DashedBox extends StatelessWidget {
  const _DashedBox({this.child, this.faint = false});

  final Widget? child;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedPainter(
        color: faint ? IviaColors.border : IviaColors.borderInput,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: faint ? null : IviaColors.surface,
          borderRadius: BorderRadius.circular(IviaRadius.button),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  const _DashedPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(IviaRadius.button),
    ).deflate(1);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final metric in (ui.Path()..addRRect(rect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.color != color;
}

/// Prix en FCFA, groupé par milliers pendant la saisie.
class PriceField extends StatelessWidget {
  const PriceField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return IviaFieldLabel(
      label: 'Prix',
      child: TextField(
        controller: controller,
        enabled: enabled,
        onChanged: onChanged,
        keyboardType: TextInputType.number,
        inputFormatters: [XofInputFormatter()],
        decoration: InputDecoration(
          hintText: '0',
          suffixText: 'FCFA',
          errorText: errorText,
          errorMaxLines: 3,
        ),
      ),
    );
  }
}

/// Catégorie de produits ; une sous-catégorie s'affiche « Parent › Enfant ».
class CategoryField extends ConsumerWidget {
  const CategoryField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(productCategoriesProvider);
    return IviaFieldLabel(
      label: 'Catégorie',
      child: switch (categories) {
        AsyncData(value: final all) => DropdownButtonFormField<String>(
          // Catégorie désactivée entre-temps : absente de la liste, à
          // choisir à nouveau.
          initialValue: all.any((c) => c.id == value) ? value : null,
          isExpanded: true,
          hint: const Text('Choisir'),
          decoration: InputDecoration(errorText: errorText, errorMaxLines: 3),
          items: [
            for (final c in all)
              DropdownMenuItem(
                value: c.id,
                child: Text(
                  categoryLabel(c, all),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: enabled
              ? (id) {
                  if (id != null) onChanged(id);
                }
              : null,
        ),
        AsyncError() => OutlinedButton(
          onPressed: () => ref.invalidate(productCategoriesProvider),
          child: const Text('Catégories : réessayer'),
        ),
        _ => const SizedBox(
          height: 54,
          child: Center(child: CircularProgressIndicator()),
        ),
      },
    );
  }
}

/// Libellé de la catégorie choisie, pour l'aperçu.
String? categoryNameOf(WidgetRef ref, String? id) {
  final all = ref.watch(productCategoriesProvider).value ?? const [];
  final c = all.where((c) => c.id == id).firstOrNull;
  return c == null ? null : categoryLabel(c, all);
}

/// Disponibilité vue par l'acheteur.
String availabilityLabel({required bool tracked, required int quantity}) =>
    !tracked
    ? 'Disponible'
    : quantity > 0
    ? 'En stock'
    : 'Épuisé';

/// Rappel : `ParcelSize` affiché « Colis moyen ».
String parcelChip(ParcelSize size) =>
    'Colis ${parcelLabel(size).toLowerCase()}';
