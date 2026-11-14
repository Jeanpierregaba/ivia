import 'package:flutter/material.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../business/biz_ui.dart';
import 'catalog_labels.dart';
import 'product_sheets.dart';

enum _RowAction { edit, stock, withdraw }

/// Pastille d'état d'un produit : en vente, épuisé, brouillon, retiré.
class ProductStatusBadge extends StatelessWidget {
  const ProductStatusBadge(this.product, {super.key});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return switch (p.status) {
      ProductStatus.active when p.soldOut => const BizBadge(
        'Épuisé',
        color: Biz.red,
        icon: Icons.error_outline_rounded,
      ),
      ProductStatus.active => const BizBadge(
        'En vente',
        color: Biz.green,
        icon: Icons.check_circle_rounded,
      ),
      ProductStatus.draft => const BizBadge(
        'Brouillon',
        color: Biz.muted,
        icon: Icons.edit_note_rounded,
      ),
      ProductStatus.withdrawn => const BizBadge(
        'Retiré',
        color: Biz.amber,
        icon: Icons.pause_circle_outline_rounded,
      ),
    };
  }
}

/// Couleur du stock : rouge épuisé, ambre bas (3 ou moins), vert sinon.
Color stockColor(Product p) {
  if (p.stockMode != StockMode.tracked) return Biz.muted;
  final q = p.stockQuantity ?? 0;
  return q <= 0
      ? Biz.red
      : q <= 3
      ? Biz.amber
      : Biz.green;
}

/// Ligne d'un produit : vignette, état, nom, stock, prix. Glisser vers la
/// droite retire (ou remet) en vente, vers la gauche ajuste le stock ; un
/// appui long démarre la sélection multiple.
class ProductRow extends StatelessWidget {
  const ProductRow({
    super.key,
    required this.product,
    required this.categoryName,
    required this.onOpen,
    required this.onStock,
    required this.onWithdraw,
    required this.onRestore,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
  });

  final Product product;
  final String? categoryName;

  /// Modifier un produit, ou reprendre un brouillon.
  final VoidCallback onOpen;
  final VoidCallback onStock;
  final VoidCallback onWithdraw;
  final VoidCallback onRestore;

  /// Sélection multiple en cours : un appui coche ou décoche.
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = product;
    final withdrawn = p.status == ProductStatus.withdrawn;
    final active = p.status == ProductStatus.active;
    final soldOut = active && p.soldOut;
    // Police agrandie : prix et actions passent sous le nom.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    final card = BizCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      border: selected ? Biz.blue : null,
      color: selected ? const Color(0xFFF2F7FE) : Colors.white,
      onTap: selecting ? onSelect : onOpen,
      onLongPress: selecting ? null : onSelect,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Biz.page,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Opacity(
                  opacity: withdrawn ? 0.55 : 1,
                  child: ProductThumb(url: p.images.firstOrNull?.url, size: 72),
                ),
              ),
              Positioned(
                top: -6,
                left: -6,
                child: AnimatedScale(
                  scale: selecting ? 1 : 0,
                  duration: Biz.medium,
                  curve: Biz.spring,
                  child: _Check(selected: selected),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductStatusBadge(p),
                const SizedBox(height: 4),
                Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: withdrawn ? Biz.muted : IviaColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: stockColor(p),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        productSubtitle(p, category: categoryName),
                        style: soldOut
                            ? t.bodySmall?.copyWith(
                                color: Biz.red,
                                fontWeight: FontWeight.w700,
                              )
                            : t.bodySmall?.copyWith(color: Biz.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (stacked)
                  _trailing(context, stacked: true)
                else
                  Text(
                    formatXof(p.priceXof),
                    style: t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Biz.navy,
                      fontFeatures: Biz.tabular,
                    ),
                  ),
              ],
            ),
          ),
          if (!stacked && !selecting) _trailing(context, stacked: false),
        ],
      ),
    );

    if (selecting) return card;
    final tracked = active && p.stockMode == StockMode.tracked;
    return Dismissible(
      key: ValueKey('swipe-${p.id}'),
      direction: tracked
          ? DismissDirection.horizontal
          : DismissDirection.startToEnd,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.32,
        DismissDirection.endToStart: 0.32,
      },
      // Le geste lance l'action ; la ligne revient à sa place.
      confirmDismiss: (direction) async {
        Biz.tick();
        if (direction == DismissDirection.endToStart) {
          onStock();
        } else if (withdrawn) {
          onRestore();
        } else if (active) {
          onWithdraw();
        } else {
          onOpen();
        }
        return false;
      },
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: withdrawn
            ? Biz.green
            : active
            ? Biz.red
            : Biz.blue,
        icon: withdrawn
            ? Icons.play_circle_outline_rounded
            : active
            ? Icons.pause_circle_outline_rounded
            : Icons.edit_outlined,
        label: withdrawn
            ? 'Remettre'
            : active
            ? 'Retirer'
            : 'Reprendre',
      ),
      secondaryBackground: const _SwipeBackground(
        alignment: Alignment.centerRight,
        color: Biz.blue,
        icon: Icons.inventory_outlined,
        label: 'Stock',
      ),
      child: card,
    );
  }

  Widget _trailing(BuildContext context, {required bool stacked}) {
    final t = Theme.of(context).textTheme;
    final p = product;
    if (p.status == ProductStatus.withdrawn) {
      final button = TextButton(
        onPressed: onRestore,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          foregroundColor: Biz.blue,
          textStyle: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        child: Text('Remettre', semanticsLabel: 'Remettre ${p.name} en vente'),
      );
      if (!stacked) return button;
      // Grande police : le bouton passe sous le prix s'il manque de place.
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [_price(context), button],
      );
    }
    final active = p.status == ProductStatus.active;
    if (stacked) {
      return Row(
        children: [
          Expanded(child: _price(context)),
          if (active) _menu(context),
        ],
      );
    }
    return active ? _menu(context) : const SizedBox(width: 8);
  }

  Widget _price(BuildContext context) => Text(
    formatXof(product.priceXof),
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: Biz.navy,
      fontFeatures: Biz.tabular,
    ),
  );

  // Cible tactile de 48 dp (taille par défaut du bouton).
  Widget _menu(BuildContext context) => PopupMenuButton<_RowAction>(
    tooltip: 'Actions pour ${product.name}',
    padding: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    icon: const Icon(Icons.more_vert_rounded, color: Biz.muted),
    onSelected: (action) => switch (action) {
      _RowAction.edit => onOpen(),
      _RowAction.stock => onStock(),
      _RowAction.withdraw => onWithdraw(),
    },
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: _RowAction.edit,
        child: ListTile(
          leading: Icon(Icons.edit_outlined),
          title: Text('Modifier'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (product.stockMode == StockMode.tracked)
        const PopupMenuItem(
          value: _RowAction.stock,
          child: ListTile(
            leading: Icon(Icons.inventory_outlined),
            title: Text('Ajuster le stock'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      const PopupMenuItem(
        value: _RowAction.withdraw,
        child: ListTile(
          leading: Icon(Icons.pause_circle_outline, color: IviaColors.error),
          title: Text(
            'Retirer de la vente',
            style: TextStyle(color: IviaColors.error),
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
  );
}

/// Vignette d'un produit en grille : grande photo, état, nom, prix.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.onOpen,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
  });
  final Product product;
  final VoidCallback onOpen;
  final bool selecting, selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = product;
    return BizCard(
      padding: EdgeInsets.zero,
      border: selected ? Biz.blue : null,
      onTap: selecting ? onSelect : onOpen,
      onLongPress: selecting ? null : onSelect,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(Biz.radius),
                  ),
                  child: LayoutBuilder(
                    builder: (_, c) => ProductThumb(
                      url: p.images.firstOrNull?.url,
                      size: c.maxWidth,
                    ),
                  ),
                ),
                Positioned(left: 8, top: 8, child: ProductStatusBadge(p)),
                Positioned(
                  right: 8,
                  top: 8,
                  child: AnimatedScale(
                    scale: selecting ? 1 : 0,
                    duration: Biz.medium,
                    curve: Biz.spring,
                    child: _Check(selected: selected),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatXof(p.priceXof),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Biz.navy,
                          fontFeatures: Biz.tabular,
                        ),
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: stockColor(p),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: Biz.fast,
    width: 26,
    height: 26,
    decoration: BoxDecoration(
      color: selected ? Biz.blue : Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: selected ? Biz.blue : Biz.line, width: 2),
      boxShadow: Biz.shadow,
    ),
    child: selected
        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
        : null,
  );
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });
  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(Biz.radius),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}
