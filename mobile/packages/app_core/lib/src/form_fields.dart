import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

import 'legal_text.dart';
import 'phone_format.dart';

/// Numéro mobile togolais : indicatif +228 fixe, 8 chiffres par paires.
class TogoPhoneField extends StatelessWidget {
  const TogoPhoneField({
    super.key,
    required this.label,
    required this.controller,
    this.enabled = true,
    this.helperText,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final String? helperText;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return IviaFieldLabel(
      label: label,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumberNational],
        inputFormatters: [TogoPhoneFormatter()],
        decoration: InputDecoration(
          prefixIcon: const _PhonePrefix(),
          hintText: '90 12 34 56',
          helperText: helperText,
          helperMaxLines: 2,
          errorText: errorText,
          errorMaxLines: 3,
        ),
      ),
    );
  }
}

class _PhonePrefix extends StatelessWidget {
  const _PhonePrefix();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: IviaSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: IviaSpacing.lg),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: IviaColors.border)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+228',
            style: Theme.of(context).textTheme.titleSmall,
            semanticsLabel: 'Indicatif plus 2 2 8',
          ),
        ],
      ),
    );
  }
}

/// Case de consentement au traitement des données, avec le lien vers la
/// Politique de confidentialité.
class ConsentCheckbox extends StatelessWidget {
  const ConsentCheckbox({
    super.key,
    required this.value,
    required this.error,
    required this.onChanged,
  });

  final bool value;
  final String? error;

  /// `null` : case désactivée (envoi en cours).
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              isError: error != null,
              onChanged: onChanged == null ? null : (v) => onChanged!(v!),
              // Le texte à côté est lu ensuite, avec son lien.
              semanticLabel: 'Accord pour le traitement de mes données',
            ),
            const SizedBox(width: IviaSpacing.xs),
            Expanded(
              child: GestureDetector(
                onTap: onChanged == null ? null : () => onChanged!(!value),
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LegalText(
                    style: textTheme.bodyMedium?.copyWith(
                      color: IviaColors.textSecondary,
                    ),
                    parts: const [
                      LegalPart(
                        "J'accepte que ivia traite mes données selon la ",
                      ),
                      LegalPart.link('Politique de confidentialité'),
                      LegalPart('.'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: textTheme.bodySmall?.copyWith(color: IviaColors.error),
              ),
            ),
          ),
      ],
    );
  }
}
