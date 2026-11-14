import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';
import '../business/biz_ui.dart';
import 'catalog_actions.dart';
import 'catalog_providers.dart';
import 'catalog_screen.dart' show showCategorySheet;
import 'product_fields.dart';
import 'product_form.dart';
import 'product_preview.dart';
import 'product_sheets.dart';

/// Création d'un produit, ou reprise d'un brouillon ([productId]), sur une
/// seule page : photos, informations, statut, prix et catégorie, livraison
/// et stock. Barre fixe : Annuler, Publier (ou Enregistrer le brouillon).
/// Jauge de complétude en haut, aperçu acheteur à tout moment.
class ProductEditorScreen extends ConsumerStatefulWidget {
  const ProductEditorScreen({super.key, this.productId});

  final String? productId;

  @override
  ConsumerState<ProductEditorScreen> createState() =>
      _ProductEditorScreenState();
}

enum _Busy { none, draft, publish }

/// Section du formulaire (pour y ramener sur une erreur).
enum _Part { photos, details, price, delivery }

class _ProductEditorScreenState extends ConsumerState<ProductEditorScreen> {
  ProductForm? _form;
  Object? _loadError;

  var _errors = <String, String>{};
  String? _generalError;
  var _busy = _Busy.none;
  var _dirty = false;

  /// Statut choisi : en vente (publier) ou brouillon.
  var _publish = true;
  final _scroll = ScrollController();
  final _keys = {for (final p in _Part.values) p: GlobalKey()};

  @override
  void initState() {
    super.initState();
    // Message du catalogue (« Brouillon enregistré »…) : il masquerait les
    // boutons du formulaire.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    });
    if (widget.productId == null) {
      _form = ProductForm();
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final product = await ref
          .read(apiClientProvider)
          .sellerProduct(widget.productId!);
      if (!mounted) return;
      // Lien vers un produit qui n'est plus un brouillon (liste périmée,
      // autre téléphone) : « Modifier », pour ne pas le retirer par erreur.
      if (product.status != ProductStatus.draft) {
        context.pushReplacement(Routes.productEdit(product.id));
        return;
      }
      setState(() => _form = ProductForm.fromProduct(product));
    } on Exception catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    _form?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _isBusy => _busy != _Busy.none;

  void _changed([String? field]) {
    _dirty = true;
    setState(() {
      if (field != null) _errors = {..._errors}..remove(field);
      _generalError = null;
    });
  }

  /// Catégories actives chargées ; `null` : pas encore connues.
  Set<String>? get _categoryIds =>
      switch (ref.read(productCategoriesProvider).value) {
        final all? => {for (final c in all) c.id},
        null => null,
      };

  _Part _partOf(String field) => switch (field) {
    'image_keys' => _Part.photos,
    'name' || 'description' => _Part.details,
    'price_xof' || 'category_id' => _Part.price,
    _ => _Part.delivery,
  };

  /// Amène la première section en erreur à l'écran.
  void _reveal(Iterable<String> fields) {
    if (fields.isEmpty) return;
    final first = fields
        .map(_partOf)
        .reduce((a, b) => a.index < b.index ? a : b);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[first]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: Biz.medium,
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
      }
    });
  }

  Map<String, String> _validate({required bool publish}) {
    final form = _form!;
    return {
      ...form.validateDetails(categoryIds: _categoryIds),
      ...form.validateDelivery(),
      if (publish && form.photos.isEmpty) 'image_keys': noPhotoMessage,
    };
  }

  Future<void> _save() async {
    if (_isBusy) return;
    final publish = _publish;
    final form = _form!;
    final errors = _validate(publish: publish);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      _reveal(errors.keys);
      return;
    }
    final shopId = ref.read(sellerShopProvider).value?.id;
    if (shopId == null) return;
    setState(() {
      _busy = publish ? _Busy.publish : _Busy.draft;
      _generalError = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final product = await form.save(
        ref.read(apiClientProvider),
        shopId: shopId,
        active: publish,
      );
      if (!mounted) return;
      _dirty = false;
      refreshCatalog(container);
      final tab = ref.read(catalogTabProvider.notifier);
      if (publish) {
        tab.select(ProductStatus.active);
        context.go(Routes.productPublished, extra: product);
      } else {
        tab.select(ProductStatus.draft);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Brouillon enregistré : ${product.name}')),
        );
        context.go(Routes.catalog);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      final fields = e.fields;
      if (fields.containsKey('category_id')) {
        ref.invalidate(productCategoriesProvider);
      }
      // Erreur sans champ affiché : message général au-dessus des boutons.
      setState(() {
        _errors = fields;
        if (!fields.keys.any(shownFields.contains)) {
          _generalError = catalogErrorMessage(container, e);
        }
      });
      _reveal(fields.keys.where(shownFields.contains));
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _generalError = catalogErrorMessage(container, e));
      }
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  Future<void> _back() async {
    if (_isBusy) return;
    if (_dirty && !await _confirmLeave()) return;
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.catalog);
    }
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          widget.productId == null
              ? 'Abandonner ce produit ?'
              : 'Abandonner les changements ?',
        ),
        content: const Text('Ce que vous avez saisi ne sera pas enregistré.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: IviaColors.error),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _chooseCategory(ProductForm form) async {
    final all = ref.read(productCategoriesProvider).value;
    if (all == null) {
      ref.invalidate(productCategoriesProvider);
      return;
    }
    final id = await showCategorySheet(
      context,
      categories: all,
      selected: form.categoryId,
    );
    if (id == null || id.isEmpty || !mounted) return;
    form.categoryId = id;
    _changed('category_id');
  }

  void _preview(ProductForm form) {
    final shop = ref.read(sellerShopProvider).value;
    final category = categoryNameOf(ref, form.categoryId);
    showBizSheet<void>(
      context,
      title: 'Aperçu acheteur',
      expand: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProductPreviewCard(
              photos: form.photos,
              name: form.name.text.trim().isEmpty
                  ? 'Nom du produit'
                  : form.name.text.trim(),
              price: formatXof(parseXof(form.price.text) ?? 0),
              shopLine: [
                ?shop?.name,
                if (shop?.neighborhoodName case final n? when n.isNotEmpty) n,
              ].join(' · '),
              availability: availabilityLabel(
                tracked: form.tracked,
                quantity: form.quantity,
              ),
              chips: [
                ?category,
                if (form.parcelSize case final s?) parcelChip(s),
              ],
              description: form.description.text.trim(),
            ),
            const SizedBox(height: 16),
            for (final check in form.checks()) PreviewCheck(check),
          ],
        ),
      ),
    );
  }

  /// Éléments prêts sur 5 : photo, nom, prix, catégorie, colis.
  int _ready(ProductForm form) {
    final n = form.name.text.trim().length;
    final price = parseXof(form.price.text) ?? 0;
    return [
      form.photos.isNotEmpty,
      n >= 2 && n <= 150,
      price >= 1,
      form.categoryId != null,
      form.parcelSize != null,
    ].where((v) => v).length;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final form = _form;
    final title = widget.productId == null ? 'Nouveau produit' : 'Brouillon';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Biz.page,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IviaBackButton(onPressed: _isBusy ? null : _back),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // Barre fixe : titre borné à 150 % (lu en entier).
                          textScaler: MediaQuery.textScalerOf(context)
                              .clamp(maxScaleFactor: 1.5),
                          style: t.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Biz.navy,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Aperçu',
                      onPressed: form == null ? null : () => _preview(form),
                      icon: const Icon(
                        Icons.visibility_outlined,
                        color: Biz.navy,
                      ),
                    ),
                  ],
                ),
              ),
              if (form != null) _Progress(ready: _ready(form), total: 5),
              Expanded(
                child: form == null
                    ? _loading()
                    // Colonne entière (pas de liste paresseuse) : une
                    // section en erreur est toujours atteignable.
                    : SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (i, w) in _sections(form).indexed)
                              BizReveal(index: i, child: w),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: form == null ? null : _bottomBar(),
      ),
    );
  }

  Widget _bottomBar() => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Biz.line)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_generalError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _generalError!,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: IviaColors.error),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: BizButton(
                  outlined: true,
                  label: 'Annuler',
                  onPressed: _isBusy ? null : _back,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: BizButton(
                  color: _publish ? Biz.red : Biz.navy,
                  busy: _isBusy,
                  icon: _publish
                      ? Icons.rocket_launch_outlined
                      : Icons.save_outlined,
                  label: _publish ? 'Publier' : 'Enregistrer',
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _loading() {
    if (_loadError case final error?) {
      return BizEmpty(
        icon: Icons.cloud_off_rounded,
        color: Biz.red,
        title: catalogErrorMessage(
          ProviderScope.containerOf(context, listen: false),
          error,
        ),
        action: BizButton(outlined: true, label: 'Réessayer', onPressed: _load),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  List<Widget> _sections(ProductForm form) {
    final enabled = !_isBusy;
    final category = categoryNameOf(ref, form.categoryId);
    return [
      _Section(
        key: _keys[_Part.photos],
        title: 'Photos',
        child: PhotosField(
          photos: form.photos,
          enabled: enabled,
          errorText: _errors['image_keys'],
          onChanged: (photos) {
            form.photos = photos;
            _changed('image_keys');
          },
        ),
      ),
      _Section(
        key: _keys[_Part.details],
        title: 'Informations',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IviaFieldLabel(
              label: 'Nom du produit',
              child: TextField(
                controller: form.name,
                enabled: enabled,
                onChanged: (_) => _changed('name'),
                maxLength: 150,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: 'Riz parfumé 5 kg',
                  counterText: '',
                  errorText: _errors['name'],
                  errorMaxLines: 2,
                ),
              ),
            ),
            const SizedBox(height: 14),
            DescriptionField(
              controller: form.description,
              enabled: enabled,
              onChanged: (_) => _changed('description'),
            ),
          ],
        ),
      ),
      _Section(
        title: 'Statut',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StatusChoice(
                label: 'En vente',
                hint: 'Visible dès la publication',
                selected: _publish,
                onTap: enabled ? () => setState(() => _publish = true) : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatusChoice(
                label: 'Brouillon',
                hint: 'À terminer plus tard',
                selected: !_publish,
                onTap: enabled ? () => setState(() => _publish = false) : null,
              ),
            ),
          ],
        ),
      ),
      _Section(
        key: _keys[_Part.price],
        title: 'Prix et catégorie',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PriceField(
              controller: form.price,
              enabled: enabled,
              errorText: _errors['price_xof'],
              onChanged: (_) => _changed('price_xof'),
            ),
            const SizedBox(height: 14),
            _AddRow(
              icon: Icons.grid_view_rounded,
              title: 'Catégorie',
              value: category,
              placeholder: 'Où les acheteurs le trouveront',
              errorText: _errors['category_id'],
              onTap: enabled ? () => _chooseCategory(form) : null,
            ),
          ],
        ),
      ),
      _Section(
        key: _keys[_Part.delivery],
        title: 'Livraison et stock',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ParcelSizePicker(
              value: form.parcelSize,
              errorText: _errors['parcel_size'],
              onChanged: enabled
                  ? (size) {
                      form.parcelSize = size;
                      _changed('parcel_size');
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            StockCard(
              tracked: form.tracked,
              quantity: form.quantity,
              locked: form.stockModeLocked,
              enabled: enabled,
              errorText: _errors['stock_quantity'],
              onTracked: (v) {
                form.tracked = v;
                _changed();
              },
              onQuantity: (v) {
                form.quantity = v;
                _changed('stock_quantity');
              },
            ),
            const SizedBox(height: 8),
            Text(
              form.stockModeLocked
                  ? "Le mode de stock ne change plus après l'enregistrement : "
                        'des commandes peuvent réserver la quantité.'
                  : 'Désactivé : vous confirmez la disponibilité à chaque '
                        'commande.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Biz.muted),
            ),
          ],
        ),
      ),
    ];
  }
}

/// Jauge de complétude : « 3 sur 5 prêts ».
class _Progress extends StatelessWidget {
  const _Progress({required this.ready, required this.total});
  final int ready, total;

  @override
  Widget build(BuildContext context) {
    final done = ready == total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: ready / total),
                duration: Biz.medium,
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: Biz.line,
                  color: done ? Biz.green : Biz.blue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: Biz.fast,
            child: Text(
              done ? 'Prêt' : '$ready sur $total',
              key: ValueKey(ready),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: done ? Biz.green : Biz.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: BizCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800, color: Biz.navy),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _StatusChoice extends StatelessWidget {
  const _StatusChoice({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });
  final String label, hint;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '$label, $hint',
      excludeSemantics: true,
      onTap: onTap,
      child: BizPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Biz.medium,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF2F6FC) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? Biz.navy : Biz.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: Biz.fast,
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Biz.blue : Biz.line,
                    width: selected ? 6 : 2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(hint, style: t.bodySmall?.copyWith(color: Biz.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne « Catégorie · + Ajouter » ; valeur choisie et « Modifier » ensuite.
class _AddRow extends StatelessWidget {
  const _AddRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.errorText,
  });
  final IconData icon;
  final String title;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final error = errorText;
    final big = MediaQuery.textScalerOf(context).scale(10) > 13;
    final action = Text(
      value == null ? '+ Ajouter' : 'Modifier',
      style: t.labelLarge?.copyWith(
        color: Biz.blue,
        fontWeight: FontWeight.w800,
        decoration: TextDecoration.underline,
        decorationColor: Biz.blue,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          button: true,
          label: value == null ? '$title, à ajouter' : '$title, $value',
          excludeSemantics: true,
          onTap: onTap,
          child: BizPressable(
            onTap: onTap,
            child: AnimatedContainer(
              duration: Biz.medium,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Biz.page,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: error != null ? IviaColors.error : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  // Grande police : place au texte, l'action passe dessous.
                  if (!big) ...[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: Biz.navy, size: 20),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: Biz.fast,
                          child: Text(
                            value ?? placeholder,
                            key: ValueKey(value),
                            style: t.bodySmall?.copyWith(
                              color: value == null ? Biz.muted : Biz.navy,
                              fontWeight: value == null
                                  ? FontWeight.w400
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (big) action,
                      ],
                    ),
                  ),
                  if (!big) ...[const SizedBox(width: 8), action],
                ],
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
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

/// « Suivre le stock » et « Quantité disponible ».
class StockCard extends StatelessWidget {
  const StockCard({
    super.key,
    required this.tracked,
    required this.quantity,
    required this.locked,
    required this.enabled,
    required this.onTracked,
    required this.onQuantity,
    this.errorText,
  });

  final bool tracked;
  final int quantity;

  /// Mode déjà enregistré : il ne change plus.
  final bool locked;
  final bool enabled;
  final ValueChanged<bool> onTracked;
  final ValueChanged<int> onQuantity;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(IviaSpacing.xl),
      decoration: BoxDecoration(
        color: IviaColors.surface,
        borderRadius: BorderRadius.circular(IviaRadius.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Suivre le stock', style: textTheme.titleMedium),
                      Text(
                        'La quantité baisse à chaque commande. Impossible de '
                        'vendre plus que le stock.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: IviaColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: IviaSpacing.md),
                Switch(
                  value: tracked,
                  onChanged: enabled && !locked ? onTracked : null,
                ),
              ],
            ),
          ),
          if (tracked) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: IviaSpacing.lg),
              child: Divider(),
            ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: IviaSpacing.sm,
              children: [
                Text('Quantité disponible', style: textTheme.titleMedium),
                IviaQuantityStepper(
                  label: 'Quantité disponible',
                  value: quantity,
                  enabled: enabled,
                  onChanged: onQuantity,
                ),
              ],
            ),
            if (errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: IviaSpacing.xs),
                child: Text(
                  errorText!,
                  style: textTheme.bodySmall?.copyWith(color: IviaColors.error),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
