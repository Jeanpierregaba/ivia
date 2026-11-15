# 001 — Connexion et inscription (v2 : numéro de téléphone, WhatsApp, SMS)

> **Remplacée en partie par la [029](../029-connexion-mot-de-passe/spec.md)** (ADR 0011) : la
> connexion se fait par mot de passe ou Google ; le code reçu par e-mail ne sert plus qu'à créer
> le compte et au mot de passe oublié. « Faisons connaissance » et le démarrage restent valables.

## Objectif

Les acheteurs se connectent avec leur **numéro de téléphone**, sans mot de passe. Un code à
6 chiffres leur arrive par WhatsApp, ou par SMS en secours. Un nouveau numéro devient un compte
après la saisie du prénom et du nom.

- **Parcours de référence** : le schéma du porteur du projet,
  [workflow-inscription-connexion-ivia.bpmn](workflow-inscription-connexion-ivia.bpmn) (aperçu
  `.png`).
- **Décision** : [ADR 0012](../../decisions/0012-connexion-numero-whatsapp-jetons-totp.md).
- **Marchand** : même parcours ; ses maquettes viendront plus tard.
- **Back-office** : e-mail et mot de passe, puis un second facteur. Ce second facteur est
  l'application d'authentification, ou le code par e-mail tant qu'elle n'est pas activée.

La v1 (code par e-mail, puis e-mail et mot de passe, ADR 0006 et 0011) reste dans l'historique git.
Ses routes restent ouvertes le temps de la migration.

## Comportement attendu (apps mobiles)

**Démarrage** :
- session gardée ⇒ profil relu au serveur :
  - jeton d'accès expiré : renouvelé en silence ;
  - session refusée : retour à la connexion ;
- pas de session ⇒ présentation au premier lancement, puis connexion.

**1. « Votre numéro »**
- Indicatif +228 fixe et champ de 8 chiffres. Espaces et +228 sont acceptés.
- Bouton « Recevoir le code sur WhatsApp », et lien « Recevoir par SMS ».
- Mention des Conditions d'utilisation et de la Politique de confidentialité.
- L'écran est le même que le numéro ait un compte ou non.

**2. « Saisissez le code »**
- Rappel du numéro et du canal (« Envoyé sur WhatsApp au +228 90 12 34 56 »), avec « Modifier ».
- 6 cases. Coller un code ou le remplissage automatique par SMS remplit les 6 cases.
- Compte à rebours de 60 s, puis « Renvoyer le code » et « Recevoir par SMS ».
- Mention « Le code est valable 5 minutes ».
- Validation automatique au 6e chiffre.
- Si WhatsApp a échoué et que le code est parti par SMS, l'écran l'indique.

**3. « Faisons connaissance »** (nouveau numéro)
- Prénom, nom, et la case « J'accepte que ivia traite mes données selon la Politique de
  confidentialité ».
- Bouton « Créer mon compte ».
- Délai de 15 minutes après le code, sinon il faut recommencer.
- Le retour ramène à l'étape 1.

**Accueil** : il s'ouvre dès que la session est ouverte, que le compte soit nouveau ou existant.

**Profil › Sécurité**
- « Appareils connectés » : liste des sessions, avec « Déconnecter » pour chacune.
- « Changer de numéro » : code envoyé au nouveau numéro.
- « Se déconnecter de tous les appareils ».

## Comportement attendu (back-office)

1. **Connexion** : e-mail et mot de passe.
2. **Second facteur** :
   - application d'authentification activée : saisir son code (6 chiffres) ou un code de secours ;
   - sinon : code reçu par e-mail.
3. **Sécurité** (page du compte admin) :
   - activer l'application (QR code, puis un premier code) ;
   - voir les 10 codes de secours une seule fois, les régénérer, désactiver l'application ;
   - voir ses sessions ouvertes et en déconnecter une.
4. **Utilisateurs** : un admin peut réinitialiser l'application d'un autre admin (motif
   obligatoire).

## Critères d'acceptation

- [x] Étant donné un numéro valide, quand l'utilisateur demande le code, alors un code de
      6 chiffres valable 5 minutes part par WhatsApp, et la réponse indique le canal.
- [x] Étant donné WhatsApp en échec, alors le même code part par SMS.
- [x] Étant donné un numéro inconnu et le bon code, alors aucun compte n'est créé avant le nom ;
      avec le nom et le consentement, le compte est créé avec son numéro vérifié, la session
      s'ouvre et le back-office est prévenu.
- [x] Étant donné un numéro connu et le bon code, alors la session s'ouvre. Si l'appareil est
      nouveau, l'utilisateur reçoit l'alerte « Nouvelle connexion ».
- [x] Étant donné 5 codes faux, alors le code est annulé et le numéro bloqué 15 minutes. Même le
      bon code et une nouvelle demande sont refusés.
- [x] Étant donné une demande dans la minute qui suit, alors elle est refusée (`otp_rate_limited`).
- [x] Étant donné le plafond horaire global atteint, alors les demandes sont refusées et les admins
      prévenus une seule fois.
- [x] Étant donné un jeton d'accès expiré, alors l'API répond `access_token_expired`. Le jeton de
      rafraîchissement donne un nouveau couple de jetons, et l'ancien ne sert plus.
- [x] Étant donné un ancien jeton de rafraîchissement réutilisé hors du délai de grâce, alors la
      session est révoquée.
- [x] Étant donné un numéro vérifié, alors il ne change pas par le profil, seulement par un code
      envoyé au nouveau numéro.
- [x] Étant donné « Appareils connectés », quand l'utilisateur déconnecte un appareil, alors la
      session de cet appareil est refusée.
- [x] Admin : l'application d'authentification s'active avec un premier code. Ensuite, le code par
      e-mail est refusé (`mfa_use_totp`) et un code de l'application ne sert qu'une fois.
- [x] Admin : un code de secours sert une seule fois. Un autre admin peut réinitialiser
      l'application (motif, journal, sessions coupées).
- [x] Le code, le jeton, le numéro et le secret n'apparaissent ni dans les journaux (hors mode
      local) ni dans une URL.
- [x] App acheteur : écrans 1 à 3, renouvellement silencieux du jeton, appareils connectés.
- [x] Back-office : écran du second facteur selon `mfa_method`, page Sécurité.
- [ ] App acheteur : « Changer de numéro ».

## Cas limites et erreurs

Le message affiché est celui du serveur (`error.message`, en français).

**Code**
- **Code faux** (`otp_invalid`) : message, cases vidées.
- **Code expiré** (`otp_expired`) : message, l'utilisateur en redemande un.
- **Numéro bloqué** (`phone_locked`, 429, `retry_after`) : « Réessayez dans 15 minutes ».

**Envoi**
- **Trop de demandes** : `otp_rate_limited`, `otp_daily_limit`, `rate_limited`.
- **Service saturé** (`otp_service_busy`, 503) : « Réessayez dans quelques minutes ».
- **Envoi impossible** (`otp_send_failed`) : proposer le SMS.
- **Connexion par numéro fermée** (`otp_channel_unavailable`), quand WhatsApp n'est pas configuré :
  message.

**Inscription et session**
- **Inscription expirée** (`signup_expired`) : retour à l'étape 1.
- **Jeton d'accès expiré** (`access_token_expired`) : renouvellement automatique.
- **Échec du renouvellement** (`invalid_session`) : session effacée, écran de connexion.
- **Réseau coupé** : « Pas de connexion internet » ; un double appui n'envoie qu'une requête.

## Hors périmètre

- Choix du fournisseur SMS. D'ici là, pas de secours SMS hors local.
- Clés de sécurité matérielles (WebAuthn) pour les admins.
- Connexion Google sur mobile : la route reste, mais l'écran n'est pas prévu par le parcours.

## Questions ouvertes

Aucune : les valeurs par défaut sont dans l'ADR 0012 et se règlent par configuration.
