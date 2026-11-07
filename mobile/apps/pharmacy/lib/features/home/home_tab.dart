import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import '../alerts/alert_detail_screen.dart';
import '../alerts/alert_logic.dart';

/// Ligne sous le nom : la garde en cours (« De garde · 20:00 → 08:00 »),
/// sinon l'ouverture.
String dutyLine(
  PharmacyProfile p,
  List<({String id, DateTime startsAt, DateTime endsAt})> shifts,
  DateTime now,
) {
  if (p.onDuty) {
    for (final s in shifts) {
      if (!s.startsAt.isAfter(now) && s.endsAt.isAfter(now)) {
        return 'De garde · ${hhmm(s.startsAt)} → ${hhmm(s.endsAt)}';
      }
    }
    if (p.dutyUntil case final until?) {
      return "De garde jusqu'à ${hhmm(until)}";
    }
    return 'De garde';
  }
  if (p.open24h) return 'Ouverte 24 h/24';
  return p.isOpen ? 'En service' : 'Hors service';
}

/// Accueil (F09) : en-tête vert (nom, garde, « En service », chiffres du
/// jour), alertes à traiter, commandes à préparer.
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({
    super.key,
    required this.onSeeAlerts,
    required this.onSeeOrders,
  });
  final VoidCallback onSeeAlerts;
  final VoidCallback onSeeOrders;

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  var _busy = false;

  Future<void> _setOpen(PharmacyProfile p, bool open) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .setPharmacyStatus(
            isOpen: open,
            onDuty: p.onDuty,
            open24h: p.open24h,
          );
      ref.invalidate(pharmacyProfileProvider);
    } on ApiException catch (e) {
      if (mounted) say(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(pharmacyProfileProvider).value;
    final inboxValue = ref.watch(inboxProvider);
    final inbox = inboxValue.value ?? const <InboxAlert>[];
    final orders = ref.watch(ordersProvider).value ?? const <PharmacyOrder>[];
    final shifts = ref.watch(shiftsProvider).value ?? const [];
    final now = DateTime.now();
    final open = inbox.where((a) => isOpenAlert(a, now)).toList()
      ..sort((a, b) => a.searchEndsAt.compareTo(b.searchEndsAt));
    final toPrepare =
        orders
            .where((o) => o.status == 'reserved' && o.preparedAt == null)
            .toList()
          ..sort(
            (a, b) => (a.expiresAt ?? a.createdAt).compareTo(
              b.expiresAt ?? b.createdAt,
            ),
          );
    final error = errorOf(inboxValue);
    if (p == null) return const Center(child: CircularProgressIndicator());
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: RefreshIndicator(
        color: P.green,
        onRefresh: () async {
          ref
            ..invalidate(inboxProvider)
            ..invalidate(ordersProvider)
            ..invalidate(pharmacyProfileProvider);
        },
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _Header(
              profile: p,
              line: dutyLine(p, shifts, now),
              stats: todayStats(inbox, now),
              busy: _busy,
              onOpen: (v) => _setOpen(p, v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(P.gutter, 20, P.gutter, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            'Alertes à traiter',
                            style: PText.figure.copyWith(fontSize: 20),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onSeeAlerts,
                        style: TextButton.styleFrom(foregroundColor: P.green),
                        child: Text(
                          'Tout voir',
                          style: PText.button.copyWith(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (error != null)
                    PErrorRetry(message: error)
                  else if (open.isEmpty)
                    const PEmpty(
                      icon: Icons.notifications_none,
                      text:
                          'Aucune alerte à traiter. Les nouvelles alertes '
                          'apparaissent ici en direct.',
                    ),
                  for (final a in open)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AlertCard(alert: a),
                    ),
                  if (toPrepare.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _OrdersCard(orders: toPrepare, onTap: widget.onSeeOrders),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.line,
    required this.stats,
    required this.busy,
    required this.onOpen,
  });

  final PharmacyProfile profile;
  final String line;
  final ({int received, int responded, int confirmed}) stats;
  final bool busy;
  final ValueChanged<bool> onOpen;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final receiving = p.isOpen || p.onDuty || p.open24h;
    final top = MediaQuery.paddingOf(context).top;
    Widget kpi(int value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: P.greenDeep,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Semantics(
          container: true,
          label: '$value $label',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value', style: PText.figure.copyWith(color: Colors.white)),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PText.body.copyWith(
                  color: IviaPharmacyColors.onGreenMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(P.gutter, top + 26, P.gutter, 18),
      decoration: const BoxDecoration(
        color: P.green,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IviaLogoTile(
                size: 44,
                color: Colors.white.withValues(alpha: 0.16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        p.name,
                        style: PText.figure.copyWith(
                          color: Colors.white,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    Text(
                      line,
                      style: PText.body.copyWith(
                        color: IviaPharmacyColors.onGreenMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            decoration: BoxDecoration(
              color: P.greenDeep,
              borderRadius: BorderRadius.circular(P.radius),
            ),
            child: MergeSemantics(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.isOpen ? 'En service' : 'Hors service',
                          style: PText.cardTitle.copyWith(color: Colors.white),
                        ),
                        Text(
                          receiving
                              ? 'Vous recevez les alertes'
                              : "Vous ne recevez pas d'alertes",
                          style: PText.body.copyWith(
                            color: IviaPharmacyColors.onGreenMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PSwitch(
                    value: p.isOpen,
                    onColor: IviaPharmacyColors.switchOn,
                    onChanged: busy ? null : onOpen,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              kpi(stats.received, 'Alertes'),
              const SizedBox(width: 8),
              kpi(stats.responded, 'Répondues'),
              const SizedBox(width: 8),
              kpi(stats.confirmed, 'Confirmées'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Carte d'une alerte ouverte : bord rouge, « Nouvelle », compte à rebours,
/// puis « Voir » et « Répondre ».
class AlertCard extends StatelessWidget {
  const AlertCard({super.key, required this.alert});
  final InboxAlert alert;

  void _open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AlertDetailScreen(alertId: alert.alertId),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final a = alert;
    return PCard(
      border: P.red,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  'Reçue à ${hhmm(a.receivedAt)}',
                  style: PText.cardTitle.copyWith(fontSize: 18),
                ),
              ),
              if (!a.seen) ...[
                const SizedBox(width: 8),
                const PPill('Nouvelle', bg: P.softRed, fg: P.red),
              ],
              const Spacer(),
              const SizedBox(width: 8),
              PCountdownPill(deadline: a.searchEndsAt),
            ],
          ),
          const SizedBox(height: 10),
          Text(alertSummary(a), style: PText.body.copyWith(fontSize: 16)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: PButton(
                  label: 'Voir',
                  style: PButtonStyle.soft,
                  height: 44,
                  onTap: () => _open(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: PButton(
                  label: 'Répondre',
                  height: 44,
                  onTap: () => _open(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrdersCard extends StatelessWidget {
  const _OrdersCard({required this.orders, required this.onTap});
  final List<PharmacyOrder> orders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = orders.length;
    final first = orders.first;
    return Semantics(
      button: true,
      child: PCard(
        onTap: onTap,
        child: Row(
          children: [
            const PIcon(Icons.inventory_2, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$n commande${n > 1 ? 's' : ''} à préparer',
                    style: PText.cardTitle,
                  ),
                  Text(
                    [
                      'Client confirmé',
                      if (first.expiresAt case final until?)
                        'mis de côté → ${hhmm(until)}',
                    ].join(' · '),
                    style: PText.bodyMuted,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: P.muted),
          ],
        ),
      ),
    );
  }
}
