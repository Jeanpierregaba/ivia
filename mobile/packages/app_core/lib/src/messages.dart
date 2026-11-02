import 'package:flutter/material.dart';

/// Message en bas de l'écran. Avec une action, il disparaît quand même
/// après quelques secondes (sinon il suivrait la personne d'écran en écran),
/// sauf avec une aide à la navigation (lecteur d'écran, contrôle de
/// sélection), qui laisse le temps d'y arriver.
void showMessage(
  ScaffoldMessengerState messenger,
  String message, {
  SnackBarAction? action,
}) {
  final assisted =
      MediaQuery.maybeAccessibleNavigationOf(messenger.context) ?? false;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        persist: action != null && assisted,
        duration: const Duration(seconds: 6),
      ),
    );
}
