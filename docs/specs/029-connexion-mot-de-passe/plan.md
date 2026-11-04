# 029 — Plan technique

## Approche

- **Aucun changement serveur** : routes de l'ADR 0011 déjà en place (`openapi.yaml`). L'app ne
  les appelle que par `packages/api_client`.
- **Écrans communs** dans `packages/app_core` (comme la 001) : chaque app ne fait que monter les
  routes et fournir sa couleur. Les écrans de la 001 (`EmailScreen`, `LoginFlow`) sont remplacés ;
  `CodeScreen` (6 cases, renvoi minuté, collage, code de développement) est gardé et paramétré par
  l'usage du code (création ou mot de passe oublié).
- **Routes communes** : `authRoutes()` (dans `app_core`) renvoie les `GoRoute` de la connexion,
  montées telles quelles par les trois routeurs :
  - `/login` (connexion) ;
  - `/login/signup`, `/login/signup/code`, `/login/signup/code/password` (création) ;
  - `/login/forgot`, `/login/forgot/code`, `/login/forgot/code/password` (mot de passe oublié).
  Le mot de passe est sous le code : le retour du système revient aux 6 cases ; quitter
  `signup` / `forgot` (`onExit`) oublie le parcours (relecture).
  La règle de redirection des apps (déconnecté ⇒ `/login` et ses sous-écrans) ne change que par
  la suppression de `Routes.code`.
- **Parcours avec code** (`AuthFlow`, Notifier, remplace `LoginFlow`) : garde en mémoire
  l'e-mail, l'usage (`signup` / `reset`), le délai de renvoi et le **code saisi** entre l'écran
  des 6 cases et celui du mot de passe (le serveur ne vérifie le code qu'avec le mot de passe).
  Rien n'est écrit sur le téléphone ; tout est effacé à la fin du parcours, au retour à
  `/login` ou à la déconnexion. Code faux ou expiré au moment du mot de passe ⇒ retour aux 6
  cases avec le message ; mot de passe refusé ⇒ message sous le champ, même écran.
- **Session** : chaque succès (`login`, `signup`, `password/reset`, `google`) passe par
  `AuthController.signedIn(session)` (inchangé) : profil incomplet ⇒ « Faisons connaissance »,
  sinon accueil de l'app.
- **Google** : interface `GoogleAuth` dans `app_core` (`signIn()` ⇒ jeton d'identité, ou `null`
  si l'utilisateur ferme la fenêtre), implémentation `google_sign_in` (`GoogleSignIn.instance`
  `.initialize(clientId, serverClientId)` puis `.authenticate()` ⇒ `authentication.idToken` ;
  `GoogleSignInExceptionCode.canceled` ⇒ `null`) et implémentation factice pour les tests
  (règle 7). Identifiants passés par `--dart-define` (`GOOGLE_SERVER_CLIENT_ID`, et
  `GOOGLE_IOS_CLIENT_ID` sur iOS) ; sans eux, `GoogleAuth.available` est faux. Le bouton
  s'affiche si `available` **et** `GET /v1/auth/providers` répond `google: true` (lu à
  l'ouverture de l'écran de connexion, gardé le temps de l'app ; échec ⇒ bouton masqué).
- **Mot de passe** : champ commun `PasswordField` (masqué, bouton œil « Afficher le mot de
  passe » / « Masquer le mot de passe », `autofillHints` `password` / `newPassword`,
  `enableSuggestions: false`, `autocorrect: false`) ; contrôleurs vidés au départ de l'écran.
  Aucune règle locale autre que « non vide » : le serveur juge (10 à 128 caractères, mots de
  passe courants, ressemblance avec l'e-mail) et l'app affiche son message.
- **Changer de mot de passe** : écran `ChangePasswordScreen` (`app_core`) ouvert depuis la ligne
  « Mot de passe » de l'écran Compte de chaque app ; « Mot de passe actuel » demandé sauf si le
  compte n'en a pas : `GET /v1/auth/session` (`SessionInfo.has_password`) lu à l'ouverture de
  l'écran (échec ⇒ champ affiché, le serveur tranche).
- **Fin de l'ancienne connexion par code** : `requestOtp` / `verifyOtp` retirés du client (plus
  aucun appelant) ; le serveur garde les routes, dépréciées (suppression : Gedeon).

## Fichiers touchés

**`packages/api_client`**
- `lib/src/models.dart` : `AuthProviders` (`password`, `google`), `SessionInfo` (`hasPassword`).
- `lib/src/client.dart` : `authProviders()`, `sessionInfo()`, `login(email, password)`, `requestSignupCode(email)`,
  `signup(email, code, password)`, `requestPasswordReset(email)`, `resetPassword(email, code,
  password)`, `signInWithGoogle(idToken)`, `changePassword(current, next)` ; retrait de
  `requestOtp` / `verifyOtp`.
- `lib/testing.dart` : `FakeAuth(server)` fidèle au module `auth` : comptes (avec ou sans mot de
  passe, Google), codes par usage (1 par minute, 10 par jour, 5 essais, expiration), connexion
  (`invalid_credentials` identique que le compte existe ou non, blocage après 10 échecs
  `account_locked`), création (`account_exists`, compte de l'ancienne connexion complété), mot de
  passe oublié (réponse identique, déconnexion des autres sessions), règles du mot de passe
  (mêmes messages que `password.go`), Google (`google_disabled`, `google_token_invalid`),
  changement de mot de passe ; requêtes enregistrées.
- `test/client_test.dart`.

**`packages/app_core`**
- `lib/src/auth_flow.dart` (remplace `login_flow.dart`).
- `lib/src/login_screen.dart` (remplace `email_screen.dart`), `signup_email_screen.dart`
  (e-mail de création et de mot de passe oublié, selon l'usage), `code_screen.dart` (paramétré),
  `new_password_screen.dart` (création et nouveau mot de passe), `change_password_screen.dart`,
  `password_field.dart`, `google_auth.dart` (interface, implémentation, fournisseur).
- `lib/src/auth_routes.dart` : chemins et `authRoutes()`.
- `pubspec.yaml` : `google_sign_in: ^7.2.0`.
- tests de chaque écran et du parcours (faux serveur, faux Google).

**Apps (acheteur, marchand, livreur)**
- `lib/app/router.dart` : `...authRoutes()` à la place des deux routes de la 001 ; `Routes.code`
  retiré ; route « mot de passe » sous l'écran Compte.
- écran Compte : acheteur `features/profile/profile_tab_screen.dart`, marchand
  `features/account/account_screen.dart`, livreur `features/home/home_placeholder_screen.dart`
  (en attendant son écran Compte) : ligne « Mot de passe ».
- tests (`app_test.dart`, `router_test.dart`) : parcours de connexion réécrits.
- iOS : schéma d'URL Google (`CFBundleURLTypes`, `REVERSED_CLIENT_ID`) ajouté **quand les
  identifiants seront fournis** (tâche à part, hors code tant qu'ils manquent) ; Android : rien
  dans le dépôt (empreinte SHA-1 déclarée dans Google Cloud).

**Docs**
- `docs/DESIGN.md` (« Connexion »), `AGENTS.md` (commande `--dart-define=GOOGLE_…` et code de
  développement pour la création de compte), `docs/specs/001-connexion-otp/spec.md` (remplacée
  en partie par la 029), `TASKS.md`.

## Données

Aucune côté app : la session reste dans `SessionStore` (stockage sécurisé, inchangé) ; aucun mot
de passe ni code stocké.

## API / interfaces

Routes existantes (ADR 0011) : `GET /v1/auth/providers`, `GET /v1/auth/session`, `POST /v1/auth/login`,
`/v1/auth/signup/code`, `/v1/auth/signup`, `/v1/auth/password/forgot`, `/v1/auth/password/reset`,
`/v1/auth/google`, `/v1/me/password`. `openapi.yaml` inchangé.

## Dépendances

- **`google_sign_in` 7.2.0** (pub.dev, éditeur vérifié flutter.dev, Flutter ≥ 3.29) : plugin
  officiel ; API 7 (`GoogleSignIn.instance.initialize`, `authenticate`, `authentication.idToken`,
  `GoogleSignInException` / `canceled`) lue dans la doc à jour (Context7, pub.dev). Android : le
  `serverClientId` (client OAuth « web ») suffit, sans `google-services.json` ; iOS : `clientId`
  iOS et schéma d'URL inversé dans `Info.plist`.

## Sécurité

- Mot de passe : jamais gardé ni journalisé, effacé des champs en quittant l'écran ; pas de
  suggestions du clavier ; envoyé seulement en HTTPS à l'API (déjà la règle du client).
- Code reçu par e-mail : en mémoire le temps du parcours seulement ; code de développement
  (`IVIA_DEV_OTP`) jamais en release (inchangé).
- Jeton Google : envoyé tel quel au serveur, qui le vérifie (ADR 0011) ; jamais gardé.
- Même message que le compte existe ou non (connexion, mot de passe oublié) : l'app n'en déduit
  rien et n'affiche rien de plus que le serveur.
- `docs/SECURITY.md` : partie authentification à relire (mots de passe et Google) ; mise à jour
  si besoin.

## Tests

**Partie critique (TESTING.md : OTP et sessions)** : le faux serveur `FakeAuth` et ses tests sont
écrits **avant** les écrans (test-writer), puis vérifiés en échec contre un client vide.

- `api_client` : chaque route (méthode, chemin, corps), modèles ; `FakeAuth` : règles listées
  ci-dessus.
- `app_core` (widgets, faux serveur et faux Google) : connexion (succès, `invalid_credentials` et
  aide « Créez votre mot de passe », `account_locked`) ; création (code, mot de passe refusé sans
  nouveau code, code faux au dernier écran ⇒ retour aux 6 cases, `account_exists`) ; mot de passe
  oublié ; Google (masqué, annulé, refusé, réussi) ; changement de mot de passe ; double appui ;
  réseau coupé ; mot de passe vidé en quittant ; police à 200 % sur 320 dp ; lecteur d'écran
  (bouton œil, erreurs).
- Apps : redirections (`router_test`), parcours complet de connexion par mot de passe dans
  chaque app (`app_test`), ligne « Mot de passe » de l'écran Compte.
- Vérification sur le simulateur contre l'API locale (comptes de démonstration avec mot de passe
  de `seed-dev`) : création de compte, connexion, mot de passe oublié, changement ; Google
  seulement quand les identifiants seront fournis.

## Risques

- **Identifiants Google absents** : bouton masqué, parcours Google non vérifiable en vrai ; la
  partie Google est testée avec le faux, puis vérifiée quand le porteur du projet fournit les
  identifiants (tâche à part dans `TASKS.md`).
- **Comptes existants sans mot de passe** : la connexion échoue (`invalid_credentials`), l'aide
  les mène à « Créer un compte » ; à annoncer aux premiers utilisateurs.
- **Taille du changement** : trois apps et les écrans communs ; découpé en tâches commitées une à
  une, l'ancienne connexion retirée en dernier.
