# RULES — Interdits stricts

Interdits que personne (agent ou développeur) ne doit enfreindre, quelle que soit la demande.
Les préférences de style sont dans `AGENTS.md`. Les règles imposées techniquement (permissions et
hooks dans `.claude/settings.json`) sont marquées [bloqué].

## Code et dépendances
- Ne jamais ajouter une dépendance sans vérifier qu'elle existe, qu'elle est maintenue et qu'elle est
  bien celle attendue (nom exact : attention aux paquets aux noms proches).
- Ne jamais désactiver un test, une règle de lint ou une vérification de type pour « faire passer ».
- Ne jamais laisser de code mort, de `console.log` de debug ou de TODO sans entrée dans `TASKS.md`.

## Secrets
- Jamais de secret, clé ou mot de passe en dur dans le code, les tests ou les docs.
- Ne jamais lire ni modifier les fichiers `.env` réels. [bloqué]
- Toute nouvelle variable d'environnement est ajoutée (sans valeur) à `.env.example`.

## Données
- Ne jamais exécuter de migration destructive (suppression de table, de colonne, de données)
  sans confirmation explicite de l'utilisateur.
- Ne jamais se connecter à la base de production depuis l'environnement de développement.

## Git
- Ne jamais réécrire l'historique partagé (`push --force`, `reset --hard` sur une branche poussée). [bloqué]
- Ne jamais committer directement sur la branche principale une fois le projet en production.

## Spécifiques au projet

**Argent et commandes**
- Ne jamais marquer un paiement réussi ni faire avancer une commande payée ailleurs que dans le
  traitement du webhook vérifié ou la revérification par l'API du prestataire.
- Ne jamais changer le statut d'une commande en dehors de la machine à états du module `orders`.
- Ne jamais modifier ni supprimer une ligne de `order_status_events`, `payment_events`, `refunds`,
  `admin_audit_log`, ni un relevé `settlements` marqué réglé. On corrige par une nouvelle ligne.
- Ne jamais utiliser de nombre à virgule (`float`, `double`, `numeric` avec décimales) pour un montant.
- Ne jamais appeler la vraie API de paiement, ni envoyer un vrai e-mail, WhatsApp ou SMS depuis
  les tests ou l'environnement local : utiliser les implémentations factices.

**Accès et données personnelles**
- Ne jamais attribuer les rôles `driver` ou `admin` par l'inscription ou par une route
  accessible à un non-admin.
- Ne jamais renvoyer le numéro ou l'adresse d'un acheteur à un livreur hors de sa mission en cours,
  ni à un marchand.
- Ne jamais écrire de donnée personnelle (numéro complet, e-mail, adresse, position), de code OTP,
  de jeton ou de donnée de paiement dans les logs, Sentry ou une URL. Seule exception : la
  position arrondie à environ 110 m des recherches « autour de moi », sans journalisation des
  paramètres d'URL ([ADR 0010](decisions/0010-position-arrondie-dans-les-recherches.md)).
- Ne jamais placer de clé de service (prestataire de paiement, Brevo, R2, Firebase admin) dans une
  app mobile ou dans du code exécuté par le navigateur. Seule la clé Google Maps, restreinte aux
  apps, est embarquée.
- Ne jamais rendre public le bucket des documents des livreurs.

**Architecture**
- Ne jamais accéder à la base depuis une app mobile ou depuis le back-office Next.js.
- Ne jamais lire ou écrire les tables d'un autre module backend.
- Ne jamais appeler une API Google payante (Directions, Geocoding, Places…) sans un ADR qui
  l'accepte et chiffre son coût.
- Ne jamais modifier un ADR accepté : en écrire un nouveau qui le remplace.

**Collaboration**
- Dès l'arrivée du second développeur, tout changement passe par une branche et une pull request
  relue par l'autre ; pas de push direct sur `main` ni sur `develop`.
- Flux de branches :
  - `main` : version stable, ne reçoit que des fusions de `develop` ;
  - `develop` : intégration, reçoit les pull requests des branches de travail ;
  - une branche de travail par développeur (`jeanpierre`…) ou par fonctionnalité
    (`feat/001-otp-login`…), créée depuis `develop` et mise à jour depuis `develop` avant la PR.
- Une pull request n'est fusionnée que si la CI est verte.
