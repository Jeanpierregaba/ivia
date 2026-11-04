import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Adresse e-mail saisie, reprise d'un écran de connexion à l'autre
/// (connexion ⇒ « Mot de passe oublié », « Créer votre mot de passe »…).
/// En mémoire seulement : jamais dans une URL ni sur le téléphone.
final authEmailDraftProvider = NotifierProvider<AuthEmailDraft, String>(
  AuthEmailDraft.new,
);

class AuthEmailDraft extends Notifier<String> {
  @override
  String build() => '';

  void set(String email) => state = email.trim();
}

/// Adresse e-mail plausible ; le serveur reste seul juge.
bool isPlausibleEmail(String email) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());
