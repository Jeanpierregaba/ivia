import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../business/biz_ui.dart';
import 'catalog_labels.dart';
import 'catalog_providers.dart';
import 'media_sheet.dart';
import 'product_form.dart';
import 'product_sheets.dart';

/// Photos du produit : 1 à 5, la première est la principale. Vides : grande
/// carte « Ajouter des photos » ; sinon bande de vignettes à réordonner par
/// appui long et glisser. L'ajout ouvre la bibliothèque de la boutique.
class PhotosField extends ConsumerWidget {
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

  /// Vignettes plus petites (écran « Modifier »).
  final bool compact;

  Future<void> _add(BuildContext context) async {
    final picked = await showMediaSheet(context, current: photos);
    if (picked != null) onChanged(picked);
  }

  Future<void> _actions(BuildContext context, int index) async {
    final action = await showPhotoActions(context, isMain: index == 0);
    if (action == null) return;
    final next = [...photos];
    final photo = next.removeAt(index);
    if (action == PhotoAction.makeMain) next.insert(0, photo);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final count = photos.length;
    final size = compact ? 76.0 : 104.0;
    final error = errorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: Biz.medium,
          child: count == 0
              ? _EmptyMedia(
                  key: const ValueKey('empty'),
                  enabled: enabled,
                  error: error != null,
                  onTap: () => _add(context),
                )
              : SizedBox(
                  key: const ValueKey('strip'),
                  height: size + 8,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, _, animation) => ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.06).animate(animation),
                      child: Material(color: Colors.transparent, child: child),
                    ),
                    itemCount: count,
                    onReorderItem: (from, to) {
                      final next = [...photos];
                      final p = next.removeAt(from);
                      next.insert(to, p);
                      Biz.tick();
                      onChanged(next);
                    },
                    footer: count < maxPhotos
                        ? Padding(
                            padding: const EdgeInsets.only(left: 2, top: 4),
                            child: _AddTile(
                              size: size,
                              enabled: enabled,
                              onTap: () => _add(context),
                            ),
                          )
                        : null,
                    itemBuilder: (context, i) => Padding(
                      key: ObjectKey(photos[i]),
                      padding: const EdgeInsets.only(right: 10, top: 4),
                      child: ReorderableDelayedDragStartListener(
                        index: i,
                        enabled: enabled,
                        child: _PhotoTile(
                          photo: photos[i],
                          size: size,
                          main: i == 0,
                          label: i == 0
                              ? 'Photo principale'
                              : 'Photo ${i + 1} sur $count',
                          onTap: enabled ? () => _actions(context, i) : null,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        if (count > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${photosLabel(count)} · appui long pour réordonner',
              style: t.bodySmall?.copyWith(color: Biz.muted),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: t.bodySmall?.copyWith(color: IviaColors.error),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyMedia extends StatelessWidget {
  const _EmptyMedia({
    super.key,
    required this.enabled,
    required this.error,
    required this.onTap,
  });
  final bool enabled, error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      button: true,
      label: 'Ajouter une photo',
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: BizCard(
        onTap: enabled ? onTap : null,
        border: error ? IviaColors.error : null,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Grande police : tout l'espace pour le texte.
            if (MediaQuery.textScalerOf(context).scale(10) <= 13) ...[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Biz.page,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.add_photo_alternate_outlined,
                  color: Biz.navy,
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ajouter des photos',
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Bibliothèque ou appareil photo · $maxPhotos au plus',
                    style: t.bodySmall?.copyWith(color: Biz.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Biz.muted),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.size,
    required this.enabled,
    required this.onTap,
  });
  final double size;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: 'Ajouter une photo',
    excludeSemantics: true,
    onTap: enabled ? onTap : null,
    child: BizPressable(
      onTap: enabled ? onTap : null,
      scale: 0.92,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: IviaColors.borderInput, width: 1.4),
        ),
        child: const Icon(Icons.add_rounded, color: Biz.navy, size: 30),
      ),
    ),
  );
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.size,
    required this.main,
    required this.label,
    required this.onTap,
  });
  final EditorPhoto photo;
  final double size;
  final bool main;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: BizPressable(
      onTap: onTap,
      scale: 0.94,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: main ? Border.all(color: Biz.navy, width: 2.5) : null,
              ),
              padding: EdgeInsets.all(main ? 2 : 0),
              child: ProductThumb(
                url: photo.url,
                bytes: photo.bytes,
                size: size,
              ),
            ),
            if (main)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Biz.navy,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Principale',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
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
