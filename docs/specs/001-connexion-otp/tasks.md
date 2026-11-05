# 001 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

## v1 (ADR 0006 puis 0011) : faite

Code par e-mail, écrans e-mail, code et « Faisons connaissance », consentement (migration 00018).
Le détail est dans l'historique git.

## v2 (ADR 0012) : numéro, WhatsApp, SMS, jetons, TOTP admin

- [x] 1. Backend : migration 00029, connexion par numéro (code, vérification, inscription en
      attente), verrou après 5 codes faux, limites par appareil et plafond global
- [x] 2. Backend : expéditeur WhatsApp (API Cloud), secours SMS, `ChannelRouter`, configuration
- [x] 3. Backend : jetons d'accès courts et de rafraîchissement, détection de réutilisation,
      appareils connectés, alerte « nouvelle connexion », alerte admin « nouvel acheteur »
- [x] 4. Backend : changement de numéro par code
- [x] 5. Backend : application d'authentification (TOTP), codes de secours, réinitialisation par
      un autre admin ; `mfa_method` dans la session
- [x] 6. Backend : openapi.yaml, tests Go, ADR 0012
- [x] 7. `api_client` : appels v2, `SessionStore` (jeton de rafraîchissement, identifiant
      d'installation), renouvellement unique et automatique du jeton d'accès ; tests
- [x] 8. `app_core` : écrans numéro, code (WhatsApp/SMS, validation au 6e chiffre),
      « Faisons connaissance » v2, « Appareils connectés » ; mode de connexion choisi par app
      (`LoginMethod`) : le marchand et le livreur restent sur l'e-mail en attendant leurs maquettes
- [x] 9. Acheteur : connexion par numéro, Profil › Appareils connectés ; tests (191)
- [x] 10. Back-office : second facteur selon `mfa_method` (code de secours possible), page
      Sécurité (QR code généré dans le navigateur, codes de secours, sessions), « Réinitialiser la
      2FA » sur les comptes admin
- [ ] Acheteur : « Changer de numéro » (l'API est prête)
- [ ] 11. Mise en service WhatsApp : identifiants Meta et modèle approuvé (porteur du projet) ;
      choix du fournisseur SMS
