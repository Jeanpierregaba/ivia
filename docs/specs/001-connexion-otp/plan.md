# 001 — Plan technique

## Approche

**Backend (petit ajout)** : le consentement doit être enregistré par le serveur, qui n'en garde
aujourd'hui aucune trace.
- Migration `00018` : colonne `users.privacy_consent_at timestamptz NULL`.
- `PATCH /v1/me` accepte `accept_privacy_policy: true`. Il date le consentement s'il n'en existe
  pas encore ; `false` est refusé. On retire son consentement en supprimant son compte.
- `User` expose `privacy_consent_at`.
- `profile_complete` exige désormais prénom, téléphone **et** consentement : un compte existant sans
  consentement repasse par « Faisons connaissance ». Le marchand et le livreur sont aussi concernés,
  ce qui est voulu : le consentement est demandé à tous.
- `openapi.yaml` est mis à jour dans le même commit, avec des tests Go (consentement daté une seule
  fois, `false` refusé, `profile_complete`).

**`packages/api_client`** devient un paquet Flutter. Il porte les appels HTTP, les modèles et le
jeton (comme prévu par ARCHITECTURE) :
- `IviaApiClient` construit sur `dio`, avec :
  - `requestOtp` (renvoie `resendAfter` et `expiresIn`) ;
  - `verifyOtp` (renvoie `Session` : jeton, `isNewUser`, `User`) ;
  - `getMe`, `updateMe`, `logout`.
- Un intercepteur ajoute `Authorization: Bearer` et signale les réponses 401.
- `ApiException(code, message, fields, status)` traduit le format d'erreur commun. Les coupures
  réseau et les délais dépassés deviennent `ApiException.network`, avec un message français.
  Délais : 10 s pour la connexion, 15 s pour la réponse.
- `SessionStore` range le jeton et le dernier profil reçu (JSON) dans `flutter_secure_storage`
  (Keystore Android, Keychain iOS). Rien n'est stocké en clair.
- Les journaux de dio ne sont pas activés : aucun jeton, e-mail ni code n'y figure.

**App acheteur : un état de session unique qui pilote la navigation.**
- `AuthController` (`Notifier` Riverpod) a 5 états :
  - `starting` ;
  - `signedOut` ;
  - `needsProfile(user)` ;
  - `signedIn(user)` ;
  - `offlineNoProfile` (session gardée sans profil, serveur injoignable).
- Au démarrage, il lit le `SessionStore`, puis appelle `GET /v1/me` (délai de 5 s).
- La règle `redirect` de go_router, rafraîchie à chaque changement d'état, remplace
  l'`initialLocation` de 027 :
  - `starting` ⇒ `/splash` ;
  - `signedOut` ⇒ `/onboarding` (si pas vue) ou `/login…` ;
  - `needsProfile` ⇒ `/login/profile` ;
  - `signedIn` ⇒ `/home` ;
  - `offlineNoProfile` ⇒ `/offline`.
  On ne peut donc jamais atteindre un écran qui ne correspond pas à l'état.
- `LoginFlow` (`Notifier`) garde l'adresse saisie et l'heure à partir de laquelle un code peut être
  renvoyé, de l'étape 1 à l'étape 2.
- Le splash de chargement (`/splash`) reste au moins 800 ms (027).

**Composants partagés (`packages/ui`)**, utilisables ensuite par les deux autres apps :
- `IviaLogoTile` : logo dans une tuile de couleur.
- `IviaBackButton` : bouton retour rond, blanc.
- `IviaFieldLabel` : libellé au-dessus d'un champ.
- `IviaCodeInput` : 6 cases, collage, effacement arrière.
- `IviaInfoCard` : encart d'information.
- `IviaPill` : pastille « Dernière étape ».
- `IviaLoadingSplash` : splash de chargement.

**Thème** : boutons pleins et à contour en **pilule**, de 54 dp de haut (maquettes). Champs blancs,
contour `border-input` fin au repos, Imperial de 2 dp quand le champ est actif (choix du
2026-10-31 : contraste 3:1). DESIGN.md est mis à jour en conséquence.

## Fichiers touchés

**Backend**
- `backend/db/migrations/00018_users_privacy_consent.sql`
- `backend/internal/users/queries.sql`, `service.go`, `handler.go`, `store/` (généré par sqlc)
- `backend/api/openapi.yaml`
- tests : `backend/internal/app/flows_test.go` (ou `users`)

**`mobile/packages/api_client`**
- `lib/src/client.dart`, `models.dart`, `api_exception.dart`, `session_store.dart`
- `pubspec.yaml` (`flutter`, `dio`, `flutter_secure_storage`)
- `test/` : client testé avec un faux adaptateur dio (JSON réels du contrat, erreurs, 401,
  réseau), `SessionStore` testé avec un faux stockage

**`mobile/packages/ui`**
- `lib/src/` : composants ci-dessus, `onboarding.dart` révisé (027), `theme.dart` (boutons, champs)
- tests de widget de chaque composant

**`mobile/apps/buyer`**
- `lib/app/` : `auth_controller.dart`, `router.dart` (redirect), `providers.dart` (client,
  stockage), `main.dart`
- `lib/features/splash/` (splash de chargement)
- `lib/features/onboarding/` : pages et illustrations (027)
- `lib/features/auth/` : `email_screen.dart`, `code_screen.dart`, `profile_screen.dart`,
  `login_flow.dart`, `offline_screen.dart`
- `lib/features/home/home_placeholder_screen.dart`
- `test/` : parcours complets avec un faux serveur (adaptateur dio), contrôleur et redirections
- `ios/Runner/Info.plist`, `android/.../AndroidManifest.xml` : rien à ajouter (HTTP en clair
  autorisé en debug uniquement, voir Sécurité)

**Docs** : DESIGN.md (boutons en pilule, nouveaux composants, écrans de connexion), ARCHITECTURE.md
(colonne de consentement), `AGENTS.md` (lancer l'app acheteur contre l'API locale sur le simulateur
iOS), TASKS.md.

Les apps marchand et livreur gardent leur écran de connexion provisoire. Elles profitent seulement
de la nouvelle mise en page de la présentation (027) et du thème.

## Données

Migration `00018` **non destructive** : ajout d'une colonne nullable. Sur le téléphone, le
`SessionStore` garde le jeton et le dernier profil reçu, dans le stockage sécurisé. Tout est effacé
à la déconnexion et quand le serveur refuse la session.

## API / interfaces

Routes déjà en place : `POST /v1/auth/otp`, `POST /v1/auth/verify`, `GET /v1/me`,
`POST /v1/auth/logout`. Changements de contrat :
- `PATCH /v1/me` accepte `accept_privacy_policy` ;
- `User.privacy_consent_at` ;
- `profile_complete` change de règle.

## Dépendances

Vérifiées sur pub.dev le 2026-10-31. La documentation de chaque paquet sera consultée via Context7
au moment de coder.

| Paquet | Version | Où | Pourquoi |
|---|---|---|---|
| `dio` | ^5.11.1 | `api_client` | client HTTP prévu par la stack (intercepteurs, délais) |
| `flutter_secure_storage` | ^11.2.0 | `api_client` | jeton dans le Keystore / Keychain (SECURITY) |

## Sécurité

- **Jeton** : stockage sécurisé uniquement, envoyé en en-tête, jamais journalisé (aucun intercepteur
  de logs), effacé à la déconnexion et sur 401.
- **HTTP en clair** (API locale `http://localhost:8080`) : autorisé seulement en debug.
  - iOS : l'exception ATS `NSAllowsLocalNetworking` ne vise que le réseau local.
  - Android : `usesCleartextTraffic` uniquement dans le manifeste `debug`.
  - La release impose `https` (vérification déjà présente dans `ApiConfig`).
- **OTP** : le code saisi n'est gardé qu'en mémoire, le temps de la requête.
- **Consentement** : daté par le serveur, jamais par l'app.
- **Énumération des comptes** : l'écran 2 s'affiche que l'adresse ait un compte ou non (le serveur
  répond pareil).

## Tests

- **Go** : migration, `PATCH /v1/me` avec et sans consentement, `profile_complete`, contrat OpenAPI
  (test existant).
- **`api_client`** : chaque appel avec un faux adaptateur dio, dont la traduction des erreurs (format
  commun, 401, coupure, délai) ; `SessionStore` (écriture, lecture, effacement).
- **`ui`** : `IviaCodeInput` (saisie, collage de 6 chiffres, effacement arrière, accessibilité),
  boutons en pilule, police à 200 %.
- **App acheteur** :
  - parcours complets contre un faux serveur : nouvel utilisateur, utilisateur existant,
    code faux, renvoi du code, consentement manquant, téléphone refusé, coupure réseau,
    relance avec session (valide, refusée, serveur injoignable), déconnexion ;
  - redirections du routeur pour chaque état.
- **Manuel** : parcours complet sur le simulateur iPhone 17 Pro contre l'API locale (code lu par
  `POST /v1/dev/otp` ou dans les journaux).

Les parties critiques au sens de `docs/TESTING.md` (OTP et sessions) sont côté serveur et déjà
testées. Côté app, les tests du `SessionStore` et de l'`AuthController` sont écrits avant le code.

## Risques

- **Changement de `profile_complete`** : il touche aussi les apps marchand et livreur (le
  consentement leur sera demandé). C'est voulu, mais c'est un changement de contrat que doit
  connaître le collègue backend.
- **Backend modifié par le développeur frontend** : à faire relire par le collègue backend dans la
  pull request.
- **Profil gardé sur le téléphone** (prénom, nom, e-mail, téléphone) : chiffré par le stockage
  sécurisé, effacé à la déconnexion. C'est acceptable au regard de SECURITY.
