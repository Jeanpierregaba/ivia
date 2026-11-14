import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/seller_shop.dart';
import '../business/biz_ui.dart';

/// Codes promo de la boutique (spec 034).
final promoCodesProvider = FutureProvider.autoDispose<List<PromoCode>>((
  ref,
) async {
  final shop = ref.watch(sellerShopProvider).value;
  if (shop == null) return const [];
  return ref.read(apiClientProvider).sellerPromoCodes(shop.id);
});

/// Nouveau code promo ; [products] : produits déjà choisis (code créé depuis
/// un produit). Annonce le code créé et relit la liste.
Future<PromoCode?> showPromoCreateSheet(
  BuildContext context, {
  List<({String id, String name})> products = const [],
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final created = await showModalBottomSheet<PromoCode>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _CreateSheet(products: products),
  );
  if (created != null) {
    container.invalidate(promoCodesProvider);
    showMessage(
      messenger,
      'Code ${created.code} créé, utilisable dès maintenant.',
    );
  }
  return created;
}

/// Portée d'un code : « toute la boutique » ou ses produits.
String promoScopeLabel(PromoCode c) {
  if (!c.limitedToProducts) return 'toute la boutique';
  final names = c.products.map((p) => p.name).toList();
  if (names.length == 1) return 'sur ${names.single}';
  if (names.length <= 3) return 'sur ${names.join(', ')}';
  return 'sur ${names.length} produits';
}

const _stateLabels = {
  'active': ('Actif', IviaColors.success),
  'scheduled': ('Programmé', IviaColors.secondary),
  'suspended': ('Suspendu', IviaColors.warning),
  'ended': ('Terminé', IviaColors.textMuted),
};

/// Codes promo : liste (actifs, programmés, terminés) avec les utilisations
/// et le montant offert ; création ; suspension, reprise, fin. La réduction
/// est prise sur ce que reçoit la boutique.
class PromoCodesScreen extends ConsumerWidget {
  const PromoCodesScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) =>
      showPromoCreateSheet(context);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final list = ref.watch(promoCodesProvider);
    return Scaffold(
      backgroundColor: IviaColors.background,
      appBar: AppBar(
        backgroundColor: IviaColors.background,
        title: const Text('Codes promo'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Créer un code'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(promoCodesProvider.future),
        child: switch (list) {
          AsyncData(:final value) when value.isEmpty => ListView(
            padding: const EdgeInsets.all(IviaSpacing.xxl),
            children: [
              const SizedBox(height: IviaSpacing.xl),
              const Icon(
                Icons.local_offer_outlined,
                size: 56,
                color: IviaColors.textMuted,
              ),
              const SizedBox(height: IviaSpacing.md),
              Text(
                'Attirez de nouveaux clients',
                textAlign: TextAlign.center,
                style: t.titleMedium,
              ),
              const SizedBox(height: IviaSpacing.xs),
              Text(
                'Créez un code promo : -10 %, 500 F offerts… Vos clients le '
                'saisissent au paiement. La réduction est prise sur vos '
                'ventes.',
                textAlign: TextAlign.center,
                style: t.bodyMedium,
              ),
            ],
          ),
          AsyncData(:final value) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              IviaSpacing.screen,
              IviaSpacing.sm,
              IviaSpacing.screen,
              96,
            ),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: IviaSpacing.md),
            itemBuilder: (context, i) => IviaReveal(
              index: i,
              child: _CodeCard(code: value[i]),
            ),
          ),
          AsyncError() => ListView(
            padding: const EdgeInsets.all(IviaSpacing.xxl),
            children: [
              Text(
                'Impossible de charger vos codes.',
                textAlign: TextAlign.center,
                style: t.bodyLarge,
              ),
              Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(promoCodesProvider),
                  child: const Text('Réessayer'),
                ),
              ),
            ],
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _CodeCard extends ConsumerStatefulWidget {
  const _CodeCard({required this.code});
  final PromoCode code;

  @override
  ConsumerState<_CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends ConsumerState<_CodeCard> {
  var _busy = false;

  Future<void> _act(String action) async {
    final messenger = ScaffoldMessenger.of(context);
    if (action == 'end') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Terminer ce code ?'),
          content: const Text('Il ne pourra plus être utilisé ni repris.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Terminer'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .sellerPromoCodeAction(widget.code.id, action);
      ref.invalidate(promoCodesProvider);
    } on ApiException catch (e) {
      showMessage(messenger, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = widget.code;
    final (label, color) = _stateLabels[c.state] ?? _stateLabels['active']!;
    final value = c.isPercent ? '-${c.value} %' : '-${formatXof(c.value)}';
    final details = [
      if (c.isPercent && c.maxDiscountXof != null)
        'max ${formatXof(c.maxDiscountXof!)}',
      if (c.minOrderXof > 0) 'dès ${formatXof(c.minOrderXof)}',
      if (c.maxUses != null) '${c.maxUses} utilisations',
      if (c.endsAt != null) 'jusqu’au ${shortDate(c.endsAt!.toLocal())}',
      promoScopeLabel(c),
      c.visibility == 'public' ? 'visible par tous' : 'privé',
    ];
    return Material(
      color: IviaColors.surface,
      borderRadius: BorderRadius.circular(IviaRadius.large),
      child: Padding(
        padding: const EdgeInsets.all(IviaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: IviaColors.primarySoft,
                    borderRadius: BorderRadius.circular(IviaRadius.button),
                  ),
                  child: Text(
                    value,
                    style: t.titleMedium?.copyWith(
                      color: IviaColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: IviaSpacing.md),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: c.code));
                      showMessage(
                        ScaffoldMessenger.of(context),
                        'Code ${c.code} copié : partagez-le à vos clients.',
                      );
                    },
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.code,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.copy_rounded,
                          size: 16,
                          color: IviaColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(IviaRadius.pill),
                  ),
                  child: Text(
                    label,
                    style: t.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: IviaSpacing.sm),
            Text(details.join(' · '), style: t.bodySmall),
            const SizedBox(height: IviaSpacing.xs),
            Text(
              '${c.usedCount} utilisation${c.usedCount > 1 ? 's' : ''} · '
              '${formatXof(c.discountGivenXof)} offerts',
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (c.suspendedByIvia) ...[
              const SizedBox(height: IviaSpacing.xs),
              Text(
                'Suspendu par ivia : ${c.suspensionReason}',
                style: t.bodySmall?.copyWith(color: IviaColors.warning),
              ),
            ],
            if (c.status != 'ended' && !c.suspendedByIvia)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: IviaSpacing.xs,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _act(
                              c.status == 'suspended' ? 'resume' : 'suspend',
                            ),
                      child: Text(
                        c.status == 'suspended' ? 'Reprendre' : 'Suspendre',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _act('end'),
                      style: TextButton.styleFrom(
                        foregroundColor: IviaColors.error,
                      ),
                      child: const Text('Terminer'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// « Créer un code » : code (ou généré), type, valeur, plafond, minimum,
/// limites, fin, public ou privé.
class _CreateSheet extends ConsumerStatefulWidget {
  const _CreateSheet({this.products = const []});

  final List<({String id, String name})> products;

  @override
  ConsumerState<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends ConsumerState<_CreateSheet> {
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _max = TextEditingController();
  final _min = TextEditingController();
  final _uses = TextEditingController();
  var _percent = true;
  var _public = true;
  int? _days = 30;
  var _busy = false;
  String? _error;

  /// Produits visés ; vide avec [_someProducts] faux : toute la boutique.
  late var _products = [...widget.products];
  late var _someProducts = widget.products.isNotEmpty;

  Future<void> _pickProducts() async {
    final picked = await showProductPicker(context, selected: _products);
    if (picked != null && mounted) setState(() => _products = picked);
  }

  @override
  void dispose() {
    for (final c in [_code, _value, _max, _min, _uses]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) =>
      int.tryParse(c.text.replaceAll(RegExp(r'\s'), ''));

  Future<void> _submit() async {
    final shop = ref.read(sellerShopProvider).value;
    final value = _int(_value);
    if (shop == null) return;
    if (value == null || value <= 0) {
      setState(() => _error = 'Indiquez la réduction.');
      return;
    }
    if (_someProducts && _products.isEmpty) {
      setState(() => _error = 'Choisissez au moins un produit.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(apiClientProvider)
          .createSellerPromoCode(
            shop.id,
            code: _code.text,
            kind: _percent ? 'percent' : 'fixed',
            value: value,
            maxDiscountXof: _percent ? _int(_max) : null,
            minOrderXof: _int(_min) ?? 0,
            maxUses: _int(_uses),
            endsAt: _days == null
                ? null
                : DateTime.now().add(Duration(days: _days!)),
            visibility: _public ? 'public' : 'private',
            productIds: _someProducts
                ? [for (final p in _products) p.id]
                : const [],
          );
      if (mounted) Navigator.pop(context, created);
    } on ApiException catch (e) {
      setState(() => _error = e.fields.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final numbers = [FilteringTextInputFormatter.digitsOnly];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        IviaSpacing.screen,
        0,
        IviaSpacing.screen,
        MediaQuery.viewInsetsOf(context).bottom + IviaSpacing.screen,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouveau code promo', style: t.titleLarge),
            const SizedBox(height: IviaSpacing.md),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Code (facultatif)',
                helperText: 'Vide : un code est créé pour vous',
              ),
            ),
            const SizedBox(height: IviaSpacing.md),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Pourcentage')),
                ButtonSegment(value: false, label: Text('Montant fixe')),
              ],
              selected: {_percent},
              onSelectionChanged: (s) => setState(() => _percent = s.first),
            ),
            const SizedBox(height: IviaSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _value,
                    keyboardType: TextInputType.number,
                    inputFormatters: numbers,
                    decoration: InputDecoration(
                      labelText: _percent ? 'Réduction (%)' : 'Réduction (F)',
                    ),
                  ),
                ),
                if (_percent) ...[
                  const SizedBox(width: IviaSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _max,
                      keyboardType: TextInputType.number,
                      inputFormatters: numbers,
                      decoration: const InputDecoration(
                        labelText: 'Plafond (F)',
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: IviaSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _min,
                    keyboardType: TextInputType.number,
                    inputFormatters: numbers,
                    decoration: const InputDecoration(
                      labelText: 'Achat minimum (F)',
                    ),
                  ),
                ),
                const SizedBox(width: IviaSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _uses,
                    keyboardType: TextInputType.number,
                    inputFormatters: numbers,
                    decoration: const InputDecoration(
                      labelText: 'Utilisations max',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: IviaSpacing.md),
            Text('Durée', style: t.titleSmall),
            const SizedBox(height: IviaSpacing.xs),
            Wrap(
              spacing: IviaSpacing.xs,
              children: [
                for (final (d, l) in [
                  (7, '7 jours'),
                  (30, '30 jours'),
                  (90, '3 mois'),
                  (null, 'Sans fin'),
                ])
                  ChoiceChip(
                    label: Text(l),
                    selected: _days == d,
                    onSelected: (_) => setState(() => _days = d),
                  ),
              ],
            ),
            const SizedBox(height: IviaSpacing.md),
            Text("S'applique à", style: t.titleSmall),
            const SizedBox(height: IviaSpacing.xs),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Toute la boutique')),
                ButtonSegment(value: true, label: Text('Certains produits')),
              ],
              selected: {_someProducts},
              onSelectionChanged: (s) {
                setState(() => _someProducts = s.first);
                if (s.first && _products.isEmpty) _pickProducts();
              },
            ),
            AnimatedSize(
              duration: Biz.medium,
              curve: Curves.easeOutCubic,
              child: !_someProducts
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: IviaSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final p in _products)
                                InputChip(
                                  label: Text(p.name),
                                  onDeleted: () => setState(
                                    () => _products = [
                                      for (final q in _products)
                                        if (q.id != p.id) q,
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: _pickProducts,
                            icon: const Icon(Icons.checklist_rounded),
                            label: Text(
                              _products.isEmpty
                                  ? 'Choisir les produits'
                                  : 'Modifier la sélection (${_products.length})',
                            ),
                          ),
                          Text(
                            _products.length == 1
                                ? 'La réduction porte sur ce produit seulement.'
                                : 'La réduction porte seulement sur ces produits '
                                      'dans le panier.',
                            style: t.bodySmall?.copyWith(
                              color: IviaColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _public,
              onChanged: (v) => setState(() => _public = v),
              title: const Text('Visible par tous'),
              subtitle: Text(
                _public
                    ? 'Affiché dans « Mes coupons » des clients'
                    : 'Privé : à partager vous-même',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: IviaSpacing.sm),
                child: Text(
                  _error!,
                  style: t.bodySmall?.copyWith(color: IviaColors.error),
                ),
              ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Créer le code'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Choix de plusieurs produits en vente de la boutique, avec recherche.
/// `null` : fermé sans valider.
Future<List<({String id, String name})>?> showProductPicker(
  BuildContext context, {
  List<({String id, String name})> selected = const [],
}) => showBizSheet<List<({String id, String name})>>(
  context,
  title: 'Produits concernés',
  expand: true,
  builder: (_) => _ProductPicker(selected: selected),
);

class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker({required this.selected});
  final List<({String id, String name})> selected;

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  late final _picked = {for (final p in widget.selected) p.id: p.name};
  late final Future<List<Product>> _load = () async {
    final shop = ref.read(sellerShopProvider).value;
    if (shop == null) return const <Product>[];
    final page = await ref
        .read(apiClientProvider)
        .sellerProducts(shop.id, status: ProductStatus.active, limit: 100);
    return page.items;
  }();
  var _q = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Chercher un produit',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Product>>(
            future: _load,
            builder: (context, snap) {
              if (snap.hasError) {
                return const BizEmpty(
                  icon: Icons.cloud_off_rounded,
                  color: Biz.red,
                  title: 'Produits indisponibles. Vérifiez votre connexion.',
                );
              }
              final all = snap.data;
              if (all == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = [
                for (final p in all)
                  if (_q.isEmpty || p.name.toLowerCase().contains(_q)) p,
              ];
              if (all.isEmpty) {
                return const BizEmpty(
                  icon: Icons.inventory_2_outlined,
                  title: 'Aucun produit en vente.',
                );
              }
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final p = items[i];
                  final on = _picked.containsKey(p.id);
                  return CheckboxListTile(
                    value: on,
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        _picked[p.id] = p.name;
                      } else {
                        _picked.remove(p.id);
                      }
                    }),
                    title: Text(p.name),
                    subtitle: Text(formatXof(p.priceXof)),
                    secondary: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox.square(
                        dimension: 44,
                        child: p.images.isEmpty
                            ? const IviaImagePlaceholder()
                            : Image.network(
                                p.images.first.url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const IviaImagePlaceholder(),
                              ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Biz.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SafeArea(
            top: false,
            child: BizButton(
              color: Biz.navy,
              label: _picked.isEmpty
                  ? 'Valider'
                  : 'Valider (${_picked.length})',
              onPressed: () => Navigator.pop(context, [
                for (final e in _picked.entries) (id: e.key, name: e.value),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}
