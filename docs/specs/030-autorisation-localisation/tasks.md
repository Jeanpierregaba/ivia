# 030 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

- [x] 1. `app_core` : `LocationService` (`access`, `request`, `current` qui ne demande plus) et
      `DeviceLocationService` ; mise à jour des faux services des tests des apps ; tests.
- [x] 2. `ui` : `IviaLocationRadar` (cercles, pastille centrale, 4 pastilles), mise en page
      `IviaLocationPrompt` et teinte de `IviaLogo` ; tests de rendu, police à 200 %.
- [x] 3. `app_core` : `LocationPromptCopy` dans `AppIdentity`, `LocationPromptScreen`,
      `LocationPromptStore` et `locationPromptDoneProvider`, `askForLocation` ; tests (Refuser,
      Autoriser accepté ou refusé, refus définitif qui ouvre les réglages, double appui, déjà
      autorisé, stockage illisible, retour système).
- [x] 4. App acheteur : textes et icônes, route `/location` et redirection (splash ⇒ localisation
      ⇒ présentation), `main.dart` ; écran avant « Utiliser ma position », l'alerte médicament et
      l'ajout d'une adresse ; tests (routeur, premier lancement, Accueil sans écran).
- [x] 5. App marchand : textes et icônes, route et redirection, `main.dart` ; écran avant
      l'épingle de la boutique ; tests.
- [x] 6. App livreur : textes et icônes, route et redirection, `main.dart`, permission Android ;
      écran au passage en ligne ; tests.
- [x] 7. App pharmacie : textes et icônes, route et redirection (splash ⇒ localisation ⇒
      connexion), `main.dart`, permissions iOS et Android ; écran avant l'envoi du dossier ;
      premiers tests.
- [ ] 8. `docs/DESIGN.md` ; vérification sur le simulateur iPhone 17 Pro (premier lancement des
      4 apps, une fonctionnalité par app, refus puis réglages).
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
