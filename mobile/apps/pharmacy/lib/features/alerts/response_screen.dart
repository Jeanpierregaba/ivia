import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/providers.dart';
import '../../common/ui.dart';

/// Prix saisi en francs : chiffres seuls, groupés par milliers (« 1 250 »).
class _PriceFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final out = StringBuffer();
    for (var i = 0; i < trimmed.length; i++) {
      if (i > 0 && (trimmed.length - i) % 3 == 0) out.write(' ');
      out.write(trimmed[i]);
    }
    final text = out.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

int _digits(String s) => int.tryParse(s.replaceAll(RegExp(r'\D'), '')) ?? 0;

String _grouped(int n) => n == 0
    ? ''
    : _PriceFormatter()
          .formatEditUpdate(
            TextEditingValue.empty,
            TextEditingValue(text: '$n'),
          )
          .text;

/// Une ligne de la réponse : produit demandé (ou ajouté, ordonnance en photo
/// seule), disponibilité, prix, quantité, générique, ordonnance.
class _Line {
  _Line({
    this.itemId,
    required this.requested,
    required this.requestedQty,
    String name = '',
    int price = 0,
    int? quantity,
    this.available = true,
    this.prescription = false,
    String generic = '',
  }) : name = TextEditingController(text: name),
       price = TextEditingController(text: _grouped(price)),
       quantity = TextEditingController(text: '${quantity ?? requestedQty}'),
       generic = TextEditingController(text: generic);

  /// `null` : produit ajouté par la pharmacie (ordonnance en photo seule).
  final String? itemId;
  final String requested;
  final int requestedQty;
  final TextEditingController name, price, quantity, generic;
  bool available, prescription;

  bool get added => itemId == null;
  int get unitPrice => _digits(price.text);
  int get qty => _digits(quantity.text);

  /// Quantité acceptée par le serveur : 1 à 100.
  bool get qtyValid => qty >= 1 && qty <= 100;

  /// Nom envoyé : le générique proposé, sinon le produit demandé.
  String get sentName {
    if (added) return name.text.trim();
    final g = generic.text.trim();
    return g.isEmpty ? requested : g;
  }

  bool get complete =>
      !available || (unitPrice > 0 && qtyValid && sentName.length >= 2);

  ResponseLineDraft toDraft() => ResponseLineDraft(
    alertItemId: itemId,
    name: sentName,
    quantity: qty,
    unitPriceXof: available ? unitPrice : 0,
    available: available,
    prescriptionRequired: available && prescription,
  );

  void dispose() {
    for (final c in [name, price, quantity, generic]) {
      c.dispose();
    }
  }
}

/// Réponse à une alerte (F13) : une carte par produit, total indicatif des
/// produits disponibles, puis « Réponse envoyée » (F14).
class ResponseScreen extends ConsumerStatefulWidget {
  const ResponseScreen({super.key, required this.alertId});
  final String alertId;

  @override
  ConsumerState<ResponseScreen> createState() => _ResponseScreenState();
}

class _ResponseScreenState extends ConsumerState<ResponseScreen> {
  InboxAlert? _alert;
  final _lines = <_Line>[];
  var _busy = false;
  var _expired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final a = await ref
          .read(apiClientProvider)
          .pharmacyInboxItem(widget.alertId);
      if (!mounted) return;
      final previous = a.responded ? a.myLines : const <MedLine>[];
      setState(() {
        _alert = a;
        _lines.addAll([
          for (final (i, item) in a.items.indexed)
            _fromItem(item, _sentFor(item, i, previous)),
          if (a.items.isEmpty)
            for (final l in previous)
              _Line(
                requested: '',
                requestedQty: 1,
                name: l.name,
                price: l.unitPriceXof,
                quantity: l.quantity,
                available: l.available,
                prescription: l.prescriptionRequired,
              ),
          // Ordonnance en photo seule : une ligne vide à remplir.
          if (a.items.isEmpty && previous.isEmpty)
            _Line(requested: '', requestedQty: 1),
        ]);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Ligne déjà envoyée pour ce produit : même nom, sinon même position (un
  /// générique a changé le nom).
  MedLine? _sentFor(InboxAlertItem item, int i, List<MedLine> previous) {
    for (final l in previous) {
      if (l.name == item.name) return l;
    }
    return i < previous.length ? previous[i] : null;
  }

  _Line _fromItem(InboxAlertItem item, MedLine? sent) => _Line(
    itemId: item.id,
    requested: item.name,
    requestedQty: item.quantity,
    price: sent?.unitPriceXof ?? 0,
    quantity: sent?.quantity,
    available: sent?.available ?? true,
    prescription: sent?.prescriptionRequired ?? false,
    generic: sent != null && sent.name != item.name ? sent.name : '',
  );

  int get _total => _lines
      .where((l) => l.available)
      .fold(0, (sum, l) => sum + l.unitPrice * l.qty);

  Future<void> _send() async {
    final a = _alert!;
    setState(() {
      _busy = true;
      _error = null;
    });
    final drafts = [for (final l in _lines) l.toDraft()];
    try {
      await ref.read(apiClientProvider).pharmacyRespond(widget.alertId, drafts);
      ref.invalidate(inboxProvider);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResponseSentScreen(
            receivedAt: a.receivedAt,
            available: drafts.where((d) => d.available).length,
            count: drafts.length,
            totalXof: _total,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.fields.values.firstOrNull ?? e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _alert;
    final available = _lines.where((l) => l.available).length;
    final canSend =
        a != null &&
        !_expired &&
        available > 0 &&
        _lines.every((l) => l.complete);
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: Column(
          children: [
            PHeader(
              title: 'Votre réponse',
              trailing: a == null
                  ? null
                  : PCountdownPill(
                      deadline: a.searchEndsAt,
                      onExpired: () => setState(() => _expired = true),
                    ),
            ),
            Expanded(
              child: a == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(P.gutter),
                              child: PErrorRetry(
                                message: _error!,
                                onRetry: () {
                                  setState(() => _error = null);
                                  _load();
                                },
                              ),
                            ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        P.gutter,
                        4,
                        P.gutter,
                        12,
                      ),
                      children: [
                        for (final l in _lines)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _LineCard(
                              line: l,
                              genericAccepted: a.genericAccepted,
                              enabled: !_busy && !_expired,
                              onChanged: () => setState(() {}),
                              onRemove: l.added && _lines.length > 1
                                  ? () => setState(() {
                                      _lines.remove(l);
                                      l.dispose();
                                    })
                                  : null,
                            ),
                          ),
                        if (a.items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: PButton(
                              label: 'Ajouter un produit',
                              icon: Icons.add,
                              style: PButtonStyle.outline,
                              height: 48,
                              onTap: _busy || _lines.length >= 30
                                  ? null
                                  : () => setState(
                                      () => _lines.add(
                                        _Line(requested: '', requestedQty: 1),
                                      ),
                                    ),
                            ),
                          ),
                        PCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total indicatif',
                                      style: PText.bodyMuted,
                                    ),
                                    Text(
                                      formatXof(_total),
                                      style: PText.figure.copyWith(
                                        fontSize: 24,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              PPill(
                                '$available / ${_lines.length} disponible'
                                '${available > 1 ? 's' : ''}',
                              ),
                            ],
                          ),
                        ),
                        if (_expired)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'Alerte terminée : la réponse ne peut plus partir.',
                              style: PText.body.copyWith(color: P.danger),
                            ),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: PText.body.copyWith(color: P.danger),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            if (a != null)
              PBottomBar(
                children: [
                  PButton(
                    label: a.responded
                        ? 'Mettre à jour la réponse'
                        : 'Envoyer la réponse',
                    icon: Icons.send,
                    busy: _busy,
                    onTap: canSend ? _send : null,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.genericAccepted,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final _Line line;
  final bool genericAccepted, enabled;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  /// Champ gris des maquettes (F13).
  static InputDecoration _input({String? suffix, String? hint}) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      filled: true,
      fillColor: P.page,
      hintText: hint,
      suffixText: suffix,
      suffixStyle: PText.label.copyWith(color: P.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: P.green, width: 2),
      ),
    );
  }

  Future<void> _editGeneric(BuildContext context) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) =>
          _GenericDialog(initial: line.generic.text, requested: line.requested),
    );
    if (value == null) return;
    line.generic.text = value;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l = line;
    final title = l.added
        ? IviaFieldLabel(
            label: 'Produit',
            child: TextField(
              controller: l.name,
              enabled: enabled,
              maxLength: 160,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => onChanged(),
              decoration: _input(hint: 'Nom et dosage')
                  .copyWith(counterText: ''),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.requested, style: PText.cardTitle.copyWith(fontSize: 18)),
              Text('Demandé : ${l.requestedQty}', style: PText.small),
            ],
          );
    final availability = MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              l.available ? 'Disponible' : 'Indisponible',
              style: PText.button.copyWith(
                fontSize: 16,
                color: l.available ? P.green : P.muted,
              ),
            ),
          ),
          PSwitch(
            value: l.available,
            onChanged: enabled
                ? (v) {
                    l.available = v;
                    onChanged();
                  }
                : null,
          ),
        ],
      ),
    );
    final remove = onRemove == null
        ? null
        : IconButton(
            tooltip: 'Retirer ce produit',
            onPressed: enabled ? onRemove : null,
            icon: const Icon(Icons.close, color: P.muted),
          );
    // Police très agrandie : la disponibilité passe sous le nom.
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 13;
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stacked) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                ?remove,
              ],
            ),
            Align(alignment: Alignment.centerLeft, child: availability),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                const SizedBox(width: 8),
                availability,
                ?remove,
              ],
            ),
          if (l.available) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: IviaFieldLabel(
                    label: 'Prix unitaire',
                    child: TextField(
                      controller: l.price,
                      enabled: enabled,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_PriceFormatter()],
                      onChanged: (_) => onChanged(),
                      decoration: _input(suffix: 'F', hint: '0'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: IviaFieldLabel(
                    label: 'Quantité',
                    child: TextField(
                      controller: l.quantity,
                      enabled: enabled,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      onChanged: (_) => onChanged(),
                      decoration: _input().copyWith(
                        errorText: l.qtyValid ? null : '1 à 100',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (genericAccepted && !l.added)
              Semantics(
                button: true,
                label: l.generic.text.isEmpty
                    ? 'Proposer un générique'
                    : 'Générique : ${l.generic.text}, modifier',
                excludeSemantics: true,
                child: InkWell(
                  onTap: enabled ? () => _editGeneric(context) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_horiz, size: 20, color: P.green),
                        const SizedBox(width: 10),
                        if (l.generic.text.isEmpty)
                          Expanded(
                            child: Text(
                              'Proposer un générique',
                              style: PText.button.copyWith(
                                fontSize: 15,
                                color: P.green,
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: 'Générique :  ',
                                children: [
                                  TextSpan(
                                    text: l.generic.text,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: P.ink,
                                    ),
                                  ),
                                ],
                              ),
                              style: PText.body.copyWith(color: P.label),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            PCheckRow(
              value: l.prescription,
              onChanged: enabled
                  ? (v) {
                      l.prescription = v;
                      onChanged();
                    }
                  : null,
              label: 'Délivré sur ordonnance uniquement',
            ),
          ],
        ],
      ),
    );
  }
}

/// Nom du générique proposé ; « Aucun » le retire.
class _GenericDialog extends StatefulWidget {
  const _GenericDialog({required this.initial, required this.requested});
  final String initial, requested;

  @override
  State<_GenericDialog> createState() => _GenericDialogState();
}

class _GenericDialogState extends State<_GenericDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Générique proposé'),
    content: TextField(
      controller: _c,
      autofocus: true,
      maxLength: 160,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(hintText: widget.requested),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, ''),
        child: const Text('Aucun'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _c.text.trim()),
        child: const Text('Valider'),
      ),
    ],
  );
}

/// Réponse envoyée (F14) : produits disponibles, total, « Retour aux
/// alertes ».
class ResponseSentScreen extends StatelessWidget {
  const ResponseSentScreen({
    super.key,
    required this.receivedAt,
    required this.available,
    required this.count,
    required this.totalXof,
  });

  final DateTime receivedAt;
  final int available, count, totalXof;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: PText.body.copyWith(color: P.label)),
          ),
          Text(value, style: PText.cardTitle.copyWith(fontSize: 16)),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: P.page,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: P.gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DoneBadge(),
                      const SizedBox(height: 22),
                      Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text('Réponse envoyée', style: PText.heading),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Si le client confirme votre pharmacie, vous recevrez '
                        'une notification. Vos prix sont engageants pendant la '
                        'mise de côté.',
                        style: PText.bodyMuted.copyWith(
                          fontSize: 16,
                          color: P.label,
                        ),
                      ),
                      const SizedBox(height: 22),
                      PCard(
                        child: Column(
                          children: [
                            row('Alerte', 'Reçue à ${hhmm(receivedAt)}'),
                            row('Produits disponibles', '$available / $count'),
                            row('Total indicatif', formatXof(totalXof)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PBottomBar(
              children: [
                PButton(
                  label: 'Retour aux alertes',
                  style: PButtonStyle.outline,
                  onTap: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
