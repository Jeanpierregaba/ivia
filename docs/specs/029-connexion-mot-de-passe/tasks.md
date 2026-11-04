# 029 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

- [x] 1. `api_client` : modèles (`AuthProviders`, `SessionInfo`) et routes (`authProviders`,
      `sessionInfo`, `login`, `requestSignupCode`, `signup`, `requestPasswordReset`,
      `resetPassword`, `signInWithGoogle`, `changePassword`) ; tests du client.
- [x] 2. Tests du faux serveur `FakeAuth` écrits d'abord (sous-agent test-writer, partie
      critique) et vus en échec.
- [x] 3. `FakeAuth` fidèle au module `auth` : tests de la tâche 2 au vert.
- [x] 4. `app_core` : `PasswordField`, `GoogleAuth` (interface, `google_sign_in` 7.2.0, faux),
      `AuthFlow` (remplace `LoginFlow`), `CodeScreen` paramétré par l'usage ; tests.
- [x] 5. `app_core` : écran de connexion (Google si disponible, e-mail, mot de passe, « Mot de
      passe oublié ? », « Créer un compte », aide après `invalid_credentials`, `account_locked`) ;
      tests.
- [x] 6. `app_core` : création de compte et mot de passe oublié (e-mail, 6 cases, nouveau mot de
      passe, retours d'erreur) et `authRoutes()` ; tests.
- [x] 7. `app_core` : changement de mot de passe (`SessionInfo.has_password`) ; tests.
- [ ] 8. Apps acheteur, marchand, livreur : `authRoutes()`, ligne « Mot de passe » de l'écran
      Compte, tests de connexion réécrits ; retrait de `EmailScreen`, `LoginFlow`,
      `requestOtp` / `verifyOtp`.
- [ ] 9. Police à 200 % sur 320 dp et lecteur d'écran ; `docs/DESIGN.md`, `AGENTS.md`,
      `docs/SECURITY.md` (relecture), renvoi depuis la 001.
- [ ] 10. Vérification sur le simulateur contre l'API locale (création, connexion, mot de passe
      oublié, changement) ; Google laissé à la fourniture des identifiants (tâche dans `TASKS.md`).
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
