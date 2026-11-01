import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/seller_shop.dart';

/// Onglets de l'app marchand, dans l'ordre des branches du routeur.
const sellerTabs = [
  IviaNavItem(icon: Icons.home_outlined, label: 'Accueil'),
  IviaNavItem(icon: Icons.receipt_long_outlined, label: 'Commandes'),
  IviaNavItem(icon: Icons.grid_view_rounded, label: 'Catalogue'),
  IviaNavItem(icon: Icons.person_outline, label: 'Compte'),
];

/// Cadre des onglets : barre du bas pour une boutique publiée. En attente de
/// validation, seul le catalogue est ouvert, sans barre.
class SellerShell extends ConsumerWidget {
  const SellerShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final published = ref.watch(
      sellerShopProvider.select((s) => s.value?.status == ShopStatus.published),
    );
    return Scaffold(
      body: shell,
      bottomNavigationBar: published
          ? IviaBottomNav(
              items: sellerTabs,
              currentIndex: shell.currentIndex,
              // Onglet déjà ouvert : retour à son premier écran.
              onSelected: (i) =>
                  shell.goBranch(i, initialLocation: i == shell.currentIndex),
            )
          : null,
    );
  }
}
