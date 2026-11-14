import 'package:flutter/material.dart';

/// Indicateur d'envoi affiché dans un bouton pendant une requête.
class ButtonProgress extends StatelessWidget {
  const ButtonProgress({super.key, this.label = 'Envoi en cours'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5, semanticsLabel: label),
    );
  }
}
