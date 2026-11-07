import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import 'cancel_sheet.dart';
import 'handover_screen.dart';
import 'order_done_screen.dart';

/// Commande confirmée par le client : retrait au comptoir (F15) ou livraison
/// (F17). Relue toutes les 5 s : annulation, expiration ou récupération par
/// le livreur s'affichent d'elles-mêmes.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  PharmacyOrder? _o;
  String? _error;
  var _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await ref.read(apiClientProvider).pharmacyOrder(widget.orderId);
      if (mounted) setState(() => _o = o);
    } on ApiException catch (e) {
      if (mounted && _o == null) setState(() => _error = e.message);
    }
  }

  Future<bool> _run(Future<void> Function(IviaApiClient api) action) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(apiClientProvider));
      ref
        ..invalidate(ordersProvider)
        ..invalidate(earningsProvider);
      await _load();
      return true;
    } on ApiException catch (e) {
      if (mounted) say(context, e.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// « Produits mis de côté » : commande préparée, puis la remise (F16).
  Future<void> _setAside(PharmacyOrder o) async {
    if (o.preparedAt == null &&
        !await _run((api) => api.pharmacyMarkPrepared(o.id))) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => HandoverScreen(order: _o ?? o)),
    );
    await _load();
  }

  Future<void> _cancel(PharmacyOrder o) async {
    final reason = await showCancelSheet(context);
    if (reason == null || !mounted) return;
    if (await _run((api) => api.pharmacyCancelOrder(o.id, reason)) && mounted) {
      say(context, 'Commande annulée. Le client est prévenu et remboursé.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    if (o == null) {
      return Scaffold(
        backgroundColor: P.page,
        body: SafeArea(
          child: Column(
            children: [
              const PHeader(title: 'Commande'),
              Expanded(
                child: Center(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : Padding(
                          padding: const EdgeInsets.all(P.gutter),
                          child: PErrorRetry(message: _error!),
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Livreur passé : la commande lui est remise (F19).
    if (o.delivery && (o.status == 'picked_up' || o.status == 'completed')) {
      final courier = o.courier?.firstName ?? '';
      return OrderDoneScreen(
        title: 'Commande remise au livreur',
        body:
            '${courier.isEmpty ? 'Le livreur' : courier} livre le client. Le '
            'montant est ajouté à votre relevé, sans commission.',
        rows: [('Commande', '#${o.number}')],
        totalLabel: 'À vous verser',
        totalXof: o.dueXof,
        doubleCheck: true,
      );
    }
    return o.delivery ? _delivery(o) : _pickup(o);
  }

  Widget _lines(PharmacyOrder o, {required bool prices, Widget? footer}) =>
      PCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (prices) ...[
              Text('À mettre de côté', style: PText.label),
              const SizedBox(height: 6),
            ],
            for (final (i, l) in o.lines.where((l) => l.available).indexed) ...[
              if (i > 0) const Divider(height: 1, color: P.line),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const PIcon(Icons.medication),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.name, style: PText.cardTitle),
                          Text(
                            prices
                                ? [
                                    formatXof(l.unitPriceXof),
                                    if (l.prescriptionRequired)
                                      'sur ordonnance',
                                  ].join(' · ')
                                : l.prescriptionRequired
                                ? 'Sur ordonnance'
                                : 'Sans ordonnance',
                            style: PText.bodyMuted,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '×${l.quantity}',
                      semanticsLabel: 'quantité ${l.quantity}',
                      style: PText.cardTitle,
                    ),
                  ],
                ),
              ),
            ],
            ?footer,
          ],
        ),
      );

  /// Message d'une commande terminée (annulée, expirée, remise).
  Widget? _ended(PharmacyOrder o) {
    final text = switch (o.status) {
      'cancelled' =>
        'Commande annulée${o.cancelReason.isEmpty ? '' : ' : ${o.cancelReason}'}. '
            'Le client est remboursé.',
      'expired' => "Commande expirée : le client n'est pas venu à temps.",
      'completed' => 'Commande remise au client.',
      _ => null,
    };
    if (text == null) return null;
    return PCard(
      color: o.status == 'completed' ? P.softGreen : P.softRed,
      child: Text(
        text,
        style: PText.body.copyWith(
          color: o.status == 'completed' ? P.green : P.danger,
        ),
      ),
    );
  }

  Widget _pickup(PharmacyOrder o) {
    final reserved = o.status == 'reserved';
    final prepared = o.preparedAt != null;
    final top = MediaQuery.paddingOf(context).top;
    final (title, sub) = switch (o.status) {
      'reserved' when prepared => (
        'Commande prête',
        o.expiresAt == null
            ? 'Le client vient la retirer'
            : "Le client vient la retirer avant ${hhmm(o.expiresAt!)}",
      ),
      'reserved' => (
        'Client confirmé',
        o.expiresAt == null
            ? 'Mettez les produits de côté'
            : "Mettez les produits de côté jusqu'à ${hhmm(o.expiresAt!)}",
      ),
      'completed' => ('Commande remise', 'Payée au comptoir'),
      'cancelled' => ('Commande annulée', 'Le client est remboursé'),
      _ => ('Commande expirée', 'Mise de côté terminée'),
    };
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: P.page,
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      P.gutter - 2,
                      top + 8,
                      P.gutter,
                      20,
                    ),
                    decoration: BoxDecoration(
                      color: reserved ? P.green : P.ink,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Semantics(
                              button: true,
                              label: 'Retour',
                              excludeSemantics: true,
                              child: SizedBox.square(
                                dimension: 48,
                                child: Center(
                                  child: Material(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () =>
                                          Navigator.of(context).maybePop(),
                                      child: const SizedBox.square(
                                        dimension: 44,
                                        child: Icon(
                                          Icons.arrow_back,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Commande #${o.number}',
                                textAlign: TextAlign.center,
                                style: PText.header.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 56),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                reserved ? Icons.verified : Icons.info_outline,
                                color: reserved ? P.green : P.ink,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      title,
                                      style: PText.figure.copyWith(
                                        color: Colors.white,
                                        fontSize: 24,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    sub,
                                    style: PText.body.copyWith(
                                      color: IviaPharmacyColors.onGreenMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      P.gutter,
                      14,
                      P.gutter,
                      12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_ended(o) case final ended?) ...[
                          ended,
                          const SizedBox(height: 12),
                        ],
                        PCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Mode de remise',
                                      style: PText.label,
                                    ),
                                  ),
                                  const PPill(
                                    'Retrait au comptoir',
                                    icon: Icons.storefront,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                o.prescriptionRequired
                                    ? "Le client présentera son code et l'original "
                                          "de l'ordonnance."
                                    : 'Le client présentera son code de retrait.',
                                style: PText.bodyMuted,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _lines(
                          o,
                          prices: true,
                          footer: Column(
                            children: [
                              const Divider(height: 1, color: P.line),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'À encaisser sur place',
                                      style: PText.cardTitle.copyWith(
                                        fontSize: 20,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatXof(o.itemsXof),
                                    style: PText.cardTitle.copyWith(
                                      fontSize: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (reserved)
              SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(P.gutter, 8, P.gutter, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PButton(
                        label: prepared
                            ? 'Remettre au client'
                            : 'Produits mis de côté',
                        icon: Icons.inventory_2,
                        busy: _busy,
                        onTap: () => _setAside(o),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _cancel(o),
                        style: TextButton.styleFrom(
                          foregroundColor: P.danger,
                          minimumSize: const Size(160, 48),
                          textStyle: PText.button,
                        ),
                        child: const Text('Signaler une rupture'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _delivery(PharmacyOrder o) {
    final prepared = o.preparedAt != null;
    final courier = o.courier?.firstName ?? '';
    final active = o.active;
    final step2 = switch (o.status) {
      'courier_search' => "Recherche d'un livreur",
      'awaiting_payment' => 'Livreur trouvé · paiement du client',
      _ when courier.isNotEmpty => '$courier · en route vers vous',
      _ => "Recherche d'un livreur",
    };
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: Column(
          children: [
            PHeader(title: 'Livraison #${o.number}'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(P.gutter, 4, P.gutter, 12),
                children: [
                  if (_ended(o) case final ended?) ...[
                    ended,
                    const SizedBox(height: 12),
                  ],
                  PCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Payée dans l'app",
                                style: PText.cardTitle.copyWith(fontSize: 20),
                              ),
                              Text(
                                '${formatXof(o.dueXof)} · versés sur votre '
                                'relevé',
                                style: PText.bodyMuted,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const PPill(
                          'Livraison',
                          icon: Icons.two_wheeler,
                          bg: P.softBlue,
                          fg: P.blue,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _lines(o, prices: false),
                  if (active) ...[
                    const SizedBox(height: 12),
                    IviaStepList(
                      steps: [
                        IviaStep(
                          title: 'Préparer la commande',
                          subtitle: 'Emballez et notez #${o.number}',
                          state: prepared
                              ? IviaStepState.done
                              : IviaStepState.current,
                        ),
                        IviaStep(
                          title: 'Livreur en route',
                          subtitle: step2,
                          state: !prepared
                              ? IviaStepState.upcoming
                              : courier.isEmpty
                              ? IviaStepState.current
                              : IviaStepState.done,
                        ),
                        IviaStep(
                          title: 'Remise au livreur',
                          subtitle:
                              'Le livreur confirme la récupération dans son '
                              'app',
                          state: prepared && courier.isNotEmpty
                              ? IviaStepState.current
                              : IviaStepState.upcoming,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (active && !prepared)
              PBottomBar(
                children: [
                  PButton(
                    label: 'Marquer prête',
                    busy: _busy,
                    onTap: () => _run((api) => api.pharmacyMarkPrepared(o.id)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
