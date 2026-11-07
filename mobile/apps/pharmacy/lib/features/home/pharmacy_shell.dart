import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../alerts/alert_logic.dart';
import '../alerts/inbox_tab.dart';
import '../orders/orders_tab.dart';
import '../profile/office_tab.dart';
import 'home_tab.dart';

/// Espace pharmacie : Accueil, Alertes, Commandes, Profil, dans une barre
/// flottante (F09). Alertes et commandes sont relues toutes les 5 s (le
/// push complète sur téléphone).
class PharmacyShell extends ConsumerStatefulWidget {
  const PharmacyShell({super.key});

  @override
  ConsumerState<PharmacyShell> createState() => _PharmacyShellState();
}

class _PharmacyShellState extends ConsumerState<PharmacyShell> {
  var _tab = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      ref
        ..invalidate(inboxProvider)
        ..invalidate(ordersProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _go(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider).value ?? const <InboxAlert>[];
    final now = DateTime.now();
    final unseen = inbox.where((a) => isNewAlert(a, now)).length;
    return Scaffold(
      backgroundColor: P.page,
      extendBody: true,
      body: IndexedStack(
        index: _tab,
        children: [
          HomeTab(onSeeAlerts: () => _go(1), onSeeOrders: () => _go(2)),
          const SafeArea(bottom: false, child: InboxTab()),
          const SafeArea(bottom: false, child: OrdersTab()),
          const SafeArea(bottom: false, child: OfficeTab()),
        ],
      ),
      bottomNavigationBar: IviaBottomNav(
        currentIndex: _tab,
        onSelected: _go,
        items: [
          const IviaNavItem(icon: Icons.home_rounded, label: 'Accueil'),
          IviaNavItem(
            icon: Icons.notifications_none_rounded,
            label: 'Alertes',
            badge: unseen,
            badgeLabel: unseen > 1 ? '$unseen nouvelles' : '1 nouvelle',
          ),
          const IviaNavItem(
            icon: Icons.inventory_2_outlined,
            label: 'Commandes',
          ),
          const IviaNavItem(
            icon: Icons.person_outline_rounded,
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
