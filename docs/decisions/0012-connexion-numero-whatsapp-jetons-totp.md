# 0012 — Connexion par numéro (WhatsApp, SMS), jetons de rafraîchissement, application d'authentification pour les admins

- **Statut** : Accepté
- **Date** : 2026-11-05
- **Remplace** : pour les apps mobiles, la connexion par e-mail et mot de passe de
  l'[ADR 0011](0011-mot-de-passe-google-double-verification.md). Pour le back-office, l'ADR 0011
  reste valable (e-mail, mot de passe, double vérification), complété ici par l'application
  d'authentification.

## Contexte

Le porteur du projet a fourni le parcours cible de connexion des acheteurs
(`docs/specs/001-connexion-otp/workflow-inscription-connexion-ivia.bpmn`). Ce parcours repose sur
le numéro de téléphone. Le code part par WhatsApp, le SMS servant de secours, et il n'y a pas de
mot de passe. Au Togo, le numéro mobile est l'identifiant que tout le monde a, contrairement à
l'e-mail. Le marchand suivra le même parcours (maquettes à venir). Pour le back-office, il veut
un niveau « pro » : un code par e-mail ne protège pas d'une boîte mail compromise.

## Options envisagées

**Apps mobiles**
- **Garder e-mail et mot de passe** : déjà fait. Mais beaucoup d'acheteurs n'utilisent pas l'e-mail,
  et les mots de passe sont oubliés ou réutilisés.
- **Numéro et code (WhatsApp, puis SMS)** : identifiant naturel. Coût par code, et le SMS est exposé
  à la fraude (envoi massif vers des numéros surtaxés), d'où des limites strictes.

**Sessions**
- **Jeton unique de longue durée** : simple, mais un jeton volé sert 60 jours.
- **Jeton d'accès court et jeton de rafraîchissement changé à chaque usage** : c'est ce que demande
  le parcours. Un vol se détecte quand l'ancien jeton revient.

**Second facteur admin**
- **Code par e-mail** : déjà fait, mais dépend de la boîte mail.
- **Application d'authentification (TOTP, RFC 6238)** : standard, gratuite, hors ligne.
- **Clés de sécurité (WebAuthn)** : la plus solide, mais demande du matériel ; plus tard si besoin.

## Décision

**Connexion des apps mobiles par numéro**
- **Code** : 6 chiffres, valable 5 minutes, à usage unique, haché (HMAC). Il part par WhatsApp (API
  Cloud de Meta, modèle d'authentification approuvé) ; si l'envoi échoue, le même code part par
  SMS. L'app peut aussi demander le SMS directement.
- **Limites** :
  - 1 code par minute et 10 par jour par numéro ;
  - 10 codes par heure par appareil, et une limite haute par IP (IP partagées des opérateurs) ;
  - un plafond global horaire (`PHONE_CODES_PER_HOUR`) : au-delà, les demandes sont refusées et les
    admins sont prévenus.
  - 5 codes faux annulent le code et bloquent le numéro 15 minutes.
- **Pas de compte avant la preuve du numéro** : un numéro inconnu reçoit un jeton d'inscription
  (15 minutes, usage unique). Le compte n'est créé qu'avec le prénom, le nom et le consentement,
  et le back-office est alors prévenu.
- **Même réponse** à la demande de code, que le numéro ait un compte ou non.
- **Appareils** : l'app envoie un identifiant d'installation tiré au hasard, gardé haché côté
  serveur. Un appareil inconnu d'un compte qui en a déjà déclenche l'alerte « Nouvelle connexion ».
  L'utilisateur voit ses appareils connectés et peut en déconnecter un.
- **Sessions** :
  - jeton d'accès de 15 minutes, jeton de rafraîchissement changé à chaque usage ;
  - un ancien jeton présenté plus de 30 secondes après son remplacement révoque la session ;
  - la session est révocable à tout moment ;
  - les sessions sans jeton de rafraîchissement (back-office) gardent leur fonctionnement.
- **Le numéro vérifié est l'identifiant** : il ne change qu'avec un code envoyé au nouveau
  numéro.

**Back-office**
- **Connexion** : e-mail et mot de passe (ADR 0011), puis un second facteur.
- **Application d'authentification** : un admin connecté (code par e-mail validé) active une appli
  d'authentification. Elle remplace alors le code par e-mail, sans retour possible à l'e-mail.
  - Le secret est chiffré en base (AES-GCM, clé dérivée de `AUTH_SECRET`).
  - Un code ne sert qu'une fois, et 10 essais au plus par heure.
  - 10 codes de secours à usage unique servent en cas de téléphone perdu.
- **Réinitialisation** : un autre admin peut réinitialiser l'application (motif obligatoire, action
  journalisée, sessions coupées).

## Conséquences

- **Migration 00029** (additive) :
  - numéro vérifié ;
  - verrous des numéros, inscriptions en attente, appareils ;
  - jetons de rafraîchissement ;
  - application d'authentification et codes de secours.
- **Mise en service de WhatsApp** :
  - le porteur fournit l'identifiant du numéro expéditeur (`WHATSAPP_PHONE_NUMBER_ID`) et un jeton
    système (`WHATSAPP_ACCESS_TOKEN_FILE`) ;
  - il fait approuver par Meta un modèle « authentification » (`WHATSAPP_TEMPLATE`) ;
  - le numéro expéditeur n'est jamais écrit dans le code.
- **Fournisseur SMS** : à choisir. D'ici là, `SMS_SENDER=none` : sans WhatsApp, pas de code.
- **Local** : codes dans le journal et lisibles par `POST /v1/dev/otp`. Aucun envoi réel.
- **Apps mobiles** : elles renouvellent le jeton d'accès sur `access_token_expired`, un seul
  renouvellement à la fois.
- **Routes ADR 0011 conservées** : connexion par e-mail et mot de passe, et Google, pour le
  back-office et le temps de la migration des apps. L'ancienne connexion par code e-mail (ADR 0006)
  reste dépréciée.
- **Point d'attention** : un compte créé avant cet ADR avec un numéro saisi mais jamais vérifié est
  retrouvé par ce numéro à la première connexion par code, qui le vérifie. C'est voulu : le code
  prouve que la personne détient le numéro.
