# 001 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

- [x] 1. Backend : migration 00018, `PATCH /v1/me` (`accept_privacy_policy`), `privacy_consent_at`,
      règle de `profile_complete`, openapi.yaml ; tests Go
- [x] 2. `api_client` : tests puis `ApiException`, modèles, `IviaApiClient` (dio, faux adaptateur
      en test)
- [x] 3. `api_client` : tests puis `SessionStore` (stockage sécurisé)
- [x] 4. `ui` : thème (boutons en pilule, champs), `IviaLogoTile`, `IviaBackButton`,
      `IviaFieldLabel`, `IviaInfoCard`, `IviaPill`, `IviaLoadingSplash` ; tests
- [x] 5. `ui` : `IviaCodeInput` (saisie, collage, effacement, accessibilité) ; tests
- [x] 6. `ui` : présentation révisée (027) : en-tête, carte d'illustration, titre avec partie rouge ;
      marchand et livreur adaptés ; tests
- [x] 7. Acheteur : illustrations des 3 pages (027) ; le splash de chargement est branché avec la tâche 8
- [x] 8. Acheteur : tests puis `AuthController` et routeur (`redirect`)
- [x] 9. Acheteur : écran e-mail
- [x] 10. Acheteur : écran du code (renvoi, erreurs)
- [x] 11. Acheteur : écran « Faisons connaissance », accueil provisoire, écran hors ligne
- [ ] 12. Acheteur : HTTP local autorisé en debug (iOS, Android) ; parcours complet sur le simulateur
      iPhone 17 Pro contre l'API locale
- [ ] 13. Docs : DESIGN.md, ARCHITECTURE.md, AGENTS.md, TASKS.md
- [ ] Vérifier tous les critères d'acceptation de spec.md (et ceux ajoutés à 027)
- [ ] Relecture par le sous-agent reviewer
