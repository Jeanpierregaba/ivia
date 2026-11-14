import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../business/biz_ui.dart';
import 'catalog_providers.dart';
import 'product_form.dart';
import 'product_sheets.dart';

/// « Ajouter des photos » : bibliothèque de la boutique (photos déjà
/// utilisées, à réutiliser) ou nouvelle photo (appareil, galerie). Sélection
/// multiple numérotée dans l'ordre : la 1re sera la photo principale.
/// Renvoie la nouvelle liste ; `null` : annulé.
Future<List<EditorPhoto>?> showMediaSheet(
  BuildContext context, {
  required List<EditorPhoto> current,
  int max = maxPhotos,
}) => showBizSheet<List<EditorPhoto>>(
  context,
  title: 'Ajouter des photos',
  expand: true,
  builder: (context) => _MediaPicker(current: current, max: max),
);

class _MediaPicker extends ConsumerStatefulWidget {
  const _MediaPicker({required this.current, required this.max});
  final List<EditorPhoto> current;
  final int max;

  @override
  ConsumerState<_MediaPicker> createState() => _MediaPickerState();
}

class _MediaPickerState extends ConsumerState<_MediaPicker> {
  late final _picked = [...widget.current];

  /// 0 : bibliothèque ; 1 : importer. `null` : choisi à l'arrivée de la
  /// bibliothèque (vide : importer).
  int? _tab;
  String? _error;
  var _picking = false;

  int _indexOf(ProductImage m) =>
      _picked.indexWhere((p) => p.key == m.objectKey);

  void _toggle(ProductImage m) {
    final i = _indexOf(m);
    setState(() {
      _error = null;
      if (i >= 0) {
        _picked.removeAt(i);
      } else if (_picked.length >= widget.max) {
        _error = '${widget.max} photos au plus.';
      } else {
        _picked.add(EditorPhoto.remote(m));
      }
    });
  }

  Future<void> _import(PhotoSource source) async {
    if (_picking) return;
    if (_picked.length >= widget.max) {
      setState(() => _error = '${widget.max} photos au plus.');
      return;
    }
    setState(() => _picking = true);
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
      setState(() {
        _error = null;
        _picked.add(EditorPhoto.local(bytes));
      });
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Photo impossible à utiliser. Vérifiez les autorisations '
              "de l'appareil photo et des photos.",
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final media = ref.watch(shopMediaProvider);
    final library = media.value ?? const <ProductImage>[];
    final tab = _tab ?? (media.isLoading ? 0 : (library.isEmpty ? 1 : 0));
    final header = [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Tab(
              label: 'Bibliothèque',
              selected: tab == 0,
              onTap: () => setState(() => _tab = 0),
            ),
            _Tab(
              label: 'Importer',
              selected: tab == 1,
              onTap: () => setState(() => _tab = 1),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        // Grande police : « Tout désélectionner » passe à la ligne.
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Sélectionnées',
                    style: t.titleSmall?.copyWith(color: Biz.muted),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: Biz.fast,
                  transitionBuilder: (child, a) =>
                      ScaleTransition(scale: a, child: child),
                  child: Container(
                    key: ValueKey(_picked.length),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Biz.page,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_picked.length}/${widget.max}',
                      style: t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: Biz.tabular,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_picked.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  _picked.clear();
                  _error = null;
                }),
                child: const Text(
                  'Tout désélectionner',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
              ),
          ],
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Semantics(
            liveRegion: true,
            child: Text(_error!, style: t.bodySmall?.copyWith(color: Biz.red)),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tout défile (petit écran, grande police) ; seuls les boutons
        // restent fixes.
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverList.list(children: header),
              ...tab == 0 ? _library(media, library) : _importer(context),
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Biz.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: BizButton(
                    outlined: true,
                    label: 'Annuler',
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BizButton(
                    color: Biz.red,
                    label: 'Valider',
                    onPressed: () => Navigator.pop(context, _picked),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _library(
    AsyncValue<List<ProductImage>> media,
    List<ProductImage> library,
  ) {
    const grid = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 140,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
    );
    if (media.isLoading && media.value == null) {
      return [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid.builder(
            gridDelegate: grid,
            itemCount: 6,
            itemBuilder: (_, _) =>
                const BizSkeleton(height: double.infinity, radius: 16),
          ),
        ),
      ];
    }
    if (library.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: BizEmpty(
            icon: Icons.photo_library_outlined,
            title: media.hasError
                ? 'Bibliothèque indisponible'
                : 'Votre bibliothèque est vide',
            body: media.hasError
                ? 'Vérifiez votre connexion, ou importez une photo.'
                : 'Les photos de vos produits apparaîtront ici, prêtes à être '
                      'réutilisées.',
            action: BizButton(
              outlined: true,
              icon: Icons.add_a_photo_outlined,
              label: 'Importer une photo',
              onPressed: () => setState(() => _tab = 1),
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid.builder(
          gridDelegate: grid,
          itemCount: library.length,
          itemBuilder: (context, i) {
            final m = library[i];
            final order = _indexOf(m);
            return BizReveal(
              index: i % 12,
              child: Semantics(
                container: true,
                button: true,
                selected: order >= 0,
                label: order >= 0
                    ? 'Photo ${i + 1} de la bibliothèque, choisie en '
                          '${order + 1}'
                    : 'Photo ${i + 1} de la bibliothèque',
                excludeSemantics: true,
                onTap: () => _toggle(m),
                child: _SelectableImage(
                  url: m.url,
                  order: order,
                  onTap: () => _toggle(m),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _importer(BuildContext context) {
    final added = [
      for (final (i, p) in _picked.indexed)
        if (p.bytes != null) (i, p),
    ];
    return [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList.list(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _SourceTile(
                    icon: Icons.photo_camera_outlined,
                    label: 'Prendre une photo',
                    busy: _picking,
                    onTap: () => _import(PhotoSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceTile(
                    icon: Icons.photo_library_outlined,
                    label: 'Choisir une photo',
                    busy: _picking,
                    onTap: () => _import(PhotoSource.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Conseil : lumière du jour, fond uni, produit centré. La 1re '
              'photo est la principale.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Biz.muted),
            ),
            if (added.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (i, p) in added)
                    SizedBox.square(
                      dimension: 96,
                      child: _SelectableImage(
                        bytes: p,
                        order: i,
                        onTap: () => setState(() => _picked.remove(p)),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ];
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: BizPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Biz.medium,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Biz.navy : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Biz.navy : Biz.line),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? Colors.white : Biz.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => BizCard(
    color: Biz.page,
    onTap: busy ? null : onTap,
    padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
    child: Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Biz.navy),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

/// Photo cochable : numéro d'ordre dans la sélection, filet bleu nuit.
class _SelectableImage extends StatelessWidget {
  const _SelectableImage({
    this.url,
    this.bytes,
    required this.order,
    required this.onTap,
  });
  final String? url;
  final EditorPhoto? bytes;
  final int order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = order >= 0;
    return BizPressable(
      onTap: onTap,
      scale: 0.94,
      child: AnimatedContainer(
        duration: Biz.fast,
        decoration: BoxDecoration(
          color: Biz.page,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: on ? Biz.navy : Colors.transparent,
            width: 2.5,
          ),
        ),
        padding: const EdgeInsets.all(3),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (_, c) =>
                  ProductThumb(url: url, bytes: bytes?.bytes, size: c.maxWidth),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: AnimatedContainer(
                duration: Biz.fast,
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? Biz.blue : Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: on ? Biz.blue : Biz.line,
                    width: 1.5,
                  ),
                ),
                child: on
                    ? Text(
                        '${order + 1}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
