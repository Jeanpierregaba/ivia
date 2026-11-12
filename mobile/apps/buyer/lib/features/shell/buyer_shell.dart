import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../notifications/notification_watcher.dart';
import '../orders/orders_providers.dart';
import '../promo/promo_overlay.dart';

/// Onglets de l'app acheteur, dans l'ordre des branches du routeur.
const buyerTabs = [
  IviaNavItem(icon: Icons.home_outlined, label: 'Accueil'),
  IviaNavItem(icon: Icons.search, label: 'Recherche'),
  IviaNavItem(icon: Icons.receipt_long_outlined, label: 'Commandes'),
  IviaNavItem(icon: Icons.person_outline, label: 'Profil'),
];

/// Index de l'onglet Commandes.
const ordersTab = 2;

/// Cadre des onglets : barre du bas en pilule.
class BuyerShell extends ConsumerWidget {
  const BuyerShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // Publicité pendant la navigation (fenêtres et interstitiels).
      body: NotificationWatcher(child: PromoHost(child: shell)),
      bottomNavigationBar: IviaBottomNav(
        items: buyerTabs,
        currentIndex: shell.currentIndex,
        // Onglet déjà ouvert : retour à son premier écran.
        onSelected: (i) {
          // Commandes : relues à chaque ouverture de l'onglet.
          if (i == ordersTab && ref.exists(myOrdersProvider)) {
            unawaited(
              ref
                  .read(myOrdersProvider.notifier)
                  .refresh()
                  .catchError((Object _) {}),
            );
          }
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
      ),
    );
  }
}
