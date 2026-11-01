import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/router.dart';
import '../../app/seller_shop.dart';
import 'catalog_actions.dart';
import 'catalog_labels.dart';
import 'catalog_providers.dart';
import 'product_fields.dart';
import 'product_form.dart';
import 'product_preview.dart';
import 'product_sheets.dart';

/// « Modifier » un produit en vente ou retiré.
class ProductEditScreen extends ConsumerStatefulWidget {
  const ProductEditScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends ConsumerState<ProductEditScreen> {
  Product? _product;
  ProductForm? _form;
  Object? _loadError;

  /// État voulu (interrupteur), effectif à l'enregistrement.
  var _active = false;
  var _errors = <String, String>{};
  String? _generalError;
  var _busy = false;
  var _dirty = false;

  @override
  void initState() {
    super.initState();
    // Message du catalogue (« Brouillon enregistré »…) : il masquerait les
    // boutons du formulaire.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final product = await ref
          .read(apiClientProvider)
          .sellerProduct(widget.productId);
      if (!mounted) return;
      setState(() {
        _product = product;
        _form?.dispose();
        _form = ProductForm.fromProduct(product);
        _active = product.status == ProductStatus.active;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    _form?.dispose();
    super.dispose();
  }

  void _changed([String? field]) {
    _dirty = true;
    setState(() {
      _generalError = null;
      if (field != null) _errors = {..._errors}..remove(field);
    });
  }

  Future<void> _save() async {
    final form = _form!;
    if (_busy) return;
    final errors = form.validateDetails();
    final missing = _active ? photosMissing(form) : null;
    setState(() {
      _errors = errors;
      _generalError = missing;
    });
    if (errors.isNotEmpty || missing != null) return;
    final shopId = ref.read(sellerShopProvider).value?.id;
    if (shopId == null) return;
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await form.save(
        ref.read(apiClientProvider),
        shopId: shopId,
        active: _active,
      );
      if (!mounted) return;
      _dirty = false;
      refreshCatalog(container);
      messenger.showSnackBar(
        const SnackBar(content: Text('Modifications enregistrées')),
      );
      _leave();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errors = e.fields;
          if (e.fields.isEmpty) {
            _generalError = catalogErrorMessage(container, e);
          }
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _generalError = catalogErrorMessage(container, e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.catalog);
    }
  }

  Future<void> _back() async {
    if (_busy) return;
    if (_dirty) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Abandonner les changements ?'),
          content: const Text('Vos modifications ne seront pas enregistrées.'),
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
      if (leave != true) return;
    }
    if (mounted) _leave();
  }

  Future<void> _withdraw() async {
    final product = _product;
    if (product == null || _busy) return;
    await CatalogActions.of(context).withdraw(context, product);
  }

  Future<void> _editDescription(ProductForm form) async {
    final text = await showDescriptionSheet(context, form.description.text);
    if (text == null || text == form.description.text) return;
    form.description.text = text;
    _changed('description');
  }

  Future<void> _editParcel(ProductForm form) async {
    final size = await showParcelSheet(context, form.parcelSize!);
    if (size == null || size == form.parcelSize) return;
    form.parcelSize = size;
    _changed('parcel_size');
  }

  Future<void> _editStock(ProductForm form) async {
    if (!form.tracked) {
      await showUntrackedStockSheet(context);
      return;
    }
    final quantity = await showStockSheet(context, initial: form.quantity);
    if (quantity == null || quantity == form.quantity) return;
    form.quantity = quantity;
    _changed('stock_quantity');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final form = _form;
    final product = _product;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(IviaSpacing.screen),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IviaBackButton(onPressed: _busy ? null : _back),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Modifier',
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: IviaSpacing.xl),
                if (form == null || product == null)
                  _loading()
                else
                  ..._fields(form, product),
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

  List<Widget> _fields(ProductForm form, Product product) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = !_busy;
    final since = switch (product.status) {
      ProductStatus.active => product.publishedAt,
      _ => product.withdrawnAt,
    };
    final wasActive = product.status == ProductStatus.active;
    final stateText = _active == wasActive
        ? (wasActive
              ? 'Visible par les acheteurs depuis ${since == null ? 'sa publication' : shortDate(since)}.'
              : 'Non visible depuis ${since == null ? 'son retrait' : shortDate(since)}.')
        : (_active
              ? 'Sera remis en vente à l’enregistrement.'
              : 'Sera retiré de la vente à l’enregistrement.');
    return [
      Container(
        padding: const EdgeInsets.all(IviaSpacing.lg),
        decoration: BoxDecoration(
          color: IviaColors.surface,
          borderRadius: BorderRadius.circular(IviaRadius.large),
        ),
        child: MergeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _active
                                ? IviaColors.cobaltBlue
                                : IviaColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: IviaSpacing.sm),
                        Flexible(
                          child: Text(
                            _active ? 'En vente' : 'Retiré',
                            style: textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      stateText,
                      style: textTheme.bodyMedium?.copyWith(
                        color: IviaColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _active,
                onChanged: enabled
                    ? (v) {
                        setState(() => _active = v);
                        _changed();
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: IviaSpacing.lg),
      PhotosField(
        compact: true,
        photos: form.photos,
        enabled: enabled,
        errorText: _errors['image_keys'],
        onChanged: (photos) {
          form.photos = photos;
          _changed('image_keys');
        },
      ),
      const SizedBox(height: IviaSpacing.lg),
      IviaFieldLabel(
        label: 'Nom du produit',
        child: TextField(
          controller: form.name,
          enabled: enabled,
          maxLength: 150,
          onChanged: (_) => _changed('name'),
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
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
            form.categoryId = id;
            _changed('category_id');
          },
        ),
      ),
      const SizedBox(height: IviaSpacing.lg),
      Container(
        decoration: BoxDecoration(
          color: IviaColors.surface,
          borderRadius: BorderRadius.circular(IviaRadius.large),
        ),
        child: Column(
          children: [
            _SettingRow(
              label: 'Description',
              value: switch (form.description.text.trim().length) {
                0 => 'Aucune',
                1 => '1 caractère',
                final n => '$n caractères',
              },
              error: _errors['description'],
              onTap: enabled ? () => _editDescription(form) : null,
            ),
            const Divider(),
            _SettingRow(
              label: 'Taille du colis',
              value: parcelLabel(form.parcelSize!),
              error: _errors['parcel_size'],
              onTap: enabled ? () => _editParcel(form) : null,
            ),
            const Divider(),
            _SettingRow(
              label: 'Stock',
              value: form.tracked ? 'Suivi · ${form.quantity}' : 'Non suivi',
              error: _errors['stock_quantity'],
              onTap: enabled ? () => _editStock(form) : null,
            ),
          ],
        ),
      ),
      const SizedBox(height: IviaSpacing.xxl),
      if (_generalError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: IviaSpacing.md),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _generalError!,
              style: textTheme.bodyMedium?.copyWith(color: IviaColors.error),
            ),
          ),
        ),
      FilledButton(
        onPressed: enabled ? _save : null,
        child: _busy
            ? const ButtonProgress()
            : const Text('Enregistrer les modifications'),
      ),
      if (wasActive) ...[
        const SizedBox(height: IviaSpacing.sm),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: IviaColors.error),
          onPressed: enabled ? _withdraw : null,
          child: const Text('Retirer de la vente'),
        ),
      ],
    ];
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.error,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: IviaSpacing.lg,
            vertical: IviaSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: IviaSpacing.md,
                children: [
                  Text(
                    label,
                    style: textTheme.titleSmall?.copyWith(
                      color: IviaColors.textSecondary,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(value, style: textTheme.titleSmall)),
                      const Icon(
                        Icons.chevron_right,
                        color: IviaColors.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
              if (error != null)
                Text(
                  error!,
                  style: textTheme.bodySmall?.copyWith(color: IviaColors.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
