import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Motifs de refus proposés ; « Autre » demande un texte.
const rejectReasons = [
  'Produit en rupture',
  'Boutique fermée',
  'Impossible de préparer à temps',
];

/// Libellé du choix libre.
const otherReason = 'Autre';

/// Longueur maximale d'un motif saisi.
const rejectReasonMaxLength = 200;

/// « Pourquoi refusez-vous ? » : renvoie le motif choisi (ou saisi), ou
/// `null` si le marchand ferme la feuille.
Future<String?> showRejectSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            IviaSpacing.screen,
            0,
            IviaSpacing.screen,
            IviaSpacing.screen,
          ),
          child: _RejectForm(),
        ),
      ),
    );

class _RejectForm extends StatefulWidget {
  const _RejectForm();

  @override
  State<_RejectForm> createState() => _RejectFormState();
}

class _RejectFormState extends State<_RejectForm> {
  String? _choice;
  final _other = TextEditingController();

  @override
  void initState() {
    super.initState();
    _other.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  /// Motif envoyé ; `null` tant qu'il manque (aucun choix, « Autre » vide).
  String? get _reason => switch (_choice) {
    null => null,
    otherReason => _other.text.trim().isEmpty ? null : _other.text.trim(),
    final choice => choice,
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reason = _reason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Pourquoi refusez-vous ?',
            style: textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: IviaSpacing.sm),
        Text(
          "L'acheteur verra ce motif et sera remboursé.",
          style: textTheme.bodyMedium?.copyWith(
            color: IviaColors.textSecondary,
          ),
        ),
        const SizedBox(height: IviaSpacing.md),
        RadioGroup<String>(
          groupValue: _choice,
          onChanged: (value) => setState(() => _choice = value),
          child: Column(
            children: [
              for (final label in [...rejectReasons, otherReason])
                RadioListTile<String>(
                  value: label,
                  title: Text(label),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        if (_choice == otherReason) ...[
          const SizedBox(height: IviaSpacing.sm),
          TextField(
            controller: _other,
            autofocus: true,
            maxLength: rejectReasonMaxLength,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Motif',
              hintText: 'Expliquez le refus à l’acheteur',
            ),
          ),
        ],
        const SizedBox(height: IviaSpacing.lg),
        FilledButton(
          onPressed: reason == null
              ? null
              : () => Navigator.of(context).pop(reason),
          child: const Text('Refuser la commande'),
        ),
        const SizedBox(height: IviaSpacing.sm),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
      ],
    );
  }
}
