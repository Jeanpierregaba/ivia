import 'package:flutter/material.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'catalog_labels.dart';
import 'product_sheets.dart';

enum _RowAction { edit, stock, withdraw }

/// Ligne d'un produit dans le catalogue. Les lignes forment une carte
/// blanche : [first] et [last] arrondissent ses coins.
class ProductRow extends StatelessWidget {
  const ProductRow({
    super.key,
    required this.product,
    required this.categoryName,
    required this.first,
    required this.last,
    required this.onOpen,
    required this.onStock,
    required this.onWithdraw,
    required this.onRestore,
  });

  final Product product;
  final String? categoryName;
  final bool first;
  final bool last;

  /// Modifier un produit, ou reprendre un brouillon.
  final VoidCallback onOpen;
  final VoidCallback onStock;
  final VoidCallback onWithdraw;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Police agrandie : prix et actions passent sous le nom.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final p = product;
    final withdrawn = p.status == ProductStatus.withdrawn;
    final soldOut = p.status == ProductStatus.active && p.soldOut;
    const corner = Radius.circular(IviaRadius.large);
    final radius = BorderRadius.vertical(
      top: first ? corner : Radius.zero,
      bottom: last ? corner : Radius.zero,
    );
    return Material(
      color: IviaColors.surface,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(bottom: BorderSide(color: IviaColors.border)),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: IviaSpacing.lg,
            vertical: IviaSpacing.md,
          ),
          child: Row(
            children: [
              ProductThumb(url: p.images.firstOrNull?.url),
              const SizedBox(width: IviaSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: withdrawn ? IviaColors.textMuted : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      productSubtitle(p, category: categoryName),
                      style: soldOut
                          ? textTheme.bodySmall?.copyWith(
                              color: IviaColors.error,
                              fontWeight: FontWeight.w700,
                            )
                          : textTheme.bodySmall,
                    ),
                    if (stacked) ...[
                      const SizedBox(height: IviaSpacing.xs),
                      _trailing(context, stacked: true),
                    ],
                  ],
                ),
              ),
              if (!stacked) ...[
                const SizedBox(width: IviaSpacing.sm),
                _trailing(context, stacked: false),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _trailing(BuildContext context, {required bool stacked}) {
    final textTheme = Theme.of(context).textTheme;
    final p = product;
    final withdrawn = p.status == ProductStatus.withdrawn;
    if (withdrawn) {
      return OutlinedButton(
        onPressed: onRestore,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.lg),
          side: const BorderSide(color: IviaColors.cobaltBlue),
          foregroundColor: IviaColors.cobaltBlue,
          textStyle: textTheme.titleSmall,
        ),
        child: Text('Remettre', semanticsLabel: 'Remettre ${p.name} en vente'),
      );
    }
    final price = Text(
      formatXof(p.priceXof),
      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
    final active = p.status == ProductStatus.active;
    if (stacked) {
      return Row(
        children: [
          Expanded(child: price),
          if (active) _menu(context),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [price, if (active) _menu(context)],
    );
  }

  // Cible tactile de 48 dp (taille par défaut du bouton).
  Widget _menu(BuildContext context) => PopupMenuButton<_RowAction>(
    tooltip: 'Actions pour ${product.name}',
    padding: EdgeInsets.zero,
    icon: const Icon(Icons.more_horiz, color: IviaColors.textMuted),
    onSelected: (action) => switch (action) {
      _RowAction.edit => onOpen(),
      _RowAction.stock => onStock(),
      _RowAction.withdraw => onWithdraw(),
    },
    itemBuilder: (context) => [
      const PopupMenuItem(value: _RowAction.edit, child: Text('Modifier')),
      if (product.stockMode == StockMode.tracked)
        const PopupMenuItem(
          value: _RowAction.stock,
          child: Text('Ajuster le stock'),
        ),
      const PopupMenuItem(
        value: _RowAction.withdraw,
        child: Text(
          'Retirer de la vente',
          style: TextStyle(color: IviaColors.error),
        ),
      ),
    ],
  );
}
