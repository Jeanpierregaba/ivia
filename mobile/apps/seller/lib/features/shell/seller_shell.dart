import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../app/business_state.dart';
import '../../app/seller_shop.dart';
import '../business/pro_ui.dart';
import '../orders/order_labels.dart';
import '../orders/orders_providers.dart';

/// Onglets de l'app marchand, dans l'ordre des branches du routeur.
const sellerTabs = [
  IviaNavItem(icon: Icons.home_outlined, label: 'Accueil'),
  IviaNavItem(icon: Icons.receipt_long_outlined, label: 'Commandes'),
  IviaNavItem(icon: Icons.grid_view_rounded, label: 'Catalogue'),
  IviaNavItem(icon: Icons.person_outline, label: 'Compte'),
];

/// Index de l'onglet Commandes dans [sellerTabs].
const ordersTabIndex = 1;

/// Cadre des onglets : barre du bas pour une boutique publiée. En attente de
/// validation, seul le catalogue est ouvert, sans barre.
///
/// Boutique publiée : relit les nouvelles commandes toutes les 30 s tant que
/// l'app est au premier plan, la liste complète au retour et à l'ouverture
/// de l'onglet Commandes ; rien en arrière-plan. La pastille de l'onglet
/// Commandes compte les nouvelles.
class SellerShell extends ConsumerStatefulWidget {
  const SellerShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<SellerShell> createState() => _SellerShellState();
}

class _SellerShellState extends ConsumerState<SellerShell> {
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _start();
    _lifecycle = AppLifecycleListener(
      onHide: _stop,
      onShow: () {
        _reload();
        _start();
      },
    );
  }

  @override
  void dispose() {
    _stop();
    _lifecycle.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(ordersRefreshInterval, (_) => _poll());
  }

  /// Relecture légère toutes les 30 s : les nouvelles commandes seulement.
  void _poll() {
    if (!mounted || !_published) return;
    unawaited(
      ref.read(sellerOrdersProvider.notifier).poll().catchError((_) {}),
    );
  }

  /// Dernier onglet affiché : l'ouverture de l'onglet Commandes relit la
  /// liste complète.
  int? _lastIndex;

  void _onTab(int index) {
    final previous = _lastIndex;
    _lastIndex = index;
    if (previous != null && previous != index && index == ordersTabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Relecture complète (retour dans l'app, ouverture de l'onglet
  /// Commandes) : erreur ignorée, les dernières données restent.
  void _reload() {
    if (!mounted || !_published) return;
    unawaited(
      ref.read(sellerOrdersProvider.notifier).refresh().catchError((_) {}),
    );
  }

  bool get _published =>
      ref.read(sellerShopProvider).value?.status == ShopStatus.published;

  @override
  Widget build(BuildContext context) {
    _onTab(widget.shell.currentIndex);
    final published = ref.watch(
      sellerShopProvider.select((s) => s.value?.status == ShopStatus.published),
    );
    final fresh = published
        ? ref.watch(
            sellerOrdersProvider.select(
              (s) => s.value?.count(OrderTab.fresh) ?? 0,
            ),
          )
        : 0;
    final sector = ref.watch(
      businessGateProvider.select((g) => g.value?.opened?.sector),
    );
    final restaurant = sector == 'restaurant';
    return Scaffold(
      backgroundColor: Pro.page,
      body: widget.shell,
      bottomNavigationBar: published
          ? ProDock(
              accent: Pro.accent(sector),
              current: widget.shell.currentIndex,
              // Onglet déjà ouvert : retour à son premier écran.
              onSelected: (i) => widget.shell.goBranch(
                i,
                initialLocation: i == widget.shell.currentIndex,
              ),
              items: [
                const ProDockItem(Icons.space_dashboard_outlined, 'Pilotage'),
                ProDockItem(
                  Icons.receipt_long_outlined,
                  'Commandes',
                  badge: fresh,
                ),
                ProDockItem(
                  restaurant
                      ? Icons.restaurant_menu_rounded
                      : Icons.inventory_2_outlined,
                  restaurant ? 'Menu' : 'Catalogue',
                ),
                const ProDockItem(Icons.person_outline, 'Profil'),
              ],
            )
          : null,
    );
  }
}
