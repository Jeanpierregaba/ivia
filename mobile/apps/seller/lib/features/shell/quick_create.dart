import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../account/promo_codes_screen.dart';
import '../account/revenue_screen.dart';
import '../business/biz_ui.dart';
import '../orders/order_labels.dart';

/// Menu du « + » de la barre du bas : les actions les plus fréquentes du
/// marchand, à un geste de n'importe quel onglet.
Future<void> showQuickCreate(
  BuildContext context, {
  required bool restaurant,
  required int fresh,
}) {
  final router = GoRouter.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  void open(Widget screen) =>
      navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
  final actions = [
    _Action(
      icon: restaurant ? Icons.restaurant_menu_rounded : Icons.add_box_outlined,
      label: restaurant ? 'Nouveau plat' : 'Nouveau produit',
      hint: 'Photos, prix, stock',
      color: Biz.red,
      run: () => router.push(Routes.productNew),
    ),
    _Action(
      icon: Icons.local_offer_outlined,
      label: 'Code promo',
      hint: 'Attirer des clients',
      color: const Color(0xFF7A3FD6),
      run: () => open(const PromoCodesScreen()),
    ),
    _Action(
      icon: Icons.receipt_long_outlined,
      label: fresh > 0 ? 'À accepter ($fresh)' : 'Commandes',
      hint: fresh > 0 ? 'Le délai court' : 'Suivre les commandes',
      color: Biz.blue,
      run: () => router.go(Routes.ordersTab(OrderTab.fresh)),
    ),
    _Action(
      icon: Icons.query_stats_rounded,
      label: 'Revenus',
      hint: 'Ventes et relevés',
      color: Biz.green,
      run: () => open(const RevenueScreen()),
    ),
  ];
  return showBizSheet<void>(
    context,
    title: 'Créer et gérer',
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: LayoutBuilder(
        builder: (context, c) {
          // Deux colonnes, une seule si la police est très agrandie.
          final wide =
              c.maxWidth > 300 &&
              MediaQuery.textScalerOf(context).scale(10) <= 15;
          final w = wide ? (c.maxWidth - 12) / 2 : c.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (i, a) in actions.indexed)
                SizedBox(
                  width: w,
                  child: BizReveal(
                    index: i,
                    child: BizCard(
                      color: a.color.withValues(alpha: 0.06),
                      onTap: () {
                        Navigator.pop(context);
                        a.run();
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: a.color,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(a.icon, color: Colors.white),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            a.label,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            a.hint,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Biz.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _Action {
  const _Action({
    required this.icon,
    required this.label,
    required this.hint,
    required this.color,
    required this.run,
  });
  final IconData icon;
  final String label, hint;
  final Color color;
  final VoidCallback run;
}
