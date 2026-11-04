# 029 — Connexion par mot de passe et par Google (3 apps)

## Objectif

Faire passer les **trois apps** (acheteur, marchand, livreur) à la connexion décidée par
l'[ADR 0011](../../decisions/0011-mot-de-passe-google-double-verification.md) : le code reçu par
e-mail ne sert plus qu'à **créer le compte** et au **mot de passe oublié** ; on se connecte avec
**e-mail et mot de passe**, ou avec **Google**. Remplace la connexion par code seule de la
[001](../001-connexion-otp/spec.md) (encore acceptée par le serveur, dépréciée, à supprimer une
fois les apps migrées).

Le backend est fait (routes `/v1/auth/login`, `signup/code`, `signup`, `password/forgot`,
`password/reset`, `google`, `providers`, `/v1/me/password`) : seules les apps changent. Les écrans
sont communs (`packages/app_core`), chaque app garde sa couleur.

## Comportement attendu

**1. « Bienvenue sur ivia »** (connexion, remplace l'écran e-mail de la 001)
- **« Continuer avec Google »** en haut, puis « ou » : visible seulement si le serveur l'annonce
  disponible (`GET /v1/auth/providers`, `google: true`) ; sinon absent (pas de place vide).
- Champs **« Adresse e-mail »** et **« Mot de passe »** (masqué, bouton œil pour l'afficher), lien
  **« Mot de passe oublié ? »**, bouton **« Se connecter »**.
- En bas : **« Pas encore de compte ? Créer un compte »**, mentions légales (comme la 001).
- Échec `invalid_credentials` : « E-mail ou mot de passe incorrect. » sous le formulaire, puis
  l'aide **« Vous vous connectiez avec un code reçu par e-mail ? Créez votre mot de passe. »**
  (mène à la création de compte, e-mail déjà rempli). Champ mot de passe vidé.
- `account_locked` : message du serveur (« Trop d'essais : compte bloqué N min… ») avec le lien
  « Mot de passe oublié ? » mis en avant.

**2. Créer un compte** (trois étapes)
- « Créer un compte » : adresse e-mail, « Recevoir le code » (`signup/code`).
- « Vérifiez vos e-mails » : 6 cases (comme la 001 : collage, « Renvoyer le code » après 60 s,
  « Rien reçu ? … »), puis « Continuer ».
- « Choisissez un mot de passe » : mot de passe (œil), aide « 10 caractères au moins. Évitez un
  mot de passe courant ou proche de votre e-mail. », « Créer mon compte » (`signup` avec e-mail,
  code et mot de passe) ⇒ session ouverte ⇒ « Faisons connaissance » si le profil est incomplet
  (001), sinon accueil.
- Refus du mot de passe (`validation_failed` sur `password`) : message du serveur sous le champ,
  le code reste valable (même écran). Code faux ou expiré à cette étape : retour aux 6 cases avec
  le message.
- `account_exists` (compte qui a déjà un mot de passe) : message du serveur et bouton « Se
  connecter » (e-mail rempli).
- Un compte créé par l'ancienne connexion par code passe par ce même parcours (le serveur lui
  ajoute le mot de passe).

**3. Mot de passe oublié**
- « Mot de passe oublié » : adresse e-mail (reprise de l'écran de connexion), « Recevoir le
  code » (`password/forgot` : même réponse que le compte existe ou non).
- 6 cases, puis « Nouveau mot de passe » (mêmes règles), « Changer le mot de passe »
  (`password/reset`) ⇒ session ouverte, tous les autres appareils déconnectés, compte débloqué ;
  message « Mot de passe changé. ».

**4. Google**
- « Continuer avec Google » ouvre la fenêtre Google du téléphone ; le jeton d'identité est envoyé
  au serveur (`/v1/auth/google`), qui ouvre la session (compte retrouvé ou créé).
- Fenêtre fermée par l'utilisateur : rien ne se passe, aucun message.
- `google_token_invalid`, échec de Google ou réseau : message, l'écran reste.
- Nouveau compte Google : « Faisons connaissance » (prénom, nom, téléphone, consentement), comme
  après une création de compte.

**5. Changer de mot de passe** (écran Compte de chaque app : « Profil » de l'acheteur, « Compte »
du marchand, écran du livreur)
- Ligne **« Mot de passe »** ⇒ écran : « Mot de passe actuel » (absent pour un compte créé avec
  Google qui n'en a pas encore), « Nouveau mot de passe », « Enregistrer » (`/v1/me/password`).
- Réussite : « Mot de passe changé. Vos autres appareils sont déconnectés. » ; mot de passe actuel
  faux : message sous le champ.

**Communs** : mots de passe jamais gardés sur le téléphone, jamais journalisés, effacés des champs
en quittant l'écran ; boutons désactivés pendant l'envoi ; « Pas de connexion internet » sur
erreur réseau (comme la 001).

## Critères d'acceptation

- [ ] Connexion : e-mail et mot de passe envoyés à `/v1/auth/login` ; succès ⇒ session gardée et
      même suite que la 001 (profil incomplet ⇒ « Faisons connaissance », sinon accueil de
      l'app).
- [ ] `invalid_credentials` : message, champ mot de passe vidé, aide « Créez votre mot de passe »
      qui ouvre la création avec l'e-mail rempli ; `account_locked` : message du serveur.
- [ ] Création de compte : code demandé à `signup/code`, 6 cases, puis mot de passe envoyé à
      `signup` avec l'e-mail et le code ; session ouverte ; mot de passe refusé ⇒ message sous le
      champ sans redemander de code ; `account_exists` ⇒ message et « Se connecter ».
- [ ] Mot de passe oublié : `password/forgot`, 6 cases, nouveau mot de passe à `password/reset` ;
      session ouverte, message « Mot de passe changé. ».
- [ ] « Continuer avec Google » n'apparaît que si `providers.google` est vrai ; jeton envoyé à
      `/v1/auth/google` ; annulation par l'utilisateur ⇒ aucun message ; refus ⇒ message.
- [ ] Changer de mot de passe depuis l'écran Compte de chaque app (`/v1/me/password`) ;
      « Mot de passe actuel » absent si le compte n'en a pas.
- [ ] Les trois apps utilisent ces écrans (couleur de chaque app), sans la connexion par code
      seule (`/v1/auth/otp` + `/v1/auth/verify` plus appelés).
- [ ] Aucun mot de passe ni code dans les journaux, le stockage du téléphone ou une URL.
- [ ] Police à 200 % sur 320 dp et lecteur d'écran : champs étiquetés, bouton œil lu (« Afficher
      le mot de passe »), erreurs annoncées.

## Cas limites et erreurs

- **Codes** : `otp_rate_limited` (1 par minute et par usage), `otp_daily_limit`, `otp_invalid`,
  `otp_expired`, `otp_too_many_attempts` : messages du serveur, comme la 001.
- **Double appui** sur un bouton : une seule requête.
- **Réseau coupé** : message, saisie gardée (sauf le mot de passe après un refus).
- **Session ancienne (connexion par code)** : reste valable ; rien à refaire tant qu'elle n'expire
  pas.
- **Admin** : les apps ne gèrent pas la double vérification (réservée au back-office) ; un compte
  admin se connecte dans les apps comme un autre.
- **Google sans identifiants** (`google_disabled`) : bouton absent ; si le serveur répond quand
  même `google_disabled`, message.
- **Retour arrière** au milieu d'un parcours : retour à l'étape précédente, rien n'est envoyé.

## Hors périmètre

- Double vérification dans les apps (back-office seulement, ADR 0011).
- Connexion par WhatsApp ou SMS (après validation de Meta, voir `TASKS.md`).
- Suppression de l'ancienne connexion par code côté serveur (Gedeon, une fois les apps publiées).
- Identifiants Google OAuth (Android, iOS, web) : à fournir par le porteur du projet ; sans eux, le
  bouton reste masqué.

## Questions ouvertes

Aucune (tranchées le 2026-11-04 : écran de connexion avec lien « Créer un compte » ; Google dans
les trois apps ; comptes existants via « Créer un compte » ; « Changer mon mot de passe » dans
l'écran Compte).
