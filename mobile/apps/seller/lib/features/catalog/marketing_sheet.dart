import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../business/biz_ui.dart';

/// Résumé de la promotion d'un produit (ligne de « Modifier »).
String marketingSummary(Product p) {
  final parts = [
    if (p.promoPriceXof != null) 'Prix barré ${formatXof(p.promoPriceXof!)}',
    if (p.featuredRank != null) 'En vedette',
    if (p.badges.isNotEmpty) p.badges.map((b) => b.label).join(', '),
  ];
  return parts.isEmpty ? 'Aucune' : parts.join(' · ');
}

/// Promotion et mise en avant d'un produit, gérées par la boutique : prix
/// barré (et sa durée), badges, mise en vedette. Renvoie le produit à jour ;
/// `null` : fermé sans changement.
Future<Product?> showMarketingSheet(BuildContext context, Product product) =>
    showBizSheet<Product>(
      context,
      title: 'Promotion et mise en avant',
      builder: (_) => _MarketingSheet(product: product),
    );

class _MarketingSheet extends ConsumerStatefulWidget {
  const _MarketingSheet({required this.product});
  final Product product;

  @override
  ConsumerState<_MarketingSheet> createState() => _MarketingSheetState();
}

class _MarketingSheetState extends ConsumerState<_MarketingSheet> {
  late final _price = TextEditingController(
    text: widget.product.promoPriceXof?.toString() ?? '',
  );
  late var _badges = {...widget.product.badges};
  late var _featured = widget.product.featuredRank != null;
  int? _days = 7;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _price.text.replaceAll(RegExp(r'\s'), '');
    final promo = raw.isEmpty ? null : int.tryParse(raw);
    final p = widget.product;
    if (raw.isNotEmpty &&
        (promo == null || promo <= 0 || promo >= p.priceXof)) {
      setState(
        () => _error =
            'Le prix barré doit être inférieur au prix normal '
            '(${formatXof(p.priceXof)}).',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(apiClientProvider)
          .setProductMarketing(
            p.id,
            promoPriceXof: promo,
            promoEndsAt: promo == null || _days == null
                ? null
                : DateTime.now().add(Duration(days: _days!)),
            badges: _badges.toList(),
            featuredRank: _featured ? 100 : null,
            features: p.features,
          );
      if (mounted) Navigator.pop(context, updated);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.fields.values.firstOrNull ?? e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = widget.product;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Prix barré', style: t.titleSmall),
          const SizedBox(height: 6),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: 'Vide : pas de promotion',
              suffixText: 'FCFA',
              helperText:
                  'Prix normal : ${formatXof(p.priceXof)} (affiché barré)',
            ),
          ),
          const SizedBox(height: 12),
          Text('Durée de la promotion', style: t.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (d, l) in const [
                (3, '3 jours'),
                (7, '7 jours'),
                (30, '30 jours'),
                (null, 'Sans fin'),
              ])
                ChoiceChip(
                  label: Text(l),
                  selected: _days == d,
                  onSelected: (_) => setState(() => _days = d),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Badges', style: t.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final b in ProductBadge.values)
                FilterChip(
                  label: Text(b.label),
                  selected: _badges.contains(b),
                  onSelected: (on) => setState(() {
                    _badges = {..._badges};
                    on ? _badges.add(b) : _badges.remove(b);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _featured,
            onChanged: (v) => setState(() => _featured = v),
            title: const Text('Mettre en vedette'),
            subtitle: const Text(
              'Le produit remonte en tête des produits mis en avant.',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: t.bodySmall?.copyWith(color: IviaColors.error),
              ),
            ),
          const SizedBox(height: 8),
          BizButton(
            color: Biz.navy,
            busy: _busy,
            label: 'Enregistrer',
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
