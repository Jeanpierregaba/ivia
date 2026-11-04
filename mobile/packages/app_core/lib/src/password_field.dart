import 'package:flutter/material.dart';
import 'package:ivia_ui/ivia_ui.dart';

/// Champ de mot de passe : masqué, bouton œil (« Afficher le mot de passe »),
/// sans suggestions ni correction du clavier ; erreur du serveur dessous.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Mot de passe',
    this.newPassword = false,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.autofocus = false,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;

  /// Nouveau mot de passe (création, changement) : proposition du
  /// gestionnaire de mots de passe du téléphone.
  final bool newPassword;
  final String? errorText;
  final String? helperText;
  final bool enabled;
  final bool autofocus;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  var _visible = false;

  @override
  Widget build(BuildContext context) {
    return IviaFieldLabel(
      label: widget.label,
      child: TextField(
        controller: widget.controller,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        obscureText: !_visible,
        enableSuggestions: false,
        autocorrect: false,
        enableIMEPersonalizedLearning: false,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        autofillHints: [
          widget.newPassword
              ? AutofillHints.newPassword
              : AutofillHints.password,
        ],
        decoration: InputDecoration(
          errorText: widget.errorText,
          helperText: widget.helperText,
          helperMaxLines: 3,
          errorMaxLines: 3,
          suffixIcon: IconButton(
            tooltip: _visible
                ? 'Masquer le mot de passe'
                : 'Afficher le mot de passe',
            icon: Icon(
              _visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () => setState(() => _visible = !_visible),
          ),
        ),
      ),
    );
  }
}
