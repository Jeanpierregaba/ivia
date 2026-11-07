import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';
import 'order_done_screen.dart';

/// Remise au comptoir (F16) : code du client à 4 chiffres, original de
/// l'ordonnance vu, paiement reçu. Le code n'est gardé que le temps de
/// l'envoi.
class HandoverScreen extends ConsumerStatefulWidget {
  const HandoverScreen({super.key, required this.order});
  final PharmacyOrder order;

  @override
  ConsumerState<HandoverScreen> createState() => _HandoverScreenState();
}

class _HandoverScreenState extends ConsumerState<HandoverScreen> {
  final _code = TextEditingController();
  var _sawPrescription = false;
  var _paid = false;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _ready =>
      _code.text.length == 4 &&
      _paid &&
      (_sawPrescription || !widget.order.prescriptionRequired);

  Future<void> _validate() async {
    final o = widget.order;
    final code = _code.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).pharmacyCompletePickup(o.id, code);
      // Le code saisi n'est pas gardé.
      _code.clear();
      ref
        ..invalidate(ordersProvider)
        ..invalidate(earningsProvider);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OrderDoneScreen(
            title: 'Commande remise au client',
            body:
                'La commande est terminée. Le client a payé au comptoir, '
                'sans commission ivia.',
            rows: [
              ('Commande', '#${o.number}'),
              ('Remise à', hhmm(DateTime.now())),
            ],
            totalLabel: 'Encaissé sur place',
            totalXof: o.itemsXof,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _code.clear();
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final rx = [
      for (final l in o.lines)
        if (l.available && l.prescriptionRequired) l.name,
    ];
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: Column(
          children: [
            PHeader(
              title: 'Remise #${o.number}',
              trailing: o.expiresAt == null
                  ? null
                  : Semantics(
                      label: "Mise de côté jusqu'à ${hhmm(o.expiresAt!)}",
                      excludeSemantics: true,
                      child: PPill(
                        '→ ${hhmm(o.expiresAt!)}',
                        bg: P.softRed,
                        fg: P.red,
                      ),
                    ),
              onBack: _busy ? () {} : null,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(P.gutter, 4, P.gutter, 12),
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Code de retrait du client',
                      style: PText.heading,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Demandez au client son code à 4 chiffres.',
                    style: PText.body.copyWith(color: P.label),
                  ),
                  const SizedBox(height: 16),
                  IviaCodeInput(
                    controller: _code,
                    length: 4,
                    autofocus: true,
                    autofill: false,
                    enabled: !_busy,
                    hasError: _error != null,
                    semanticLabel: 'Code de retrait à 4 chiffres',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: PText.body.copyWith(color: P.danger),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  PCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        if (o.prescriptionRequired) ...[
                          PCheckRow(
                            value: _sawPrescription,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _sawPrescription = v),
                            label: "J'ai vu l'original de l'ordonnance",
                          ),
                          const Divider(height: 1, color: P.line),
                        ],
                        PCheckRow(
                          value: _paid,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _paid = v),
                          label:
                              'Le client a payé ${formatXof(o.itemsXof)} sur place',
                        ),
                      ],
                    ),
                  ),
                  if (rx.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    PCard(
                      color: P.softYellow,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ExcludeSemantics(
                            child: Icon(
                              Icons.assignment_late,
                              color: P.yellow,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              rx.length == 1
                                  ? '${rx.single} est délivré sur ordonnance.'
                                  : '${rx.join(', ')} sont délivrés sur '
                                        'ordonnance.',
                              style: PText.body.copyWith(color: P.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PBottomBar(
              children: [
                PButton(
                  label: 'Valider la remise',
                  busy: _busy,
                  onTap: _ready ? _validate : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
