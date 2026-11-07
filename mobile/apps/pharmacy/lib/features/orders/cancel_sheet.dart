import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

import '../../common/ui.dart';

/// Motifs d'annulation proposés (F18) ; « Autre motif » ouvre un texte libre.
const cancelReasons = [
  'Rupture de stock imprévue',
  'Produit périmé ou endommagé',
  'Erreur sur le prix',
];
const _other = 'Autre motif';

/// Feuille « Annuler cette commande ? » (F18). Renvoie le motif choisi (ou le
/// texte saisi pour « Autre motif »), `null` si la commande est gardée.
Future<String?> showCancelSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: IviaPharmacyColors.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) => const _CancelSheet(),
    );

class _CancelSheet extends StatefulWidget {
  const _CancelSheet();

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  var _reason = cancelReasons.first;
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? get _chosen {
    if (_reason != _other) return _reason;
    final t = _text.text.trim();
    return t.length < 3 ? null : t;
  }

  Widget _option(String label) {
    final selected = _reason == label;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => setState(() => _reason = label),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? P.green : Colors.white,
                  shape: BoxShape.circle,
                  border: selected
                      ? null
                      : Border.all(
                          color: IviaPharmacyColors.checkOff,
                          width: 2,
                        ),
                ),
                alignment: Alignment.center,
                child: selected
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: PText.body.copyWith(
                    fontSize: 16,
                    color: P.ink,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: IviaPharmacyColors.disabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Semantics(
                header: true,
                child: Text(
                  'Annuler cette commande ?',
                  style: PText.heading.copyWith(fontSize: 26),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Le client est prévenu et remboursé.',
                style: PText.bodyMuted.copyWith(color: P.label),
              ),
              const SizedBox(height: 12),
              for (final r in [...cancelReasons, _other]) ...[
                const Divider(height: 1, color: P.line),
                _option(r),
              ],
              if (_reason == _other)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: TextField(
                    controller: _text,
                    autofocus: true,
                    maxLength: 200,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Précisez le motif',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              PButton(
                label: "Confirmer l'annulation",
                style: PButtonStyle.danger,
                onTap: chosen == null
                    ? null
                    : () => Navigator.of(context).pop(chosen),
              ),
              const SizedBox(height: 8),
              PButton(
                label: 'Garder la commande',
                style: PButtonStyle.soft,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
