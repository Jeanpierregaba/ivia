import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';
import 'catalog_actions.dart';
import 'catalog_providers.dart';
import 'product_fields.dart';
import 'product_form.dart';
import 'product_preview.dart';
import 'product_sheets.dart';

/// Création d'un produit, ou reprise d'un brouillon ([productId]) :
/// étape 1 (photos, nom, prix, catégorie, description), étape 2 (colis,
/// stock), puis aperçu et publication.
class ProductEditorScreen extends ConsumerStatefulWidget {
  const ProductEditorScreen({super.key, this.productId});

  final String? productId;

  @override
  ConsumerState<ProductEditorScreen> createState() =>
      _ProductEditorScreenState();
}

enum _Busy { none, draft, publish }

class _ProductEditorScreenState extends ConsumerState<ProductEditorScreen> {
  ProductForm? _form;
  Object? _loadError;

  /// 0 : détails ; 1 : livraison et stock ; 2 : aperçu.
  var _step = 0;
  var _errors = <String, String>{};
  String? _generalError;
  var _busy = _Busy.none;
  var _dirty = false;
  final _scroll = ScrollController();

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
    if (field != null && _errors.containsKey(field)) {
      setState(() => _errors = {..._errors}..remove(field));
    }
  }

  void _goTo(int step) {
    setState(() {
      _step = step;
      _generalError = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Catégories actives chargées ; `null` : pas encore connues.
  Set<String>? get _categoryIds =>
      switch (ref.read(productCategoriesProvider).value) {
        final all? => {for (final c in all) c.id},
        null => null,
      };

  void _continue() {
    final errors = _form!.validateDetails(categoryIds: _categoryIds);
    setState(() => _errors = errors);
    if (errors.isEmpty) _goTo(1);
  }

  void _preview() {
    final form = _form!;
    final errors = form.validateDelivery();
    setState(() {
      _errors = errors;
      _generalError = errors.isEmpty ? photosMissing(form) : null;
    });
    if (errors.isEmpty && _generalError == null) _goTo(2);
  }

  Future<void> _save({required bool publish}) async {
    if (_isBusy) return;
    final form = _form!;
    final errors = {
      ...form.validateDetails(categoryIds: _categoryIds),
      ...form.validateDelivery(),
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      _goTo(errors.keys.any(detailFields.contains) ? 0 : 1);
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
      if (fields.keys.any(detailFields.contains)) {
        _goTo(0);
      } else if (fields.keys.any(shownFields.contains)) {
        _goTo(1);
      }
      // Erreur sans champ affiché : message général sur l'étape en cours.
      setState(() {
        _errors = fields;
        if (!fields.keys.any(shownFields.contains)) {
          _generalError = catalogErrorMessage(container, e);
        }
      });
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
    if (_step > 0) {
      _goTo(_step - 1);
      return;
    }
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
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final form = _form;
    final title = _step == 2
        ? 'Aperçu'
        : widget.productId == null
        ? 'Nouveau produit'
        : 'Brouillon';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(IviaSpacing.screen),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IviaBackButton(onPressed: _isBusy ? null : _back),
                    const SizedBox(width: IviaSpacing.sm),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge,
                        ),
                      ),
                    ),
                    const SizedBox(width: IviaSpacing.sm),
                    if (_step < 2)
                      IviaPill(label: '${_step + 1} sur 2')
                    else
                      const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: IviaSpacing.xl),
                if (form == null)
                  _loading()
                else
                  ...switch (_step) {
                    0 => _details(form),
                    1 => _delivery(form),
                    _ => _previewStep(form),
                  },
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _loading() {
    if (_loadError case final error?) {
      return Column(
        children: [
          Text(
            catalogErrorMessage(
              ProviderScope.containerOf(context, listen: false),
              error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: IviaSpacing.lg),
          OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
        ],
      );
    }
    return const Padding(
      padding: EdgeInsets.all(IviaSpacing.huge),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _generalErrorText() => Padding(
    padding: const EdgeInsets.only(bottom: IviaSpacing.md),
    child: Semantics(
      liveRegion: true,
      child: Text(
        _generalError!,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: IviaColors.error),
      ),
    ),
  );

  List<Widget> _details(ProductForm form) {
    final enabled = !_isBusy;
    return [
      PhotosField(
        photos: form.photos,
        enabled: enabled,
        errorText: _errors['image_keys'],
        onChanged: (photos) {
          setState(() {
            form.photos = photos;
            _generalError = null;
          });
          _changed('image_keys');
        },
      ),
      const SizedBox(height: IviaSpacing.xl),
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
      const SizedBox(height: IviaSpacing.lg),
      SideBySide(
        start: PriceField(
          controller: form.price,
          enabled: enabled,
          errorText: _errors['price_xof'],
          onChanged: (_) => _changed('price_xof'),
        ),
        end: CategoryField(
          value: form.categoryId,
          enabled: enabled,
          errorText: _errors['category_id'],
          onChanged: (id) {
            setState(() => form.categoryId = id);
            _changed('category_id');
          },
        ),
      ),
      const SizedBox(height: IviaSpacing.lg),
      DescriptionField(
        controller: form.description,
        enabled: enabled,
        onChanged: (_) => _changed('description'),
      ),
      const SizedBox(height: IviaSpacing.xl),
      if (_generalError != null) _generalErrorText(),
      FilledButton(onPressed: _continue, child: const Text('Continuer')),
    ];
  }

  List<Widget> _delivery(ProductForm form) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = !_isBusy;
    return [
      Semantics(
        header: true,
        child: Text('Livraison et stock', style: textTheme.headlineMedium),
      ),
      const SizedBox(height: IviaSpacing.xl),
      ParcelSizePicker(
        value: form.parcelSize,
        errorText: _errors['parcel_size'],
        onChanged: enabled
            ? (size) {
                setState(() => form.parcelSize = size);
                _changed('parcel_size');
              }
            : null,
      ),
      const SizedBox(height: IviaSpacing.xl),
      Semantics(
        header: true,
        child: Text('Stock', style: textTheme.labelLarge),
      ),
      const SizedBox(height: IviaSpacing.sm),
      StockCard(
        tracked: form.tracked,
        quantity: form.quantity,
        locked: form.stockModeLocked,
        enabled: enabled,
        errorText: _errors['stock_quantity'],
        onTracked: (v) {
          setState(() => form.tracked = v);
          _changed();
        },
        onQuantity: (v) {
          setState(() => form.quantity = v);
          _changed('stock_quantity');
        },
      ),
      const SizedBox(height: IviaSpacing.sm),
      Text(
        form.stockModeLocked
            ? "Le mode de stock ne change plus après l'enregistrement : des "
                  'commandes peuvent réserver la quantité.'
            : 'Désactivé : vous confirmez la disponibilité à chaque commande.',
        style: textTheme.bodySmall,
      ),
      const SizedBox(height: IviaSpacing.xxl),
      if (_generalError != null) _generalErrorText(),
      SideBySide(
        crossAxisAlignment: CrossAxisAlignment.center,
        start: OutlinedButton(
          onPressed: enabled ? () => _save(publish: false) : null,
          child: _busy == _Busy.draft
              ? const ButtonProgress()
              : const Text('Brouillon'),
        ),
        end: FilledButton(
          onPressed: enabled ? _preview : null,
          child: const Text("Voir l'aperçu"),
        ),
      ),
    ];
  }

  List<Widget> _previewStep(ProductForm form) {
    final textTheme = Theme.of(context).textTheme;
    final shop = ref.watch(sellerShopProvider).value;
    final category = categoryNameOf(ref, form.categoryId);
    return [
      Text(
        'Voici votre produit tel que les acheteurs le verront.',
        style: textTheme.bodyLarge?.copyWith(color: IviaColors.textSecondary),
      ),
      const SizedBox(height: IviaSpacing.lg),
      ProductPreviewCard(
        photos: form.photos,
        name: form.name.text.trim(),
        price: formatXof(parseXof(form.price.text) ?? 0),
        shopLine: [
          ?shop?.name,
          if (shop?.neighborhoodName case final n? when n.isNotEmpty) n,
        ].join(' · '),
        availability: availabilityLabel(
          tracked: form.tracked,
          quantity: form.quantity,
        ),
        chips: [?category, parcelChip(form.parcelSize!)],
        description: form.description.text.trim(),
      ),
      const SizedBox(height: IviaSpacing.xl),
      for (final check in form.checks()) PreviewCheck(check),
      const SizedBox(height: IviaSpacing.xl),
      if (_generalError != null) _generalErrorText(),
      FilledButton(
        onPressed: _isBusy ? null : () => _save(publish: true),
        child: _busy == _Busy.publish
            ? const ButtonProgress()
            : const Text('Publier'),
      ),
      const SizedBox(height: IviaSpacing.sm),
      TextButton(
        onPressed: _isBusy ? null : () => _goTo(0),
        child: const Text('Modifier'),
      ),
    ];
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
