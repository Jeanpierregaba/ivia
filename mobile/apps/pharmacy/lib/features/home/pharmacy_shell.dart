import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../alerts/alert_logic.dart';
import '../alerts/alerts_tab.dart';
import '../alerts/incoming_alert_screen.dart';
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

  /// Alertes de la première lecture : connues, pas montrées en plein écran.
  var _baseline = false;

  /// Sans push (Firebase absent), une alerte apparue à la relecture s'ouvre
  /// en plein écran (F10), une seule fois, et jamais par-dessus un autre
  /// écran (une réponse en cours de saisie).
  void _watchNewAlerts(List<InboxAlert> inbox) {
    final shown = ref.read(incomingShownProvider.notifier);
    final now = DateTime.now();
    final fresh = [
      for (final a in inbox)
        if (isNewAlert(a, now) && shown.markShown(a.alertId)) a,
    ];
    if (!_baseline) {
      _baseline = true;
      return;
    }
    if (fresh.isEmpty || ModalRoute.of(context)?.isCurrent != true) return;
    context.push(incomingAlertPath(fresh.first.alertId));
  }

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
    ref.listen(inboxProvider, (_, next) {
      if (next.value case final items?) _watchNewAlerts(items);
    });
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
          const SafeArea(bottom: false, child: AlertsTab()),
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
