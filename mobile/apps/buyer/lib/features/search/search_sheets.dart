import 'package:flutter/material.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/catalog_data.dart';
import 'search_state.dart';

/// Choix dans une feuille ; [T] `null` est une valeur possible (« Toutes »),
/// d'où l'enveloppe : `null` reçu = feuille fermée sans choix.
class Picked<T> {
  const Picked(this.value);

  final T value;
}

Future<Picked<T>?> _pick<T>(
  BuildContext context, {
  required String title,
  required List<(String, T)> options,
  required T current,
}) => showModalBottomSheet<Picked<T>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    ),
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: IviaSpacing.screen),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.screen),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
        const SizedBox(height: IviaSpacing.sm),
        for (final (label, value) in options)
          ListTile(
            title: Text(label),
            selected: value == current,
            trailing: value == current ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, Picked(value)),
          ),
      ],
    ),
  ),
);

/// Rayon d'« Autour de moi » ; `Picked(null)` : sans limite.
Future<Picked<int?>?> showRadiusSheet(BuildContext context, int? current) =>
    _pick<int?>(
      context,
      title: 'Autour de moi',
      current: current,
      options: [
        for (final km in searchRadii) ('$km km', km),
        ('Sans limite', null),
      ],
    );

/// Catégorie ; `Picked(null)` : toutes.
Future<Picked<String?>?> showCategorySheet(
  BuildContext context,
  List<ProductCategory> all,
  String? current,
) => _pick<String?>(
  context,
  title: 'Catégorie',
  current: current,
  options: [
    ('Toutes les catégories', null),
    for (final c in all) (categoryName(all, c.id) ?? c.name, c.id),
  ],
);

/// Tri ; la distance seulement avec la position du téléphone, les prix
/// seulement pour les produits.
Future<Picked<SearchSort>?> showSortSheet(
  BuildContext context, {
  required SearchSort current,
  required bool withDistance,
  required bool products,
}) => _pick<SearchSort>(
  context,
  title: 'Trier',
  current: current,
  options: [
    ('Pertinence', SearchSort.relevance),
    if (withDistance) ('Distance', SearchSort.distance),
    if (products) ('Prix croissant', SearchSort.priceAsc),
    if (products) ('Prix décroissant', SearchSort.priceDesc),
  ],
);

String sortLabel(SearchSort sort) => switch (sort) {
  SearchSort.relevance => 'pertinence',
  SearchSort.distance => 'distance',
  SearchSort.priceAsc => 'prix croissant',
  SearchSort.priceDesc => 'prix décroissant',
};

/// Fourchette de prix ; `null` : feuille fermée sans choix.
Future<(int?, int?)?> showPriceSheet(
  BuildContext context, {
  int? min,
  int? max,
}) => showModalBottomSheet<(int?, int?)>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => _PriceSheet(min: min, max: max),
);

class _PriceSheet extends StatefulWidget {
  const _PriceSheet({this.min, this.max});

  final int? min;
  final int? max;

  @override
  State<_PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends State<_PriceSheet> {
  late final _min = TextEditingController(
    text: widget.min == null ? '' : groupDigits(widget.min!),
  );
  late final _max = TextEditingController(
    text: widget.max == null ? '' : groupDigits(widget.max!),
  );
  String? _error;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _apply() {
    final min = parseXof(_min.text);
    final max = parseXof(_max.text);
    if (min != null && max != null && min > max) {
      setState(() => _error = 'Le prix minimal dépasse le prix maximal.');
      return;
    }
    Navigator.pop(context, (min, max));
  }

  Widget _field(String label, TextEditingController controller) =>
      IviaFieldLabel(
        label: label,
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [XofInputFormatter()],
          onChanged: (_) => setState(() => _error = null),
          decoration: const InputDecoration(hintText: '0', suffixText: 'F'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          IviaSpacing.screen,
          0,
          IviaSpacing.screen,
          IviaSpacing.screen,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Prix', style: textTheme.headlineSmall),
            ),
            const SizedBox(height: IviaSpacing.lg),
            _field('Minimum', _min),
            const SizedBox(height: IviaSpacing.md),
            _field('Maximum', _max),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: IviaSpacing.sm),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: textTheme.bodyMedium?.copyWith(
                      color: IviaColors.error,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: IviaSpacing.xl),
            FilledButton(onPressed: _apply, child: const Text('Appliquer')),
            TextButton(
              onPressed: () => Navigator.pop(context, (null, null)),
              child: const Text('Tous les prix'),
            ),
          ],
        ),
      ),
    );
  }
}

/// « 1 000 – 5 000 F », « dès 1 000 F », « jusqu'à 5 000 F ».
String? priceLabel(int? min, int? max) => switch ((min, max)) {
  (null, null) => null,
  (final a?, null) => 'dès ${formatXof(a)}',
  (null, final b?) => 'jusqu’à ${formatXof(b)}',
  (final a?, final b?) => '${groupDigits(a)} – ${formatXof(b)}',
};
