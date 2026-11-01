import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Onglets de l'app acheteur, dans l'ordre des branches du routeur.
const buyerTabs = [
  IviaNavItem(icon: Icons.home_outlined, label: 'Accueil'),
  IviaNavItem(icon: Icons.search, label: 'Recherche'),
  IviaNavItem(icon: Icons.receipt_long_outlined, label: 'Commandes'),
  IviaNavItem(icon: Icons.person_outline, label: 'Profil'),
];

/// Cadre des onglets : barre du bas en pilule.
class BuyerShell extends StatelessWidget {
  const BuyerShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: IviaBottomNav(
        items: buyerTabs,
        currentIndex: shell.currentIndex,
        // Onglet déjà ouvert : retour à son premier écran.
        onSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}
