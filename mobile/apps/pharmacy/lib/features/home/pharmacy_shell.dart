import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../alerts/inbox_tab.dart';
import '../orders/orders_tab.dart';
import '../profile/office_tab.dart';
import '../earnings/balance_tab.dart';

/// Espace pharmacie : Alertes, Réservations, Officine, Solde.
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
    // Alertes et réservations relues en direct (les notifications push
    // complètent sur téléphone).
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

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider).value ?? const <InboxAlert>[];
    final waiting = inbox
        .where(
          (a) =>
              !a.responded &&
              a.status == 'pending' &&
              a.searchEndsAt.isAfter(DateTime.now()),
        )
        .length;
    final orders = ref.watch(ordersProvider).value ?? const <PharmacyOrder>[];
    final active = orders.where((o) => o.active).length;
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: const [InboxTab(), OrdersTab(), OfficeTab(), BalanceTab()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        indicatorColor: P.softGreen,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: waiting > 0,
              label: Text('$waiting'),
              child: const Icon(Icons.notifications_none),
            ),
            label: 'Alertes',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: active > 0,
              label: Text('$active'),
              child: const Icon(Icons.inventory_2_outlined),
            ),
            label: 'Réservations',
          ),
          const NavigationDestination(
            icon: Icon(Icons.local_pharmacy_outlined),
            label: 'Officine',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Solde',
          ),
        ],
      ),
    );
  }
}
