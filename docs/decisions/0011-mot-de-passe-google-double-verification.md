# 0011 — Connexion par mot de passe et par Google, double vérification des admins

- **Statut** : Accepté
- **Date** : 2026-11-03
- **Remplace** : la connexion par code seule de l'[ADR 0006](0006-authentification-otp-sessions.md)
  (les sessions opaques de l'ADR 0006 restent inchangées)

## Contexte

Avec l'ADR 0006, chaque connexion demandait un code reçu par e-mail. Le porteur du projet veut
une connexion classique : le code ne sert qu'à créer le compte (preuve que l'adresse est à
l'utilisateur), ensuite on se connecte avec un mot de passe, avec un parcours « mot de passe
oublié ». Les acheteurs doivent aussi pouvoir créer un compte et se connecter avec Google. Pour le
back-office, qui manipule l'argent et les comptes, un mot de passe volé ne doit pas suffire.

## Décision

- **Création de compte** : code à 6 chiffres envoyé par e-mail, puis mot de passe. Un compte créé
  par l'ancienne connexion par code reçoit son mot de passe par ce parcours.
- **Connexion** : e-mail et mot de passe. Même message (`invalid_credentials`) et même durée que
  le compte existe ou non. 10 échecs d'affilée verrouillent le compte 15 minutes (`account_locked`).
- **Mot de passe oublié** : code par e-mail puis nouveau mot de passe ; tous les appareils sont
  déconnectés et le compte est déverrouillé.
- **Mot de passe** : 10 à 128 caractères, refusé s'il fait partie des plus courants ou ressemble à
  l'e-mail ; pas de règle de composition. Haché en **Argon2id** (19 Mio, 2 passes, format PHC),
  jamais stocké ni journalisé en clair.
- **Google** : l'app envoie le jeton d'identité Google ; le serveur vérifie lui-même la signature
  (clés publiques de Google, RS256), l'émetteur, l'application (`GOOGLE_CLIENT_IDS`), l'expiration
  et l'e-mail vérifié. Le compte est retrouvé par l'identifiant Google, sinon par l'e-mail, sinon
  créé. Sans identifiants configurés, la connexion Google est désactivée et le bouton masqué.
- **Back-office** : après le mot de passe, un code reçu par e-mail (double vérification). Les
  routes admin exigent une session vérifiée (`mfa_required` sinon) ; une session vérifiée expire
  au plus 8 heures plus tard, sans prolongation.
- **Codes** : chaque code a un usage (création, mot de passe oublié, double vérification) et ne
  vaut que pour lui ; 1 code par minute et par usage, 10 par jour par adresse, 5 essais, 10 minutes.
- L'ancienne connexion par code (`POST /v1/auth/otp`, `/v1/auth/verify`) reste disponible, marquée
  dépréciée, le temps que les apps mobiles migrent ; elle n'ouvre jamais le back-office.

## Conséquences

- Nouvelles tables `auth_passwords` et `auth_identities` (module auth), usage des codes et double
  vérification des sessions (migration 00024).
- Les apps mobiles changent leurs écrans de connexion (création de compte, connexion, mot de passe
  oublié, Google) ; le back-office ajoute le mot de passe avant l'écran du code.
- Google demande un projet Google Cloud et des identifiants OAuth (Android, iOS, web) à fournir par
  le porteur du projet.
- À supprimer quand les apps auront migré : l'ancienne connexion par code.
